#!/usr/bin/env python3
"""Calibrate and display ACS712 current through the ADC-only PL image.

The motor current path must be OPEN during calibration. This tool only writes
the status block's CAPTURE register (0x80000008); it never drives the motor.
Filtered values are telemetry, not a fast overcurrent protection mechanism.
Run this tool alone: another snapshot client can replace its snapshots.
"""

import argparse
from collections import deque
import mmap
import os
import statistics
import struct
import sys
import time


BASE = 0x80000000
EXPECTED_ID = 0x4D535431
EXPECTED_ABI = 0x00010000
CAPTURE = 0x08
SEQ = 0x0C
FLAGS = 0x10
CURRENT = 0x18
SAMPLE_COUNT = 0x28
ADC_ERROR_COUNT = 0x3C
LIVE_FLAGS = 0x48
LIVE_SAMPLES = 0x4C


def read_u32(regs, offset):
    return struct.unpack_from("<I", regs, offset)[0]


def read_i32(regs, offset):
    return struct.unpack_from("<i", regs, offset)[0]


def capture_snapshot(regs):
    """Request one coherent snapshot, rejecting failed or concurrent reads."""
    previous = read_u32(regs, SEQ)
    for _ in range(3):
        struct.pack_into("<I", regs, CAPTURE, 1)
        seq_before = read_u32(regs, SEQ)
        flags = read_u32(regs, FLAGS)
        current = read_i32(regs, CURRENT)
        sample_count = read_u32(regs, SAMPLE_COUNT)
        error_count = read_u32(regs, ADC_ERROR_COUNT)
        seq_after = read_u32(regs, SEQ)
        if seq_before != previous and seq_before == seq_after and (flags & 1):
            return current, sample_count, error_count, flags
        previous = seq_after
    raise RuntimeError("No coherent new snapshot; stop other snapshot readers.")


def check_sample(snapshot, previous_count, previous_errors):
    _current, sample_count, error_count, flags = snapshot
    if not (flags & 2) or (flags & 4):
        raise RuntimeError("ADC has no valid frame or is reporting an error.")
    if previous_count is not None and sample_count == previous_count:
        raise RuntimeError("ADC sample counter stopped; refusing stale data.")
    if previous_errors is not None and error_count != previous_errors:
        raise RuntimeError("ADC error count changed; check ADC wiring/timing.")


def trimmed_mean(values):
    if not values:
        raise ValueError("At least one zero-current sample is required.")
    ordered = sorted(values)
    trim = len(ordered) // 10 if len(ordered) >= 20 else 0
    middle = ordered[trim:len(ordered) - trim] if trim else ordered
    return sum(middle) / float(len(middle))


class MovingAverage:
    def __init__(self, width):
        if width < 1:
            raise ValueError("Moving-average window must be positive.")
        self.values = deque(maxlen=width)
        self.total = 0.0

    def add(self, value):
        if len(self.values) == self.values.maxlen:
            self.total -= self.values[0]
        self.values.append(value)
        self.total += value
        return self.total / len(self.values)


def verify_image_and_samples(regs):
    device_id = read_u32(regs, 0x00)
    abi = read_u32(regs, 0x04)
    if (device_id, abi) != (EXPECTED_ID, EXPECTED_ABI):
        raise RuntimeError("Wrong PL image/ABI; no register writes made.")
    flags = read_u32(regs, LIVE_FLAGS)
    if flags & (1 << 6):
        raise RuntimeError("Motor STBY status is high; refuse zero calibration.")
    before = read_u32(regs, LIVE_SAMPLES)
    time.sleep(0.03)
    after = read_u32(regs, LIVE_SAMPLES)
    if after == before or not (flags & 2) or (flags & 4):
        raise RuntimeError("ADC is not producing healthy new frames.")
    return flags


def run(regs, args):
    flags = verify_image_and_samples(regs)
    if flags & 8:
        print("Note: historical ADC errors were seen; checking for new errors.")

    zero_values = []
    previous_count = None
    previous_errors = None
    for _ in range(args.zero_samples):
        time.sleep(args.interval)
        snapshot = capture_snapshot(regs)
        check_sample(snapshot, previous_count, previous_errors)
        current, previous_count, previous_errors, _flags = snapshot
        zero_values.append(current)

    offset = trimmed_mean(zero_values)
    print("Zero-current calibration: n={} mean={:.1f} mA, median={:.1f} mA, "
          "trimmed offset={:.1f} mA, min={} mA, max={} mA".format(
              len(zero_values), statistics.mean(zero_values),
              statistics.median(zero_values), offset,
              min(zero_values), max(zero_values)))
    print("Historical ADC error count={} (must not increase).".format(
        previous_errors))

    if args.seconds <= 0:
        return

    moving = MovingAverage(args.window)
    end = time.monotonic() + args.seconds
    next_print = time.monotonic()
    print("Monitoring: raw, zero-corrected, {}-sample moving average "
          "(telemetry only).".format(args.window))
    while time.monotonic() < end:
        time.sleep(args.interval)
        snapshot = capture_snapshot(regs)
        check_sample(snapshot, previous_count, previous_errors)
        current, previous_count, previous_errors, _flags = snapshot
        corrected = current - offset
        filtered = moving.add(corrected)
        now = time.monotonic()
        if now >= next_print:
            print("raw={:+d} mA corrected={:+.1f} mA filtered={:+.1f} mA".
                  format(current, corrected, filtered))
            next_print = now + 0.25


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--confirm-zero-current", action="store_true",
                        help="Confirm motor winding path is open; required.")
    parser.add_argument("--zero-samples", type=int, default=200)
    parser.add_argument("--interval", type=float, default=0.01,
                        help="Seconds between snapshots; default 0.01.")
    parser.add_argument("--window", type=int, default=16,
                        help="Moving-average window; default 16 snapshots.")
    parser.add_argument("--seconds", type=float, default=5.0,
                        help="Monitoring duration after calibration; 0 skips.")
    args = parser.parse_args()
    if not args.confirm_zero_current:
        parser.error("Calibration requires --confirm-zero-current with the "
                     "motor winding disconnected (not just stopped).")
    if args.zero_samples < 20 or args.interval < 0.001 or args.window < 1 or args.seconds < 0:
        parser.error("Use at least 20 zero samples, interval >= 0.001 s, "
                     "window >= 1, and seconds >= 0.")
    if os.geteuid() != 0:
        parser.error("Run as root for /dev/mem access.")

    try:
        fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
        try:
            with mmap.mmap(fd, mmap.PAGESIZE, flags=mmap.MAP_SHARED,
                           prot=mmap.PROT_READ | mmap.PROT_WRITE,
                           offset=BASE) as regs:
                run(regs, args)
        finally:
            os.close(fd)
    except (OSError, RuntimeError) as error:
        print("FAIL: {}".format(error), file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("\nStopped.")
        return 130
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
