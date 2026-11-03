#!/usr/bin/env python3
"""Bounded, motor-output-free HP0-to-DDR waveform stream check."""
import argparse
import time

from motor_blackbox import FRAME, FRAME_MAGIC, FRAME_SIZE, WaveDevice
from motor_wave_stats import NATIVE_LIBRARY_NAME, NativeParser, load_native


class FrameStats(object):
    def __init__(self, expected_ticks, parser="auto"):
        self.expected_ticks = expected_ticks
        self.frames = 0
        self.sequence_gaps = 0
        self.tick_mismatches = 0
        self.first_ticks = None
        self.last_ticks = None
        self.last_seq = None
        self.current_min = None
        self.current_max = None
        self.motor_fault_frames = 0
        self.adc_error_frames = 0
        library = load_native() if parser != "python" else None
        if parser == "native" and library is None:
            raise RuntimeError("{} is missing".format(NATIVE_LIBRARY_NAME))
        self.native = NativeParser(library, expected_ticks) if library else None
        self.parser_name = "native" if self.native else "python"

    def ingest(self, data):
        if len(data) % FRAME_SIZE:
            raise RuntimeError("driver returned a partial frame")
        if self.native is not None:
            self.native.ingest(self, data)
            return
        # Python fallback: no frame-sized slices, dictionaries or repeated
        # attribute lookups in the hot loop. Native mode validates every frame
        # using the same ABI and rules, without a Python loop per frame.
        frames, gaps, mismatches = self.frames, self.sequence_gaps, self.tick_mismatches
        first_ticks, last_ticks, last_seq = self.first_ticks, self.last_ticks, self.last_seq
        minimum, maximum = self.current_min, self.current_max
        motor_faults, adc_errors = self.motor_fault_frames, self.adc_error_frames
        expected_ticks = self.expected_ticks
        try:
            for raw, _, _, _, seq, flags, ticks, _, magic in FRAME.iter_unpack(data):
                if magic != FRAME_MAGIC or not flags & 1:
                    raise ValueError("Bad waveform frame magic/valid flag")
                if last_seq is not None:
                    advance = (seq - last_seq) & 0xffffffff
                    if advance != 1:
                        gaps += (advance - 1) & 0xffffffff
                    elif (ticks - last_ticks) & 0xffffffffffffffff != expected_ticks:
                        mismatches += 1
                if first_ticks is None:
                    first_ticks = ticks
                last_ticks, last_seq = ticks, seq
                if minimum is None or raw < minimum:
                    minimum = raw
                if maximum is None or raw > maximum:
                    maximum = raw
                motor_faults += (flags >> 1) & 1
                adc_errors += (flags >> 2) & 1
                frames += 1
        finally:
            self.frames, self.sequence_gaps, self.tick_mismatches = frames, gaps, mismatches
            self.first_ticks, self.last_ticks, self.last_seq = first_ticks, last_ticks, last_seq
            self.current_min, self.current_max = minimum, maximum
            self.motor_fault_frames, self.adc_error_frames = motor_faults, adc_errors


def status_text(status):
    pending = (status["produced"] - status["consumed"]) & 0xffffffff
    return ("flags=0x{flags:02x} fifo={fifo} pending_bytes={pending} "
            "produced={produced} consumed={consumed} dropped={dropped}").format(
                fifo=status.get("fifo_used", "?"), pending=pending, **status)


def capture(device, seconds, clock_hz, sample_hz, parser="auto"):
    if seconds <= 0 or clock_hz <= 0 or sample_hz <= 0:
        raise ValueError("seconds, clock_hz and sample_hz must be positive")
    expected_ticks = (clock_hz + sample_hz - 1) // sample_hz
    stats = FrameStats(expected_ticks, parser)
    adc_errors_before = device.status()["adc_errors"]
    started = False
    read_seconds = 0.0
    parse_seconds = 0.0
    max_pending = 0

    def read_batch():
        nonlocal read_seconds, parse_seconds
        before = time.monotonic()
        data = device.read()
        after_read = time.monotonic()
        stats.ingest(data)
        after_parse = time.monotonic()
        read_seconds += after_read - before
        parse_seconds += after_parse - after_read
        return data

    try:
        device.start()
        started = True
        start_time = time.monotonic()
        next_status_check = start_time + 1.0
        while time.monotonic() - start_time < seconds:
            data = read_batch()
            now = time.monotonic()
            if not data or now >= next_status_check:
                status = device.status()
                next_status_check = now + 1.0
                max_pending = max(max_pending,
                                  (status["produced"] - status["consumed"]) & 0xffffffff)
                if status["flags"] & 8:
                    raise RuntimeError("PL DMA write/configuration error; " + status_text(status))
                if not status["flags"] & 3:
                    raise RuntimeError("PL DMA stopped during capture")
                if status["dropped"]:
                    raise RuntimeError("DMA frame loss during capture; " + status_text(status) +
                                       " read_s={:.3f} parse_s={:.3f}".format(
                                           read_seconds, parse_seconds))
            if not data:
                time.sleep(0.005)
        capture_elapsed = time.monotonic() - start_time
        capture_frames = stats.frames
        before_stop = device.status()
        pending_before_stop = (before_stop["produced"] - before_stop["consumed"]) & 0xffffffff
        max_pending = max(max_pending, pending_before_stop)
        device.stop()
        drain_start = time.monotonic()
        deadline = drain_start + 5.0
        while True:
            data = read_batch()
            if data:
                if time.monotonic() >= deadline:
                    status = device.status()
                    raise RuntimeError("DMA drain/validation timeout; " + status_text(status) +
                                       " read_s={:.3f} parse_s={:.3f}".format(
                                           read_seconds, parse_seconds))
                continue
            status = device.status()
            if status["flags"] & 8:
                raise RuntimeError("PL DMA error while draining")
            if not status["flags"] & 3 and status["produced"] == status["consumed"]:
                break
            if time.monotonic() >= deadline:
                raise RuntimeError("DMA drain/validation timeout; " + status_text(status))
            time.sleep(0.005)
        finish_time = time.monotonic()
        elapsed = finish_time - start_time
        return {
            "frames": stats.frames,
            "elapsed_s": elapsed,
            "rate_hz": stats.frames / elapsed if elapsed > 0 else 0.0,
            "capture_frames": capture_frames,
            "capture_elapsed_s": capture_elapsed,
            "capture_rate_hz": capture_frames / capture_elapsed if capture_elapsed > 0 else 0.0,
            "drain_elapsed_s": finish_time - drain_start,
            "pending_before_stop": pending_before_stop,
            "max_pending_bytes": max_pending,
            "read_seconds": read_seconds,
            "parse_seconds": parse_seconds,
            "parser": stats.parser_name,
            "sequence_gaps": stats.sequence_gaps,
            "tick_mismatches": stats.tick_mismatches,
            "expected_ticks_per_frame": expected_ticks,
            "current_raw_min": stats.current_min,
            "current_raw_max": stats.current_max,
            "motor_fault_frames": stats.motor_fault_frames,
            "adc_error_frames": stats.adc_error_frames,
            "dma_dropped": status["dropped"],
            "adc_errors_delta": (status["adc_errors"] - adc_errors_before) & 0xffffffff,
            "dma_flags": status["flags"],
        }
    finally:
        if started:
            device.stop()


def failures(result, min_rate_hz):
    problems = []
    if result["frames"] == 0:
        problems.append("no DMA frames")
    if result["rate_hz"] < min_rate_hz:
        problems.append("frame rate below minimum")
    for name in ("sequence_gaps", "tick_mismatches", "motor_fault_frames",
                 "adc_error_frames", "dma_dropped", "adc_errors_delta"):
        if result[name]:
            problems.append("{}={}".format(name, result[name]))
    if result["dma_flags"] & 3:
        problems.append("DMA remains active/busy after stop")
    return problems


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", default="/dev/motor_wave_dma")
    parser.add_argument("--seconds", type=float, default=2.0)
    parser.add_argument("--clock-hz", type=int, default=100000000)
    parser.add_argument("--sample-hz", type=int, default=50000)
    parser.add_argument("--min-rate-hz", type=float, default=45000.0)
    parser.add_argument("--parser", choices=("auto", "native", "python"), default="auto")
    args = parser.parse_args(argv)
    if not 0.1 <= args.seconds <= 60 or args.min_rate_hz < 0:
        parser.error("seconds must be 0.1..60 and min-rate-hz must be nonnegative")
    device = WaveDevice(args.device)
    try:
        result = capture(device, args.seconds, args.clock_hz, args.sample_hz, args.parser)
    finally:
        device.close()
    print("frames={frames} elapsed={elapsed_s:.3f}s rate={rate_hz:.1f}Hz ".format(**result) +
          "seq_gaps={sequence_gaps} tick_mismatches={tick_mismatches} ".format(**result) +
          "dma_dropped={dma_dropped} adc_errors_delta={adc_errors_delta}".format(**result))
    print("current_raw_range=[{current_raw_min},{current_raw_max}] ".format(**result) +
          "expected_ticks_per_frame={expected_ticks_per_frame}".format(**result))
    print("parser={parser} capture_frames={capture_frames} ".format(**result) +
          "capture_s={capture_elapsed_s:.3f} capture_rate={capture_rate_hz:.1f}Hz ".format(**result) +
          "drain_s={drain_elapsed_s:.3f} pending_before_stop={pending_before_stop} ".format(**result) +
          "max_pending_bytes={max_pending_bytes} read_s={read_seconds:.3f} ".format(**result) +
          "parse_s={parse_seconds:.3f}".format(**result))
    problems = failures(result, args.min_rate_hz)
    if problems:
        print("FAIL: " + ", ".join(problems))
        return 1
    print("PASS: continuous HP0-to-DDR waveform stream")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError) as error:
        print("FAIL: {}".format(error))
        raise SystemExit(1)
