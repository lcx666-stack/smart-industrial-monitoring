#!/usr/bin/env python3
"""Continuously record PL DMA frames and persist fault-centred waveforms.

Requires the motor_wave_dma kernel device; does not write arbitrary DDR through
/dev/mem. No motor-control command is issued by this program.
"""
import argparse
import collections
import datetime
import hashlib
import json
import math
import os
import queue
import signal
import struct
import sys
import threading
import time
import uuid
try:
    import fcntl
except ImportError:  # Permit frame/black-box unit tests on Windows.
    fcntl = None

FRAME = struct.Struct("<hhhhIIQiI")
STATUS = struct.Struct("<10I")
FRAME_MAGIC = 0x314D5246
FRAME_SIZE = FRAME.size
IOCTL_START = (ord("W") << 8) | 1
IOCTL_STOP = (ord("W") << 8) | 2
IOCTL_STATUS = 0x80000000 | (STATUS.size << 16) | (ord("W") << 8) | 3


def decode_frame(raw):
    if len(raw) != FRAME_SIZE:
        raise ValueError("Incomplete waveform frame")
    current_raw, v1, v2, v3, seq, flags, ticks, current_ma, magic = FRAME.unpack(raw)
    if magic != FRAME_MAGIC or not (flags & 1):
        raise ValueError("Bad waveform frame magic/valid flag")
    return {"current_raw": current_raw, "vibration": (v1, v2, v3),
            "seq": seq, "flags": flags, "ticks": ticks,
            "current_ma": current_ma}


def write_event(output_dir, name, event, sample_rate, sequence_gaps,
                incomplete):
    os.makedirs(output_dir, exist_ok=True)
    binary_path = os.path.join(output_dir, name + ".bin")
    metadata_path = os.path.join(output_dir, name + ".json")
    frame_count = sum(len(block) // FRAME_SIZE for block in event["frames"])
    if any(len(block) % FRAME_SIZE for block in event["frames"]):
        raise ValueError("Event contains a partial waveform frame")
    digest = hashlib.sha256()
    with open(binary_path, "xb", buffering=65536) as output:
        for block in event["frames"]:
            output.write(block)
            digest.update(block)
        output.flush()
        os.fsync(output.fileno())
    metadata = {key: value for key, value in event.items()
                if key not in ("frames", "post_remaining")}
    metadata.update({"format": "FRM1", "frame_bytes": FRAME_SIZE,
                     "sample_rate_hz_nominal": sample_rate,
                     "frame_count": frame_count,
                     "binary_bytes": frame_count * FRAME_SIZE,
                     "binary_sha256": digest.hexdigest(),
                     "incomplete": incomplete,
                     "sequence_gaps_total": sequence_gaps,
                     "binary_file": os.path.basename(binary_path)})
    with open(metadata_path, "x", encoding="utf-8") as output:
        json.dump(metadata, output, ensure_ascii=False, indent=2)
        output.flush()
        os.fsync(output.fileno())
    return binary_path


class EventWriter(object):
    """Keep SD-card fsync latency off the time-critical DMA read loop."""
    def __init__(self):
        self.pending = queue.Queue(maxsize=4)
        self.failure = None
        self.saved_count = 0
        self.closed = False
        self.worker = threading.Thread(target=self._run, name="blackbox-writer")
        self.worker.daemon = True
        self.worker.start()

    def _run(self):
        while True:
            job = self.pending.get()
            try:
                if job is None:
                    return
                if self.failure is None:
                    path = write_event(*job)
                    self.saved_count += 1
                    print("Saved fault waveform:", path, flush=True)
            except Exception as error:
                self.failure = error
            finally:
                self.pending.task_done()

    def check(self):
        if self.failure is not None:
            raise RuntimeError("black-box storage failed: {}".format(
                self.failure))

    def submit(self, *job):
        if self.closed:
            raise RuntimeError("black-box writer is closed")
        self.check()
        try:
            self.pending.put(job, timeout=0.1)
        except queue.Full:
            raise RuntimeError("black-box storage queue is full")
        return os.path.join(job[0], job[1] + ".bin")

    def close(self, timeout=15.0):
        if self.closed:
            self.check()
            return
        deadline = time.monotonic() + timeout
        try:
            self.pending.put(None, timeout=timeout)
        except queue.Full:
            raise RuntimeError("black-box writer shutdown queue timeout")
        self.worker.join(max(0.0, deadline - time.monotonic()))
        if self.worker.is_alive():
            raise RuntimeError("black-box writer shutdown timeout; storage not confirmed")
        self.closed = True
        self.check()


class WaveDevice(object):
    def __init__(self, path):
        if fcntl is None:
            raise RuntimeError("motor_wave_dma is only available on Linux")
        self.fd = os.open(path, os.O_RDWR | os.O_NONBLOCK)

    def close(self):
        if self.fd is not None:
            os.close(self.fd)
            self.fd = None

    def start(self):
        fcntl.ioctl(self.fd, IOCTL_START)

    def stop(self):
        fcntl.ioctl(self.fd, IOCTL_STOP)

    def status(self):
        buffer = bytearray(STATUS.size)
        fcntl.ioctl(self.fd, IOCTL_STATUS, buffer, True)
        values = STATUS.unpack(buffer)
        return dict(zip(("produced", "consumed", "dropped", "next_seq",
                         "flags", "fifo_used", "buffer_bytes", "live_flags",
                         "adc_errors", "reserved"), values))

    def read(self, max_bytes=65536):
        try:
            data = os.read(self.fd, max_bytes)
        except BlockingIOError:
            return b""
        if len(data) % FRAME_SIZE:
            raise IOError("Kernel returned a partial waveform frame")
        return data


class BlackBoxRecorder(object):
    def __init__(self, output_dir, pre_frames, post_frames, sample_rate,
                 current_limit_ma=None, current_zero_ma=None,
                 vibration_threshold=None, baseline_frames=2000,
                 event_sink=None, expected_ticks=2000, test_trigger_frame=None):
        self.output_dir = output_dir
        self.pre_frames = pre_frames
        self.post_frames = post_frames
        self.sample_rate = sample_rate
        self.current_limit_ma = current_limit_ma
        self.current_zero_ma = current_zero_ma
        self.vibration_threshold = vibration_threshold
        self.baseline_frames = baseline_frames
        self.event_sink = event_sink
        self.history = collections.deque(maxlen=pre_frames)
        self.event = None
        self.event_count = 0
        self.incomplete_events = 0
        self.complete_software_events = 0
        self.next_seq = None
        self.sequence_gaps = 0
        self.bad_frames = 0
        self.baseline_sum = [0, 0, 0]
        self.baseline_count = 0
        self.baseline = None
        self.previous_fault = False
        self.previous_adc_frame_error = False
        self.previous_overcurrent = False
        self.previous_vibration = False
        self.previous_adc_errors = None
        self.previous_dma_dropped = None
        self.expected_ticks = expected_ticks
        self.test_trigger_frame = test_trigger_frame
        self.test_trigger_attempted = False
        self.pending_manual_trigger = None
        self.manual_trigger_count = 0
        self.rejected_manual_triggers = 0
        self.parser_name = "python"
        self.frames = 0
        self.tick_mismatches = 0
        self.last_ticks = None
        self.latest_raw = None
        self.session_id = uuid.uuid4().hex[:12]

    def seed_counters_before_start(self, status):
        # ADC errors persist across DMA starts; DMA dropped frames reset.
        self.previous_adc_errors = status["adc_errors"]
        self.previous_dma_dropped = 0

    def _start_event(self, reason, trigger_seq, trigger_ticks, current_raw=None):
        software = "software trigger" in reason or "software test trigger" in reason
        if software:
            self.manual_trigger_count += 1
        self.event = {"reason": reason, "trigger_seq": trigger_seq,
                      "trigger_ticks": trigger_ticks,
                      "pre_count": len(self.history),
                      "dma_dropped_at_trigger": self.previous_dma_dropped,
                      "adc_errors_at_trigger": self.previous_adc_errors,
                      "frames": self.history.snapshot() if hasattr(self.history, "snapshot")
                                else list(self.history),
                      "pre_count_requested": self.pre_frames,
                      "post_count_requested": self.post_frames,
                      "trigger_frame_included": current_raw is not None,
                      "software_trigger": software,
                      "parser": self.parser_name,
                      "expected_ticks_per_frame": self.expected_ticks,
                      "clock_hz_configured": self.expected_ticks * self.sample_rate,
                      "pre_seconds_nominal": self.pre_frames / float(self.sample_rate),
                      "post_seconds_nominal": self.post_frames / float(self.sample_rate),
                      "post_remaining": self.post_frames,
                      "created_utc": datetime.datetime.now(
                          datetime.timezone.utc).isoformat()}
        if current_raw is not None:
            self.event["frames"].append(current_raw)
        if self.post_frames == 0:
            return self._finish_event()
        return None

    def _finish_event(self, incomplete=False):
        event = self.event
        if event is None:
            return None
        self.event = None
        total = sum(len(block) // FRAME_SIZE for block in event["frames"])
        event["post_count"] = total - event["pre_count"] - int(event["trigger_frame_included"])
        event["pre_window_complete"] = event["pre_count"] == self.pre_frames
        event["post_window_complete"] = event["post_count"] == self.post_frames
        incomplete = incomplete or not event["pre_window_complete"] or not event["post_window_complete"]
        name = "event-{}-{:08x}-{:03d}-{}".format(
            datetime.datetime.now(datetime.timezone.utc).strftime(
                "%Y%m%dT%H%M%S%fZ"),
            event["trigger_seq"] or 0, self.event_count, self.session_id)
        job = (self.output_dir, name, event, self.sample_rate,
               self.sequence_gaps, incomplete)
        try:
            if self.event_sink is not None:
                result = self.event_sink(*job)
            else:
                result = write_event(*job)
        except Exception:
            self.event = event
            raise
        self.event_count += 1
        self.incomplete_events += int(incomplete)
        self.complete_software_events += int(event["software_trigger"] and not incomplete)
        return result

    def _detect(self, frame):
        reasons = []
        fault = bool(frame["flags"] & 2)
        if fault and not self.previous_fault:
            reasons.append("PL motor fault")
        self.previous_fault = fault
        adc_frame_error = bool(frame["flags"] & 4)
        if adc_frame_error and not self.previous_adc_frame_error:
            reasons.append("ADC error")
        self.previous_adc_frame_error = adc_frame_error

        if self.current_limit_ma is not None:
            overcurrent = abs(frame["current_ma"] - self.current_zero_ma) >= \
                          self.current_limit_ma
            if overcurrent and not self.previous_overcurrent:
                reasons.append("current threshold")
            self.previous_overcurrent = overcurrent

        if self.vibration_threshold is not None:
            if self.baseline is None:
                for axis, value in enumerate(frame["vibration"]):
                    self.baseline_sum[axis] += value
                self.baseline_count += 1
                if self.baseline_count >= self.baseline_frames:
                    self.baseline = tuple(total / float(self.baseline_count)
                                          for total in self.baseline_sum)
            else:
                vibration = any(abs(frame["vibration"][axis] -
                                    self.baseline[axis]) >= self.vibration_threshold
                                for axis in range(3))
                if vibration and not self.previous_vibration:
                    reasons.append("vibration threshold")
                self.previous_vibration = vibration
        return reasons

    def ingest(self, raw):
        try:
            frame = decode_frame(raw)
        except ValueError:
            self.bad_frames += 1
            raise
        gap = self.next_seq is not None and frame["seq"] != self.next_seq
        if gap:
            self.sequence_gaps += (frame["seq"] - self.next_seq) & 0xffffffff
        self.next_seq = (frame["seq"] + 1) & 0xffffffff
        bad_ticks = not gap and self.last_ticks is not None and \
                    (frame["ticks"] - self.last_ticks) & 0xffffffffffffffff != self.expected_ticks
        self.tick_mismatches += int(bad_ticks)
        self.last_ticks = frame["ticks"]
        index = self.frames
        self.frames += 1
        self.latest_raw = raw
        reasons = self._detect(frame)
        if gap:
            reasons.append("waveform sequence gap")
        if bad_ticks:
            reasons.append("waveform timestamp mismatch")
        software = self.pending_manual_trigger
        self.pending_manual_trigger = None
        if self.test_trigger_frame is not None and not self.test_trigger_attempted and \
                index >= self.test_trigger_frame:
            self.test_trigger_attempted = True
            software = "software test trigger"
        if software:
            if self.event is None:
                reasons.append(software)
            else:
                self.rejected_manual_triggers += 1
        completed = None
        if self.event is not None:
            self.event["frames"].append(raw)
            self.event["post_remaining"] -= 1
            if self.event["post_remaining"] <= 0:
                completed = self._finish_event()
        elif reasons:
            completed = self._start_event(", ".join(reasons), frame["seq"],
                                          frame["ticks"], raw)
        self.history.append(raw)
        return completed

    def ingest_batch(self, data):
        if len(data) % FRAME_SIZE:
            raise ValueError("Incomplete waveform batch")
        for offset in range(0, len(data), FRAME_SIZE):
            self.ingest(data[offset:offset + FRAME_SIZE])

    def request_trigger(self):
        if self.event is not None or self.pending_manual_trigger is not None:
            self.rejected_manual_triggers += 1
            return False
        self.pending_manual_trigger = "manual software trigger"
        return True

    def observe_status(self, status):
        status_reasons = []
        if self.previous_adc_errors is None:
            self.previous_adc_errors = status["adc_errors"]
        elif status["adc_errors"] != self.previous_adc_errors:
            self.previous_adc_errors = status["adc_errors"]
            status_reasons.append("ADC error counter increased")
        if self.previous_dma_dropped is None:
            self.previous_dma_dropped = status["dropped"]
        elif status["dropped"] != self.previous_dma_dropped:
            self.previous_dma_dropped = status["dropped"]
            status_reasons.append("PL DMA frame loss")
        if (status["live_flags"] & (1 << 4)) and not self.previous_fault:
            self.previous_fault = True
            status_reasons.append("PL motor fault")
        if status_reasons and self.event is None:
            latest = decode_frame(self.latest_raw) if self.latest_raw else None
            self._start_event(", ".join(status_reasons),
                              latest["seq"] if latest else None,
                              latest["ticks"] if latest else None)

    def flush(self):
        return self._finish_event(incomplete=True)


class BlockHistory(object):
    """Bounded immutable byte blocks; copying is at block, not sample, granularity."""
    def __init__(self, capacity):
        self.capacity = capacity
        self.chunks = collections.deque()
        self.frames = 0

    def __len__(self):
        return self.frames

    def snapshot(self):
        return list(self.chunks)

    def append(self, data):
        if not data or not self.capacity:
            return
        count = len(data) // FRAME_SIZE
        if count >= self.capacity:
            self.chunks.clear()
            self.chunks.append(data[-self.capacity * FRAME_SIZE:])
            self.frames = self.capacity
            return
        self.chunks.append(data)
        self.frames += count
        excess = self.frames - self.capacity
        while excess > 0:
            first = self.chunks[0]
            count = len(first) // FRAME_SIZE
            if count <= excess:
                self.chunks.popleft()
                self.frames -= count
                excess -= count
            else:
                self.chunks[0] = first[excess * FRAME_SIZE:]
                self.frames -= excess
                break


class BatchBlackBoxRecorder(BlackBoxRecorder):
    REASONS = ((1, "PL motor fault"), (2, "ADC error"),
               (4, "current threshold"), (8, "vibration threshold"),
               (16, "waveform sequence gap"), (32, "waveform timestamp mismatch"))

    def __init__(self, *args, **kwargs):
        library = kwargs.pop("library", None)
        super(BatchBlackBoxRecorder, self).__init__(*args, **kwargs)
        from motor_wave_stats import NATIVE_LIBRARY_NAME, NativeScanner, load_native
        library = library if library is not None else load_native()
        if library is None:
            raise RuntimeError("{} is missing; build the black-box library".format(NATIVE_LIBRARY_NAME))
        self.scanner = NativeScanner(library, self.expected_ticks,
                                     self.current_limit_ma, self.current_zero_ma,
                                     self.vibration_threshold, self.baseline_frames)
        self.history = BlockHistory(self.pre_frames)
        self.parser_name = "native"

    def ingest(self, raw):
        self.ingest_batch(raw)

    def observe_status(self, status):
        super(BatchBlackBoxRecorder, self).observe_status(status)
        if self.previous_fault:
            self.scanner.detector.previous |= 1

    def ingest_batch(self, data):
        if not data:
            return
        if len(data) % FRAME_SIZE:
            self.bad_frames += 1
            raise ValueError("Incomplete waveform batch")
        before = self.frames
        result, native_triggers, valid = self.scanner.scan(self, data)
        triggers = {index: [reason for bit, reason in self.REASONS if mask & bit]
                    for index, mask in native_triggers}
        if valid:
            software = self.pending_manual_trigger
            self.pending_manual_trigger = None
            if software:
                triggers.setdefault(0, []).append(software)
            if self.test_trigger_frame is not None and not self.test_trigger_attempted and \
                    self.test_trigger_frame < before + valid:
                self.test_trigger_attempted = True
                index = max(0, self.test_trigger_frame - before)
                triggers.setdefault(index, []).append("software test trigger")
            self._consume_valid(data[:valid * FRAME_SIZE], sorted(triggers.items()))
            self.latest_raw = data[(valid - 1) * FRAME_SIZE:valid * FRAME_SIZE]
            self.next_seq = (self.last_seq + 1) & 0xffffffff
            self.previous_fault = bool(self.scanner.detector.previous & 1)
        if result:
            self.bad_frames += 1
            if result == 2:
                raise ValueError("Bad waveform frame magic/valid flag")
            raise RuntimeError("Native black-box scanner failed: {}".format(result))

    def _consume_valid(self, data, triggers):
        position, cursor = 0, 0
        count = len(data) // FRAME_SIZE
        while position < count:
            if self.event is not None:
                take = min(self.event["post_remaining"], count - position)
                block = data[position * FRAME_SIZE:(position + take) * FRAME_SIZE]
                self.event["frames"].append(block)
                self.event["post_remaining"] -= take
                self.history.append(block)
                position += take
                while cursor < len(triggers) and triggers[cursor][0] < position:
                    if any("software" in reason for reason in triggers[cursor][1]):
                        self.rejected_manual_triggers += 1
                    cursor += 1
                if self.event["post_remaining"] == 0:
                    self._finish_event()
                continue
            while cursor < len(triggers) and triggers[cursor][0] < position:
                cursor += 1
            end = triggers[cursor][0] if cursor < len(triggers) else count
            if end > position:
                self.history.append(data[position * FRAME_SIZE:end * FRAME_SIZE])
                position = end
            if position == count:
                break
            reasons = triggers[cursor][1]
            raw = data[position * FRAME_SIZE:(position + 1) * FRAME_SIZE]
            frame = decode_frame(raw)
            self._start_event(", ".join(reasons), frame["seq"], frame["ticks"], raw)
            self.history.append(raw)
            position += 1
            cursor += 1


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", default="/dev/motor_wave_dma")
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--pre-seconds", type=float, default=2.0)
    parser.add_argument("--post-seconds", type=float, default=2.0)
    parser.add_argument("--sample-rate", type=int, default=50000)
    parser.add_argument("--current-limit-ma", type=int)
    parser.add_argument("--current-zero-ma", type=int)
    parser.add_argument("--vibration-threshold-codes", type=int)
    parser.add_argument("--baseline-frames", type=int, default=2000)
    parser.add_argument("--parser", choices=("native", "python"), default="native")
    parser.add_argument("--clock-hz", type=int, default=100000000)
    parser.add_argument("--seconds", type=float, help="Bounded run; omit for continuous recording")
    parser.add_argument("--test-trigger-after", type=float,
                        help="Software-only trigger at this capture time; no motor command")
    parser.add_argument("--batch-frames", type=int, default=128)
    parser.add_argument("--batch-latency-ms", type=float, default=2.0)
    parser.add_argument("--min-rate-hz", type=float)
    args = parser.parse_args(argv)
    if not (0 <= args.pre_seconds <= 60 and 0 <= args.post_seconds <= 60):
        parser.error("pre/post seconds must be between 0 and 60")
    if args.sample_rate < 1 or args.sample_rate > 200000:
        parser.error("invalid sample rate")
    if not args.sample_rate <= args.clock_hz <= 0xffffffffffffffff or args.clock_hz % args.sample_rate:
        parser.error("clock-hz must be an integer multiple of sample-rate")
    if args.seconds is not None and (not math.isfinite(args.seconds) or args.seconds < 0.1):
        parser.error("seconds must be finite and at least 0.1")
    if not 1 <= args.batch_frames <= 2048 or not 0.1 <= args.batch_latency_ms <= 100:
        parser.error("batch frames must be 1..2048; latency must be 0.1..100 ms")
    if args.min_rate_hz is not None and (not math.isfinite(args.min_rate_hz) or args.min_rate_hz < 0):
        parser.error("min-rate-hz must be nonnegative and finite")
    if args.test_trigger_after is not None:
        if not math.isfinite(args.test_trigger_after) or args.test_trigger_after < args.pre_seconds:
            parser.error("test trigger must allow the complete pre-window")
        if args.test_trigger_after > 0xffffffffffffffff / args.sample_rate:
            parser.error("test trigger exceeds the capture frame-counter range")
        if args.seconds is not None and args.seconds <= args.test_trigger_after + args.post_seconds:
            parser.error("bounded run must leave time after the complete post-window")
    # Bound the five outstanding event buffers plus history, before opening DMA.
    if ((args.pre_seconds + args.post_seconds) * 5 + args.pre_seconds) * \
            args.sample_rate * FRAME_SIZE > 128 * 1024 * 1024:
        parser.error("black-box windows exceed the 128 MiB payload budget")
    if args.current_limit_ma is not None and (
            args.current_limit_ma <= 0 or args.current_zero_ma is None):
        parser.error("current threshold requires a positive limit and measured zero")
    if args.vibration_threshold_codes is not None and (
            args.vibration_threshold_codes <= 0 or args.baseline_frames < 1):
        parser.error("vibration threshold and baseline frame count must be positive")
    for value in (args.current_limit_ma, args.current_zero_ma, args.vibration_threshold_codes):
        if value is not None and not -2147483648 <= value <= 2147483647:
            parser.error("threshold/zero must fit a signed 32-bit value")
    if not 1 <= args.baseline_frames <= 12000000:
        parser.error("baseline-frames must be 1..12000000")
    return args


def drain_device(device, recorder, writer, timeout=5.0):
    """Read B-committed frames until a stopped PL has fully drained its FIFO."""
    deadline = time.monotonic() + timeout
    while True:
        data = device.read()
        recorder.ingest_batch(data)
        if data:
            if time.monotonic() >= deadline:
                raise RuntimeError("PL DMA did not drain after stop")
            continue
        status = device.status()
        writer.check()
        recorder.observe_status(status)
        if status["flags"] & 8:
            raise RuntimeError("PL DMA error while draining")
        if not (status["flags"] & 3) and \
                status["produced"] == status["consumed"]:
            return
        if time.monotonic() >= deadline:
            raise RuntimeError("PL DMA did not drain after stop")
        time.sleep(0.005)


def main(argv=None):
    args = parse_args(argv)
    recorder_type = BatchBlackBoxRecorder if args.parser == "native" else BlackBoxRecorder
    recorder = recorder_type(
        args.output_dir, int(args.pre_seconds * args.sample_rate),
        int(args.post_seconds * args.sample_rate), args.sample_rate,
        args.current_limit_ma, args.current_zero_ma,
        args.vibration_threshold_codes, args.baseline_frames,
        expected_ticks=args.clock_hz // args.sample_rate,
        test_trigger_frame=int(args.test_trigger_after * args.sample_rate)
                           if args.test_trigger_after is not None else None)
    device = WaveDevice(args.device)
    try:
        writer = EventWriter()
    except Exception:
        device.close()
        raise
    recorder.event_sink = writer.submit
    stopping = [False]
    manual = [False]

    def request_stop(_signum, _frame):
        stopping[0] = True

    def request_manual(_signum, _frame):
        manual[0] = True

    old_handlers = {}
    start_time = None
    capture_finish = None
    status = None
    max_pending = 0
    read_seconds = parse_seconds = 0.0
    pending = bytearray()
    try:
        for number in (signal.SIGTERM, signal.SIGINT):
            old_handlers[number] = signal.signal(number, request_stop)
        if hasattr(signal, "SIGUSR1"):
            old_handlers[signal.SIGUSR1] = signal.signal(signal.SIGUSR1, request_manual)
        initial_status = device.status()
        recorder.seed_counters_before_start(initial_status)
        device.start()
        recorder.observe_status(device.status())
        start_time = last_status = last_batch = time.monotonic()
        print("blackbox parser={} pid={} pre_frames={} post_frames={}".format(
            recorder.parser_name, os.getpid(), recorder.pre_frames, recorder.post_frames), flush=True)
        while not stopping[0]:
            before_read = time.monotonic()
            data = device.read()
            now = time.monotonic()
            read_seconds += now - before_read
            pending.extend(data)
            if manual[0]:
                manual[0] = False
                recorder.request_trigger()
            if pending and (len(pending) >= args.batch_frames * FRAME_SIZE or
                            now - last_batch >= args.batch_latency_ms / 1000.0):
                before_parse = time.monotonic()
                recorder.ingest_batch(bytes(pending))
                parse_seconds += time.monotonic() - before_parse
                pending.clear()
                last_batch = time.monotonic()
            if now - last_status >= 0.1 or not data:
                status = device.status()
                max_pending = max(max_pending, (status["produced"] - status["consumed"]) & 0xffffffff)
                writer.check()
                recorder.observe_status(status)
                if status["flags"] & 8:
                    raise RuntimeError("PL DMA error; B response / configuration failed")
                if not data and not (status["flags"] & 3) and not stopping[0]:
                    raise RuntimeError("PL DMA unexpectedly stopped")
                last_status = now
            if args.seconds is not None and now - start_time >= args.seconds:
                stopping[0] = True
            if len(pending) < args.batch_frames * FRAME_SIZE:
                time.sleep(min(0.001, args.batch_latency_ms / 1000.0))
        device.stop()
        if pending:
            recorder.ingest_batch(bytes(pending))
            pending.clear()
        drain_device(device, recorder, writer)
        status = device.status()
        capture_finish = time.monotonic()
    finally:
        try:
            device.stop()
        finally:
            try:
                try:
                    recorder.flush()
                finally:
                    writer.close()
            finally:
                device.close()
                for number, handler in old_handlers.items():
                    signal.signal(number, handler)
    elapsed = capture_finish - start_time
    storage_wait = time.monotonic() - capture_finish
    rate = recorder.frames / elapsed if elapsed else 0.0
    adc_delta = (status["adc_errors"] - initial_status["adc_errors"]) & 0xffffffff
    print("frames={} elapsed={:.3f}s rate={:.1f}Hz seq_gaps={} tick_mismatches={} ".format(
        recorder.frames, elapsed, rate, recorder.sequence_gaps, recorder.tick_mismatches) +
        "dma_dropped={} adc_errors_delta={} max_pending_bytes={} read_s={:.3f} parse_s={:.3f}".format(
            status["dropped"], adc_delta, max_pending, read_seconds, parse_seconds))
    print("events={} saved={} software_triggers={} rejected_triggers={} incomplete_events={} storage_wait_s={:.3f}".format(
        recorder.event_count, writer.saved_count, recorder.manual_trigger_count,
        recorder.rejected_manual_triggers, recorder.incomplete_events, storage_wait))
    problems = []
    if not recorder.frames:
        problems.append("no frames")
    if recorder.sequence_gaps or recorder.tick_mismatches or recorder.bad_frames:
        problems.append("waveform integrity failure")
    if status["dropped"] or adc_delta or status["flags"] & 15:
        problems.append("DMA/ADC error or incomplete stop")
    if args.test_trigger_after is not None and (
            recorder.manual_trigger_count != 1 or recorder.complete_software_events != 1):
        problems.append("complete software test window was not captured")
    minimum_rate = args.min_rate_hz
    if minimum_rate is None and args.test_trigger_after is not None and args.seconds is not None:
        minimum_rate = args.sample_rate * 0.9
    if minimum_rate is not None and rate < minimum_rate:
        problems.append("processing rate below minimum")
    if problems:
        print("FAIL: " + ", ".join(problems))
        return 1
    print("PASS: black-box capture stopped and storage flushed")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, ValueError) as error:
        print("motor_blackbox: {}".format(error), file=sys.stderr)
        sys.exit(1)
