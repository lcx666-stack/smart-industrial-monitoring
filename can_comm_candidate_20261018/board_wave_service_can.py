#!/usr/bin/env python3
"""Independent 50 kHz DMA recorder and four-channel waveform source.

Only this process opens the exclusive DMA device. The native black-box
scanner saves two seconds before/after PL fault and ADC error events. A
desktop viewer may disconnect without stopping the recorder.
"""

import argparse
import ctypes
import hashlib
import json
import os
import queue
import signal
import socket
import subprocess
import sys
import threading
import time

BOOT = '/mnt/sdboot'
SOCKET = '/data/ethernet_control_20261014/wave-service.sock'
CAN_EVENT_SOCKET = '/data/ethernet_control_20261014/can-events.sock'
ENVELOPE_LIBRARY = '/data/ethernet_control_20261014/lib_board_wave_envelope.so'
NATIVE_LIBRARY = '/data/vibration_blackbox_candidate_20261018/lib_motor_wave_stats.so'
NATIVE_SHA256 = 'bf5532d6dc6214b146e63641988edf4057fc7ec212aafffece1e0f2af4a063ac'
MOTOR_STOP = '/data/motor_anomaly_candidate_20261017/motor_open_loop_pwm10_anomaly.py'
MOTOR_STOP_SHA256 = 'affbb6e5de7ca3a69dd52a48e4ff73b6b4bcda15e94ea78604e07b73fe69532b'
VIBRATION_TRIP_RAW = 7000
STOP = False
MANUAL = False


def notify_can(message):
    """Best-effort fault notification; never waits for CAN or touches DMA."""
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as client:
            client.setblocking(False)
            client.sendto(json.dumps(message, separators=(',', ':')).encode('utf-8'),
                          CAN_EVENT_SOCKET)
    except (OSError, ValueError):
        pass  # Event JSON is still discoverable by the CAN service after save.


def request_stop(_number, _frame):
    global STOP
    STOP = True


def request_manual(_number, _frame):
    global MANUAL
    MANUAL = True


class Viewer:
    """Non-blocking display fan-out: a slow GUI can never stall DMA draining."""

    def __init__(self, path):
        self.path = path
        self.pending = queue.Queue(maxsize=2)
        self.stop = threading.Event()
        if os.path.exists(path):
            os.unlink(path)
        self.listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.listener.bind(path)
        os.chmod(path, 0o600)
        self.listener.listen(1)
        self.listener.settimeout(.2)
        self.thread = threading.Thread(target=self.run, daemon=True)
        self.thread.start()

    def publish(self, packet):
        try:
            self.pending.put_nowait(packet)
        except queue.Full:
            try:
                self.pending.get_nowait()
            except queue.Empty:
                pass
            self.pending.put_nowait(packet)

    def run(self):
        client = None
        while not self.stop.is_set():
            if client is None:
                try:
                    client, _ = self.listener.accept()
                    client.settimeout(.05)
                except socket.timeout:
                    continue
                except OSError:
                    break
            try:
                packet = self.pending.get(timeout=.1)
            except queue.Empty:
                continue
            try:
                client.sendall(packet)
            except (OSError, socket.timeout):
                client.close()
                client = None
        if client is not None:
            client.close()

    def close(self):
        self.stop.set()
        self.listener.close()
        self.thread.join(timeout=2)
        if os.path.exists(self.path):
            os.unlink(self.path)
        if self.thread.is_alive():
            raise RuntimeError('viewer socket did not close')


class EnvelopeState(ctypes.Structure):
    _fields_ = [('count', ctypes.c_uint32),
                ('low', ctypes.c_int32 * 4),
                ('high', ctypes.c_int32 * 4)]


class NativeEnvelope:
    """Batch the 50 kHz per-frame work in C so DMA draining stays ahead."""

    def __init__(self, path=ENVELOPE_LIBRARY):
        library = ctypes.CDLL(path)
        library.board_wave_env_abi.argtypes = []
        library.board_wave_env_abi.restype = ctypes.c_uint32
        library.board_wave_env_state_size.argtypes = []
        library.board_wave_env_state_size.restype = ctypes.c_size_t
        if (library.board_wave_env_abi() != 1 or
                library.board_wave_env_state_size() != ctypes.sizeof(EnvelopeState)):
            raise RuntimeError('native waveform envelope ABI mismatch')
        library.board_wave_env_ingest.argtypes = [
            ctypes.POINTER(EnvelopeState), ctypes.c_void_p, ctypes.c_size_t,
            ctypes.POINTER(ctypes.c_int32), ctypes.c_size_t,
            ctypes.POINTER(ctypes.c_size_t)]
        library.board_wave_env_ingest.restype = ctypes.c_int
        self.library = library
        self.state = EnvelopeState()

    def ingest(self, data):
        if not data or len(data) % 32:
            raise ValueError('invalid waveform batch length')
        capacity = (self.state.count + len(data) // 32) // 100
        output = (ctypes.c_int32 * max(1, capacity * 8))()
        written = ctypes.c_size_t()
        source = ctypes.c_char_p(data)
        result = self.library.board_wave_env_ingest(
            ctypes.byref(self.state), ctypes.cast(source, ctypes.c_void_p),
            len(data), output, capacity, ctypes.byref(written))
        if result or written.value != capacity:
            raise RuntimeError('native waveform envelope failed: {}'.format(result))
        return [[output[index * 8 + channel] for channel in range(8)]
                for index in range(written.value)]


class VibrationLatch:
    """Send the existing PL operator STOP without blocking the DMA reader."""

    def __init__(self):
        self.pending = False
        self.previous_high = False
        self.thread = None

    def observe(self, bins):
        for row in bins:
            # Each 2 ms bin retains the maximum of all 100 raw ADC frames.
            high = max(row[3], row[5], row[7]) >= VIBRATION_TRIP_RAW
            rising = high and not self.previous_high
            self.previous_high = high
            if rising and not self.pending:
                self.pending = True
                print('WAVE_VIBRATION_TRIP raw_ge={}; requesting PL operator STOP'.format(
                    VIBRATION_TRIP_RAW), flush=True)
                self.thread = threading.Thread(target=self._run_stop, daemon=True)
                self.thread.start()

    def _run_stop(self):
        try:
            self._stop()
        finally:
            self.pending = False

    def _stop(self):
        try:
            with open(MOTOR_STOP, 'rb') as source:
                digest = hashlib.sha256()
                for block in iter(lambda: source.read(1024 * 1024), b''):
                    digest.update(block)
            if digest.hexdigest() != MOTOR_STOP_SHA256:
                raise RuntimeError('approved motor STOP script hash mismatch')
            result = subprocess.run([sys.executable, '-B', MOTOR_STOP, '--stop'],
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    stdin=subprocess.DEVNULL, timeout=8, check=False)
            output = result.stdout.decode('utf-8', 'replace')
            if result.returncode or 'operator stop latched' not in output:
                raise RuntimeError(output[-700:])
            print('WAVE_VIBRATION_STOP_CONFIRMED: ' + output.strip(), flush=True)
        except Exception as error:
            print('WAVE_SERVICE_FAIL: vibration STOP not confirmed; '
                  'physically cut motor VM: {}'.format(error), flush=True)

    def close(self):
        if self.thread is not None:
            self.thread.join(timeout=9)
            if self.thread.is_alive():
                raise RuntimeError('vibration STOP worker did not finish')


class Envelope:
    """2 ms min/max per channel, preserving peaks from every raw ADC frame."""

    def __init__(self, viewer, recorder, latch=None, native=None):
        self.viewer = viewer
        self.recorder = recorder
        self.latch = latch
        self.native = native if native is not None else NativeEnvelope()
        self.bins = []

    def ingest(self, data, health):
        bins = self.native.ingest(data)
        if self.latch is not None:
            self.latch.observe(bins)
        self.bins.extend(bins)
        while len(self.bins) >= 50:
            packet = {'kind': 'wave', 'bin_ms': 2, 'bins': self.bins[:50],
                      'seq_gaps': self.recorder.sequence_gaps,
                      'dropped': health['dropped']}
            self.viewer.publish((json.dumps(packet, separators=(',', ':')) + '\n').encode())
            del self.bins[:50]


def main():
    global MANUAL
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', required=True)
    args = parser.parse_args()
    if not os.path.ismount(BOOT):
        raise RuntimeError('SD BOOT must be mounted read-only')
    with open(NATIVE_LIBRARY, 'rb') as source:
        native_hash = hashlib.sha256()
        for block in iter(lambda: source.read(1024 * 1024), b''):
            native_hash.update(block)
    if native_hash.hexdigest() != NATIVE_SHA256:
        raise RuntimeError('raw vibration scanner library hash mismatch')
    os.environ['MOTOR_WAVE_STATS_LIBRARY'] = NATIVE_LIBRARY
    sys.path.insert(0, BOOT)
    from motor_blackbox import BatchBlackBoxRecorder, EventWriter, WaveDevice
    for number, handler in ((signal.SIGTERM, request_stop),
                            (signal.SIGINT, request_stop),
                            (signal.SIGUSR1, request_manual)):
        signal.signal(number, handler)
    recorder = BatchBlackBoxRecorder(args.output_dir, 100000, 100000, 50000)
    # Match the motor's PS trip rule on every 50 kHz DMA frame.  The deployed
    # native scanner has no raw-code rule, so require the extension explicitly.
    raw_abi = getattr(recorder.scanner.library, 'motor_wave_raw_vibration_abi', None)
    if raw_abi is None:
        raise RuntimeError('native scanner lacks raw vibration threshold support')
    raw_abi.argtypes = []
    raw_abi.restype = ctypes.c_uint32
    if raw_abi() != 1:
        raise RuntimeError('native raw vibration threshold ABI mismatch')
    recorder.scanner.detector.vibration_threshold = VIBRATION_TRIP_RAW
    recorder.scanner.detector.enabled |= 4
    native_start_event = recorder._start_event

    def announce_start_event(*parameters, **options):
        result = native_start_event(*parameters, **options)
        current = recorder.event
        if current is not None:
            notify_can({'kind': 'trigger', 'output_dir': args.output_dir,
                        'trigger_seq': current.get('trigger_seq'),
                        'reason': current.get('reason'),
                        'created_utc': current.get('created_utc')})
        return result

    recorder._start_event = announce_start_event
    device = WaveDevice('/dev/motor_wave_dma')
    try:
        writer = EventWriter()
        try:
            viewer = Viewer(SOCKET)
        except Exception:
            writer.close()
            raise
    except Exception:
        device.close()
        raise
    recorder.event_sink = writer.submit
    latch = VibrationLatch()
    envelope = Envelope(viewer, recorder, latch)
    initial = None
    try:
        initial = device.status()
        recorder.seed_counters_before_start(initial)
        device.start()
        started_at = time.monotonic()
        last_frames_at = started_at
        ready = False
        last_health = initial
        last_check = started_at
        while not STOP:
            data = device.read()
            if data:
                recorder.ingest_batch(data)
                envelope.ingest(data, last_health)
                last_frames_at = time.monotonic()
                if not ready and recorder.frames >= 500:
                    ready = True
                    print('WAVE_SERVICE_READY pid={} blackbox_dir={} '
                          'vibration_raw_ge=7000 frames={}'.format(
                              os.getpid(), args.output_dir, recorder.frames),
                          flush=True)
            if MANUAL:
                MANUAL = False
                recorder.request_trigger()
            now = time.monotonic()
            if not ready and now - started_at >= 2:
                raise RuntimeError('ADC DMA produced fewer than 500 valid frames '
                                   'within 2 seconds of start')
            if ready and now - last_frames_at >= 1:
                raise RuntimeError('ADC DMA sample stream stalled for 1 second')
            if now - last_check >= .1 or not data:
                last_health = device.status()
                writer.check()
                recorder.observe_status(last_health)
                if last_health['flags'] & 8:
                    raise RuntimeError('DMA hardware fault')
                if (recorder.sequence_gaps or recorder.tick_mismatches or
                        last_health['dropped'] or
                        last_health['adc_errors'] != initial['adc_errors']):
                    raise RuntimeError('ADC DMA integrity fault; inspect saved event')
                if recorder.event_count >= 64:
                    raise RuntimeError('64-event storage budget reached; preserve logs')
                if not data and not (last_health['flags'] & 3):
                    raise RuntimeError('DMA stopped unexpectedly')
                last_check = now
            if not data:
                time.sleep(.001)
        device.stop()
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            data = device.read()
            if data:
                recorder.ingest_batch(data)
                continue
            status = device.status()
            if not (status['flags'] & 3) and status['produced'] == status['consumed']:
                break
            time.sleep(.005)
        else:
            raise RuntimeError('DMA drain timeout')
        status = device.status()
        recorder.observe_status(status)
        if (recorder.sequence_gaps or recorder.tick_mismatches or status['dropped'] or
                status['adc_errors'] != initial['adc_errors']):
            raise RuntimeError('waveform integrity fault')
    finally:
        try:
            device.stop()
        finally:
            try:
                recorder.flush()
                writer.close()
            finally:
                device.close()
                viewer.close()
                latch.close()
    print('WAVE_SERVICE_STOPPED frames={} events={} saved={}; DMA released, storage flushed'.format(
        recorder.frames, recorder.event_count, writer.saved_count), flush=True)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        notify_can({'kind': 'writer_failed', 'reason': str(error)[:180]})
        print('WAVE_SERVICE_FAIL: ' + str(error), file=sys.stderr, flush=True)
        sys.exit(1)
