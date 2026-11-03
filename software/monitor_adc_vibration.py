#!/usr/bin/env python3
"""Poll PL snapshots and report changes in three vibration AO channels.

This is a preliminary PS-side test. It does not capture every 50 kSPS ADC
frame: a pulse shorter than the polling gap can still be missed. Exact peak
capture needs a PL windowed peak detector or buffered waveform path.
Only the status CAPTURE register at 0x80000008 is written; no motor control.
Run alone, not concurrently with another snapshot-reading script.
"""

import argparse
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
VIBRATION_OFFSETS = (0x1C, 0x20, 0x24)
SAMPLE_COUNT = 0x28
ADC_ERROR_COUNT = 0x3C
LIVE_FLAGS = 0x48
LIVE_SAMPLES = 0x4C


def read_u32(regs, offset):
    return struct.unpack_from("<I", regs, offset)[0]


def read_i32(regs, offset):
    return struct.unpack_from("<i", regs, offset)[0]


def capture_snapshot(regs):
    previous = read_u32(regs, SEQ)
    for _ in range(3):
        struct.pack_into("<I", regs, CAPTURE, 1)
        seq_before = read_u32(regs, SEQ)
        flags = read_u32(regs, FLAGS)
        values = tuple(read_i32(regs, offset) for offset in VIBRATION_OFFSETS)
        sample_count = read_u32(regs, SAMPLE_COUNT)
        error_count = read_u32(regs, ADC_ERROR_COUNT)
        seq_after = read_u32(regs, SEQ)
        if seq_before != previous and seq_before == seq_after and (flags & 1):
            return values, sample_count, error_count, flags
        previous = seq_after
    raise RuntimeError("No coherent new snapshot; stop other snapshot readers.")


def check_snapshot(snapshot, previous_count, previous_errors):
    _values, sample_count, error_count, flags = snapshot
    if not (flags & 2) or (flags & 4):
        raise RuntimeError("ADC has no valid frame or is currently in error.")
    if previous_count is not None and sample_count == previous_count:
        raise RuntimeError("ADC sample counter stopped; refusing stale data.")
    if previous_errors is not None and error_count != previous_errors:
        raise RuntimeError("ADC error count increased; check ADC wiring/timing.")


def median_baseline(samples):
    if not samples:
        raise ValueError("No baseline samples.")
    return tuple(statistics.median(sample[channel] for sample in samples)
                 for channel in range(3))


class PeakWindow:
    def __init__(self, baseline):
        self.baseline = tuple(baseline)
        self.minimum = list(baseline)
        self.maximum = list(baseline)
        self.count = 0

    def add(self, values):
        for channel, value in enumerate(values):
            self.minimum[channel] = min(self.minimum[channel], value)
            self.maximum[channel] = max(self.maximum[channel], value)
        self.count += 1

    def peak_deltas(self):
        return tuple(max(abs(self.minimum[i] - self.baseline[i]),
                         abs(self.maximum[i] - self.baseline[i]))
                     for i in range(3))


def verify_image_and_samples(regs):
    if (read_u32(regs, 0x00), read_u32(regs, 0x04)) != (EXPECTED_ID, EXPECTED_ABI):
        raise RuntimeError("Wrong PL image/ABI; no register writes made.")
    flags = read_u32(regs, LIVE_FLAGS)
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

    previous_count = None
    previous_errors = None
    baseline_samples = []
    print("Keep all three sensors still while taking the baseline...")
    for _ in range(args.baseline_samples):
        time.sleep(args.interval)
        snapshot = capture_snapshot(regs)
        check_snapshot(snapshot, previous_count, previous_errors)
        values, previous_count, previous_errors, _flags = snapshot
        baseline_samples.append(values)

    baseline = median_baseline(baseline_samples)
    print("Baseline raw codes: CH1={:.1f} CH2={:.1f} CH3={:.1f}; "
          "historical ADC errors={}".format(
              baseline[0], baseline[1], baseline[2], previous_errors))
    print("Tap one sensor at a time during the next {:.1f} seconds.".format(
        args.seconds))

    overall = PeakWindow(baseline)
    window = PeakWindow(baseline)
    start = time.monotonic()
    next_report = start + args.report_interval
    while time.monotonic() - start < args.seconds:
        time.sleep(args.interval)
        snapshot = capture_snapshot(regs)
        check_snapshot(snapshot, previous_count, previous_errors)
        values, previous_count, previous_errors, _flags = snapshot
        overall.add(values)
        window.add(values)
        now = time.monotonic()
        if now >= next_report:
            print("t={:.1f}s captures={} peak |delta| codes: CH1={} CH2={} "
                  "CH3={}".format(now - start, window.count,
                                  *window.peak_deltas()))
            window = PeakWindow(baseline)
            next_report = now + args.report_interval

    if window.count:
        print("final partial window: captures={} peak |delta| codes: "
              "CH1={} CH2={} CH3={}".format(
                  window.count, *window.peak_deltas()))
    print("Overall peak |delta| codes: CH1={} CH2={} CH3={} from {} PS "
          "snapshots. Shorter pulses may have been missed.".format(
              *overall.peak_deltas(), overall.count))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seconds", type=float, default=15.0)
    parser.add_argument("--interval", type=float, default=0.001,
                        help="Requested seconds between PS snapshots.")
    parser.add_argument("--baseline-samples", type=int, default=200)
    parser.add_argument("--report-interval", type=float, default=0.5)
    args = parser.parse_args()
    if args.seconds <= 0 or args.interval < 0.001 or args.baseline_samples < 20 \
            or args.report_interval < 0.1:
        parser.error("Use seconds > 0, interval >= 0.001, "
                     "baseline-samples >= 20, report-interval >= 0.1.")
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
