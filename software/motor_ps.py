#!/usr/bin/env python3
"""PS motor/ADC app for trial, speed-control and guarded-control images.

Trial uses the PL's one-shot limit. Continuous mode writes the PL speed
setpoint and supervises feedback; it requires wired encoder feedback and
independent current limiting. Legacy images also require an external command
watchdog; images 0x143/0x343/0x743/0xF43/0x1B43 have a PL heartbeat/run-time guard. PS polling alone is
not a hardware cutoff and software confirmation flags do not verify wiring.
The separate 0x4143 encoder-free image uses motor_open_loop.py instead of this
legacy continuous command and has no independent-limiter confirmation flag.
"""

import argparse
import contextlib
import csv
import math
import mmap
import os
import signal
import statistics
import struct
import sys
import time
from collections import namedtuple


STATUS_BASE = 0x80000000
GPIO_BASE = 0x80001000
ID = 0x4D535431
ABI = 0x00010000
FEATURES = 0x00000033
CONTINUOUS_FEATURES = 0x00000003
DMA_CONTINUOUS_FEATURES = 0x00000043
SAFE_DMA_FEATURES = 0x000000C3
GUARDED_FEATURES = 0x00000143
FILTERED_GUARDED_FEATURES = 0x00000343
BYPASS_GUARDED_FEATURES = 0x00000743
OBSERVE_GUARDED_FEATURES = 0x00000F43
FILTER4_OBSERVE_FEATURES = 0x00001B43
OPEN_LOOP_FEATURES = 0x00004143
OBSERVATION_IMAGES = (OBSERVE_GUARDED_FEATURES, FILTER4_OBSERVE_FEATURES)
TRACED_GUARDED_IMAGES = (FILTERED_GUARDED_FEATURES, BYPASS_GUARDED_FEATURES, *OBSERVATION_IMAGES)
GUARDED_IMAGES = (GUARDED_FEATURES, *TRACED_GUARDED_IMAGES, OPEN_LOOP_FEATURES)
CONTINUOUS_GUARDED_IMAGES = (GUARDED_FEATURES, FILTERED_GUARDED_FEATURES)
PL_ENCODER_COUNTS = 40000
GUARD_ID = 0x4D475231
GUARD_ARM = 0x41524D31
GUARD_STOP = 0x53544F50
GUARD_CLEAR = 0x434C5231
GUARD_ESTOP = 0x45535450
GUARD_FAULT_NAMES = ("ADC error", "ADC stale", "current limit", "motor core fault",
                     "heartbeat timeout", "run deadline", "invalid control", "operator stop")
ARM_MAGIC = 0x53414645
LOCK_PATH = "/run/motor_ps.lock"
CSV_COLUMNS = ("phase", "time_s", "current_raw_ma", "current_corrected_ma",
               "vibration1_code", "vibration2_code", "vibration3_code",
               "speed_raw_q16_16", "target_q16_16", "ctrl", "flags",
               "fault_code", "sample_count", "sample_age_cycles",
               "adc_error_count", "pl_ticks", "trial_status")


def u32(page, offset):
    return struct.unpack_from("<I", page, offset)[0]


def i32(page, offset):
    return struct.unpack_from("<i", page, offset)[0]


def w32(page, offset, value):
    struct.pack_into("<I", page, offset, value)


Sample = namedtuple("Sample", ("seq flags speed_q16 current_ma vibration "
                               "sample_count sample_age adc_errors fault_code "
                               "target_q16 ctrl ticks trial"))


class MotorDevice:
    """Single-owner MMIO access. Other snapshot programs must not run."""

    def __init__(self, exclusive=True):
        self.exclusive = exclusive
        self.lock_fd = None
        self.mem_fd = None
        self.status = None
        self.gpio = None

    def acquire_lock(self):
        import fcntl  # Linux target only; allow host-side unit tests to import.
        flags = os.O_CREAT | os.O_RDWR | getattr(os, "O_NOFOLLOW", 0)
        if self.lock_fd is None:
            self.lock_fd = os.open(LOCK_PATH, flags, 0o600)
            fcntl.flock(self.lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)

    def __enter__(self):
        try:
            if self.exclusive:
                self.acquire_lock()
            self.mem_fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
            self.status = mmap.mmap(self.mem_fd, mmap.PAGESIZE,
                                    flags=mmap.MAP_SHARED,
                                    prot=mmap.PROT_READ | mmap.PROT_WRITE,
                                    offset=STATUS_BASE)
            return self
        except BaseException:
            self.__exit__(None, None, None)
            raise

    def __exit__(self, _kind, _value, _traceback):
        for page in (self.gpio, self.status):
            if page is not None:
                page.close()
        for fd in (self.mem_fd, self.lock_fd):
            if fd is not None:
                os.close(fd)
        self.gpio = self.status = self.mem_fd = self.lock_fd = None

    def verify_image(self, expected=FEATURES):
        identity = (u32(self.status, 0), u32(self.status, 4),
                    u32(self.status, 0x54))
        if identity != (ID, ABI, expected):
            raise RuntimeError("Wrong PL image/ABI/features: {} (need features "
                               "0x{:08X})".format(
                                   tuple("0x{:08X}".format(x) for x in identity),
                                   expected))
        if expected in TRACED_GUARDED_IMAGES and (
                u32(self.status, 0x200), u32(self.status, 0x204)) != (0x45545231, ABI):
            raise RuntimeError("Encoder trace ID/ABI mismatch; no writes made")
        if expected in OBSERVATION_IMAGES and (
                u32(self.status, 0x400), u32(self.status, 0x404)) != (0x454C4731, ABI):
            raise RuntimeError("Encoder observation ID/ABI mismatch; no writes made")

    def capture(self):
        previous = u32(self.status, 0x0C)
        for _ in range(3):
            w32(self.status, 0x08, 1)
            seq = u32(self.status, 0x0C)
            values = (u32(self.status, 0x10), u32(self.status, 0x14),
                      i32(self.status, 0x18),
                      tuple(i32(self.status, x) for x in (0x1C, 0x20, 0x24)),
                      u32(self.status, 0x28), u32(self.status, 0x2C),
                      u32(self.status, 0x3C), u32(self.status, 0x30),
                      u32(self.status, 0x34), u32(self.status, 0x38),
                      (u32(self.status, 0x44) << 32) | u32(self.status, 0x40))
            if seq != previous and seq == u32(self.status, 0x0C) and values[0] & 1:
                return Sample(seq, *values, u32(self.status, 0x58))
            previous = u32(self.status, 0x0C)
        raise RuntimeError("No coherent snapshot; stop other snapshot readers")

    def check_fresh(self, previous_count=None, previous_errors=None):
        sample = self.capture()
        if not sample.flags & 2 or sample.flags & 4:
            raise RuntimeError("ADC has no valid frame or reports an error")
        if sample.sample_age > 10_000:
            raise RuntimeError("ADC sample is stale (>100 us at 100 MHz)")
        if (previous_count is not None and
                sample.sample_count == previous_count):
            raise RuntimeError("ADC sample count stopped")
        if previous_errors is not None and sample.adc_errors != previous_errors:
            raise RuntimeError("ADC error count increased")
        return sample

    def check_adc(self):
        first = self.capture()
        before = u32(self.status, 0x4C)
        time.sleep(0.05)
        after = u32(self.status, 0x4C)
        live = u32(self.status, 0x48)
        if after == before or not live & 2 or live & 4:
            raise RuntimeError("ADC has no fresh valid frames")
        sample = self.check_fresh(first.sample_count, first.adc_errors)
        return sample

    def map_gpio(self):
        if self.gpio is None:
            self.gpio = mmap.mmap(self.mem_fd, mmap.PAGESIZE,
                                  flags=mmap.MAP_SHARED,
                                  prot=mmap.PROT_READ | mmap.PROT_WRITE,
                                  offset=GPIO_BASE)

    def neutralize(self):
        """Disarm PL before neutralizing GPIO. The hardware latch remains used."""
        if u32(self.status, 0x54) in GUARDED_IMAGES:
            w32(self.status, 0x108, GUARD_STOP)
        w32(self.status, 0x58, 0)
        self.map_gpio()
        w32(self.gpio, 0x08, 0)  # ctrl=FREE
        w32(self.gpio, 0x00, 0)  # target=0
        w32(self.gpio, 0x0C, 0)  # ctrl channel output
        w32(self.gpio, 0x04, 0)  # target channel output


def baseline(device, count, interval):
    first = device.check_adc()
    if u32(device.status, 0x58) & 1 or u32(device.status, 0x48) & 0x40:
        raise RuntimeError("Drive is active; cannot determine no-drive baseline")
    current = []
    vibration = [[], [], []]
    records = []
    previous = first.sample_count
    errors = first.adc_errors
    started = time.monotonic()
    for _ in range(count):
        time.sleep(interval)
        sample = device.check_fresh(previous, errors)
        previous = sample.sample_count
        current.append(sample.current_ma)
        for channel in range(3):
            vibration[channel].append(sample.vibration[channel])
        records.append(("baseline", time.monotonic() - started, sample))
    offset = statistics.median(current)
    if abs(offset) >= 1000:
        raise RuntimeError("No-drive current is >=1 A from nominal zero; check wiring")
    vib_zero = tuple(statistics.median(channel) for channel in vibration)
    return offset, vib_zero, min(current), max(current), records


def csv_row(phase, seconds, sample, offset):
    return (phase, "{:.6f}".format(seconds), sample.current_ma,
            "{:.1f}".format(sample.current_ma - offset), *sample.vibration,
            sample.speed_q16, sample.target_q16, sample.ctrl,
            "0x{:08X}".format(sample.flags),
            "0x{:08X}".format(sample.fault_code),
            sample.sample_count, sample.sample_age, sample.adc_errors,
            sample.ticks,
            "0x{:08X}".format(sample.trial))


def save_records(path, records, offset):
    if not path:
        return
    with open(path, "x", newline="") as output:
        writer = csv.writer(output)
        writer.writerow(CSV_COLUMNS)
        for phase, seconds, sample in records:
            writer.writerow(csv_row(phase, seconds, sample, offset))
    print("Saved {} PS snapshots to {}".format(len(records), path))


def format_faults(sample):
    names = ("encoder invalid transition", "startup no feedback",
             "running feedback lost")
    return [name for bit, name in enumerate(names) if sample.fault_code & 1 << bit]


def show_status(device):
    sample = device.capture()
    live = u32(device.status, 0x48)
    features = u32(device.status, 0x54)
    print("PL=0x{:08X} ABI=0x{:08X} features=0x{:08X}".format(
        u32(device.status, 0), u32(device.status, 4), features))
    print("live=0x{:08X} trial=0x{:08X} seq={} samples={} age={} cycles "
          "ADC errors={}".format(live, sample.trial, sample.seq,
                                sample.sample_count, sample.sample_age,
                                sample.adc_errors))
    if features == OPEN_LOOP_FEATURES:
        fault_names = ["invalid open-loop command"] if sample.fault_code & 1 else []
    else:
        fault_names = format_faults(sample)
    print("IN5 raw current={} mA; vibration raw codes={}; faults={}".format(
        sample.current_ma, sample.vibration, fault_names))
    if features == OPEN_LOOP_FEATURES:
        print("open-loop requested duty={}%, applied duty={}%, ctrl={}; RPM unavailable".format(
            sample.target_q16, u32(device.status, 0x168), sample.ctrl))
    else:
        print("speed raw Q16.16={} target raw Q16.16={} ctrl={}".format(
            sample.speed_q16, sample.target_q16, sample.ctrl))
    if features in GUARDED_IMAGES:
        if u32(device.status, 0x100) != GUARD_ID or u32(device.status, 0x104) != ABI:
            raise RuntimeError("PL guard ID/ABI mismatch")
        faults = u32(device.status, 0x124)
        print("guard status=0x{:02X} faults=0x{:02X} {} heartbeat_age={}ms run_age={}ms".format(
            u32(device.status, 0x120), faults,
            [name for bit, name in enumerate(GUARD_FAULT_NAMES) if faults & (1 << bit)],
            u32(device.status, 0x12c), u32(device.status, 0x138)))
        print("guard current_zero={}mA current_limit={}mA watchdog={}ms run_limit={}ms".format(
            i32(device.status, 0x110), u32(device.status, 0x114),
            u32(device.status, 0x118), u32(device.status, 0x11c)))
        if features in TRACED_GUARDED_IMAGES:
            print("encoder qualification={} cycles rejected={} trace_status=0x{:02X}".format(
                u32(device.status, 0x228), u32(device.status, 0x238),
                u32(device.status, 0x208)))
        if features in OBSERVATION_IMAGES:
            print("long observation status=0x{:02X} pre_events={} post_events={} dropped_post={}".format(
                u32(device.status, 0x408), u32(device.status, 0x418),
                u32(device.status, 0x420), u32(device.status, 0x43c)))


def run_monitor(device, args):
    offset, vib_zero, low, high, records = baseline(
        device, args.baseline_samples, args.interval)
    print("No-drive baseline={:.1f} mA [{}..{}], vibration={}".format(
        offset, low, high, vib_zero))
    previous = records[-1][2].sample_count
    errors = records[-1][2].adc_errors
    min_current = max_current = 0.0
    peaks = [0, 0, 0]
    captures = 0
    with contextlib.ExitStack() as stack:
        file = stack.enter_context(open(args.csv, "x", newline="")) if args.csv else None
        writer = csv.writer(file) if file is not None else None
        if writer:
            writer.writerow(CSV_COLUMNS)
            for phase, seconds, sample in records:
                writer.writerow(csv_row(phase, seconds, sample, offset))
        start = time.monotonic()
        next_report = start + args.report_interval
        while time.monotonic() - start < args.seconds:
            time.sleep(args.interval)
            sample = device.check_fresh(previous, errors)
            previous = sample.sample_count
            seconds = time.monotonic() - start
            captures += 1
            if writer:
                writer.writerow(csv_row("monitor", seconds, sample, offset))
            corrected = sample.current_ma - offset
            min_current = min(min_current, corrected)
            max_current = max(max_current, corrected)
            for i in range(3):
                peaks[i] = max(peaks[i], abs(sample.vibration[i] - vib_zero[i]))
            if time.monotonic() >= next_report:
                print("t={:.2f}s current={:+.1f}mA observed range="
                      "[{:+.1f},{:+.1f}]mA vibration peak delta={}".format(
                          seconds, corrected, min_current, max_current, peaks))
                next_report += args.report_interval
    if args.csv:
        print("Saved {} PS snapshots to {}".format(len(records) + captures,
                                                     args.csv))
    print("PASS: {} PS snapshots; observed current range [{:+.1f},{:+.1f}] mA; "
          "vibration peak delta {} codes. Short peaks can be missed.".format(
              len(records) + captures, min_current, max_current, peaks))


def run_trial(device, args):
    if u32(device.status, 0x58) != 0 or u32(device.status, 0x48) & 0x10:
        raise RuntimeError("Trial already used/faulted; power-cycle PL to retry")
    offset, vib_zero, low, high, records = baseline(
        device, args.baseline_samples, args.interval)
    print("No-drive baseline={:.1f} mA [{}..{}], vibration={}".format(
        offset, low, high, vib_zero))
    if args.csv and os.path.exists(args.csv):
        raise FileExistsError("CSV already exists: " + args.csv)
    device.map_gpio()
    previous = records[-1][2].sample_count
    errors = records[-1][2].adc_errors
    min_current = max_current = 0.0
    peaks = [0, 0, 0]
    trip_reason = None
    final = 0
    captures = 0
    start = None
    try:
        device.neutralize()
        w32(device.gpio, 0x00, 1 << 16)  # Core requires a nonzero target.
        w32(device.gpio, 0x08, 1 if args.direction == "forward" else 2)
        time.sleep(0.15)  # Allow encoder-stopped qualification.
        device.check_fresh(previous, errors)
        w32(device.status, 0x58, ARM_MAGIC)
        if u32(device.status, 0x58) & 3 != 3:
            raise RuntimeError("PL guard refused arm")
        print("ARMED: one fixed 20% PWM, 0.5 s pulse; PS observed-current "
              "stop threshold={} mA (not hardware protection)".format(
                  args.ps_stop_ma))
        start = time.monotonic()
        while time.monotonic() - start < 0.75:
            sample = device.check_fresh(previous, errors)
            previous = sample.sample_count
            seconds = time.monotonic() - start
            records.append(("pulse", seconds, sample))
            captures += 1
            corrected = sample.current_ma - offset
            min_current = min(min_current, corrected)
            max_current = max(max_current, corrected)
            for i in range(3):
                peaks[i] = max(peaks[i], abs(sample.vibration[i] - vib_zero[i]))
            if abs(corrected) >= args.ps_stop_ma:
                trip_reason = "PS observed current exceeded requested stop threshold"
                device.neutralize()
                break
            if sample.fault_code or sample.trial & 0x1C:
                trip_reason = "PL/core fault during trial"
                device.neutralize()
                break
            if not sample.trial & 1:
                break
            time.sleep(args.interval)
        final = u32(device.status, 0x58)
        if final & 1:
            trip_reason = trip_reason or "trial did not stop within 0.75 s"
        elif final & 0x1C:
            trip_reason = trip_reason or "PL/core fault latched"
        elif not final & 2:
            trip_reason = trip_reason or "one-shot used flag missing"
        elif final & 0x20 and time.monotonic() - start < 0.45:
            trip_reason = trip_reason or "pulse ended before normal 0.5 s timeout"
    finally:
        device.neutralize()
        save_records(args.csv, records, offset)
    print("trial=0x{:08X}, captures={}, observed corrected current="
          "[{:+.1f},{:+.1f}]mA, vibration peak delta={}".format(
              final, captures, min_current, max_current, peaks))
    if trip_reason:
        raise RuntimeError(trip_reason)
    print("PASS: one-shot command finished. Visually confirm rotation; "
          "short current peaks and true speed were NOT measured.")


def rpm_to_q16(rpm, encoder_counts=PL_ENCODER_COUNTS,
               pl_counts=PL_ENCODER_COUNTS):
    if not math.isfinite(rpm):
        raise ValueError("Target RPM must be finite")
    if encoder_counts <= 0 or pl_counts <= 0:
        raise ValueError("Encoder counts must be positive")
    value = round(rpm * encoder_counts * 65536.0 / (60.0 * pl_counts))
    if value <= 0 or value > 0xFFFFFFFF:
        raise ValueError("Target RPM is outside unsigned Q16.16 range")
    return value


def measured_rpm(raw, encoder_counts, pl_counts=PL_ENCODER_COUNTS):
    return raw * pl_counts * 60.0 / (65536.0 * encoder_counts)


def parse_speed_step(text):
    try:
        second, rpm = map(float, text.split(":"))
        if not math.isfinite(second) or not math.isfinite(rpm):
            raise ValueError
        return second, rpm
    except ValueError:
        raise argparse.ArgumentTypeError("speed-step must be SECOND:RPM")


def speed_plan(args, encoder_counts, pl_counts):
    result = [(0.0, args.rpm, rpm_to_q16(args.rpm, encoder_counts, pl_counts))]
    for second, rpm in args.speed_step:
        if not (result[-1][0] < second < args.seconds and 0 <= rpm <= args.rated_rpm):
            raise ValueError("Speed steps must increase in time, precede stop and stay within rated RPM")
        result.append((second, rpm, rpm_to_q16(rpm, encoder_counts, pl_counts) if rpm else 0))
    return result


def prepare_guard(device, args, offset):
    if u32(device.status, 0x100) != GUARD_ID or u32(device.status, 0x104) != ABI:
        raise RuntimeError("PL continuous guard ID/ABI mismatch")
    if u32(device.status, 0x124):
        raise RuntimeError("PL guard fault latched; inspect and explicitly clear it before retry")
    values = ((0x110, int(round(offset)) & 0xffffffff),
              (0x114, args.pl_current_limit_ma),
              (0x118, args.guard_watchdog_ms),
              (0x11c, 0 if getattr(args, 'continuous', False)
               else math.ceil(args.seconds * 1000) + 100))
    for address, value in values:
        w32(device.status, address, value)
        if u32(device.status, address) != value:
            raise RuntimeError("PL guard configuration readback failed")
    w32(device.status, 0x108, GUARD_ARM)
    if not u32(device.status, 0x120) & 1 or u32(device.status, 0x124):
        raise RuntimeError("PL guard refused arming: verify neutral command, fresh ADC and baseline")
    return u32(device.status, 0x10c)


def refresh_guard(device, token):
    token = (token + 1) & 0xffffffff or 1
    w32(device.status, 0x10c, token)
    if u32(device.status, 0x124) or not u32(device.status, 0x120) & 1:
        raise RuntimeError("PL guard stopped motor: faults=0x{:02X}".format(
            u32(device.status, 0x124)))
    return token


class ContinuousCSV:
    """Stream snapshots instead of retaining an hour of samples in RAM."""
    def __init__(self, path, offset, encoder_counts, pl_counts):
        self.output = None
        self.writer = None
        self.offset, self.encoder_counts, self.pl_counts = offset, encoder_counts, pl_counts
        if path:
            self.output = open(path, "x", newline="")
            try:
                self.writer = csv.writer(self.output)
                self.writer.writerow(CSV_COLUMNS + ("speed_rpm", "target_rpm", "encoder_counts_per_rev"))
            except BaseException:
                self.output.close()
                raise

    def append(self, phase, seconds, sample):
        if self.writer:
            self.writer.writerow(csv_row(phase, seconds, sample, self.offset) + (
                measured_rpm(sample.speed_q16, self.encoder_counts, self.pl_counts),
                measured_rpm(sample.target_q16, self.encoder_counts, self.pl_counts),
                self.encoder_counts))

    def close(self):
        if self.output:
            self.output.close()


def run_continuous(device, args):
    """Set PL closed-loop target, supervise samples, always neutralize on exit."""
    if u32(device.status, 0x54) in (BYPASS_GUARDED_FEATURES, *OBSERVATION_IMAGES):
        raise RuntimeError("This is a bounded encoder comparison image; continuous drive is disabled")
    guarded = u32(device.status, 0x54) in GUARDED_IMAGES
    if args.pl_guard and not guarded:
        raise RuntimeError("PL guard requested but guarded image 0x143/0x343 is not loaded")
    if u32(device.status, 0x48) & 0x50 or u32(device.status, 0x50):
        raise RuntimeError("Motor is already active or has a latched fault")
    if guarded and (u32(device.status, 0x120) & 3 or u32(device.status, 0x124)):
        raise RuntimeError("PL guard already active or faulted; inspect before running")
    encoder_counts = 4 * args.encoder_ppr * args.gear_ratio
    pl_counts = u32(device.status, 0x130) if guarded else PL_ENCODER_COUNTS
    if pl_counts <= 0 or encoder_counts <= 0:
        raise RuntimeError("Encoder scale is invalid")
    plan = speed_plan(args, encoder_counts, pl_counts)
    offset, vib_zero, low, high, records = baseline(
        device, args.baseline_samples, args.interval)
    print("No-drive baseline={:.1f} mA [{}..{}], vibration={}".format(
        offset, low, high, vib_zero))
    if args.csv and os.path.exists(args.csv):
        raise FileExistsError("CSV already exists: " + args.csv)
    print("Encoder: {} PPR x {} gear x4 = {} counts/output revolution".format(
        args.encoder_ppr, args.gear_ratio, encoder_counts))
    _second, requested_rpm, target = plan[0]
    direction = 1 if args.direction == "forward" else 2
    device.map_gpio()
    previous = records[-1][2].sample_count
    errors = records[-1][2].adc_errors
    min_current = max_current = 0.0
    max_observed_rpm = 0.0
    peaks = [0, 0, 0]
    captures = 0
    started = None
    failure = None
    log = ContinuousCSV(args.csv, offset, encoder_counts, pl_counts)
    step_index = 1
    try:
        for phase, seconds, record in records:
            log.append(phase, seconds, record)
        records.clear()
        device.neutralize()
        if guarded:
            token = prepare_guard(device, args, offset)
            token = refresh_guard(device, token)
        w32(device.gpio, 0x00, target)
        w32(device.gpio, 0x08, direction)
        started = time.monotonic()
        next_report = started + args.report_interval
        while time.monotonic() - started < args.seconds:
            time.sleep(max(0.0, min(args.interval, args.seconds - (time.monotonic() - started))))
            seconds = time.monotonic() - started
            if seconds >= args.seconds:
                break
            if guarded:
                token = refresh_guard(device, token)
            while step_index < len(plan) and seconds >= plan[step_index][0]:
                _second, requested_rpm, target = plan[step_index]
                w32(device.gpio, 0x00, target)
                w32(device.gpio, 0x08, direction if target else 0)
                step_index += 1
            sample = device.check_fresh(previous, errors)
            previous = sample.sample_count
            seconds = time.monotonic() - started
            log.append("running", seconds, sample)
            captures += 1
            corrected = sample.current_ma - offset
            rpm = measured_rpm(sample.speed_q16, encoder_counts, pl_counts)
            min_current = min(min_current, corrected)
            max_current = max(max_current, corrected)
            max_observed_rpm = max(max_observed_rpm, rpm)
            for i in range(3):
                peaks[i] = max(peaks[i], abs(sample.vibration[i] - vib_zero[i]))
            if guarded and (u32(device.status, 0x124) or not u32(device.status, 0x120) & 1):
                failure = "PL guard stopped motor: faults=0x{:02X}".format(u32(device.status, 0x124))
            elif sample.target_q16 != target or sample.ctrl != (direction if target else 0):
                failure = "PL target/direction readback does not match command"
            elif sample.fault_code or sample.flags & 0x10 or u32(device.status, 0x50):
                failure = "PL motor fault latched: {}".format(format_faults(sample))
            elif abs(corrected) >= args.ps_stop_ma:
                failure = "PS observed current exceeded requested stop threshold"
            elif rpm > args.rated_rpm * 1.1:
                failure = "Observed speed exceeded 110% of stated rated RPM"
            if failure:
                device.neutralize()
                break
            if time.monotonic() >= next_report:
                print("t={:.2f}s speed={:.1f}/{:.1f}rpm current={:+.1f}mA "
                      "vibration peak delta={}".format(
                          seconds, rpm, requested_rpm, corrected, peaks))
                next_report += args.report_interval
    finally:
        try:
            device.neutralize()
        finally:
            log.close()
    print("captures={} observed speed max={:.1f}rpm current="
          "[{:+.1f},{:+.1f}]mA vibration peak delta={}".format(
              captures, max_observed_rpm, min_current, max_current, peaks))
    if failure:
        raise RuntimeError(failure)
    print("PASS: timed continuous-control command completed; motor outputs "
          "returned to FREE. Verify actual speed/behavior on the board.")


def parser_definition():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command")
    commands.required = True  # Python 3.6 on some Bionic boards.
    commands.add_parser("status", help="Read image, trial state and one snapshot")
    commands.add_parser("check", help="Check image and fresh ADC frames")
    commands.add_parser("stop", help="Disarm PL and set motor GPIO neutral")
    commands.add_parser("clear-fault", help="Explicitly acknowledge only the PL run-guard fault while neutral")
    zero = commands.add_parser("zero", help="Measure no-drive sensor baseline")
    monitor = commands.add_parser("monitor", help="Log PS current/vibration snapshots")
    trial = commands.add_parser("trial", help="Run the single PL-guarded test pulse")
    continuous = commands.add_parser("continuous", help="Run timed PL closed-loop speed control")
    for item in (zero, monitor, trial, continuous):
        item.add_argument("--baseline-samples", type=int, default=100)
        item.add_argument("--interval", type=float, default=0.002)
    for item in (monitor, trial, continuous):
        item.add_argument("--csv", help="New CSV path; existing files are preserved")
    monitor.add_argument("--seconds", type=float, default=10)
    monitor.add_argument("--report-interval", type=float, default=0.5)
    trial.add_argument("--direction", choices=("forward", "reverse"), default="forward")
    trial.add_argument("--motor-vm", type=float, required=True)
    trial.add_argument("--ps-stop-ma", type=int, default=1500)
    trial.add_argument("--encoder-grounded", action="store_true")
    trial.add_argument("--sensor-in-motor-lead", action="store_true")
    trial.add_argument("--motor-unloaded", action="store_true")
    trial.add_argument("--accept-no-hardware-current-cutoff", action="store_true")
    continuous.add_argument("--rpm", type=float, required=True)
    continuous.add_argument("--rated-rpm", type=float, required=True)
    continuous.add_argument("--seconds", type=float, required=True)
    continuous.add_argument("--report-interval", type=float, default=0.5)
    continuous.add_argument("--direction", choices=("forward", "reverse"),
                            default="forward")
    continuous.add_argument("--motor-vm", type=float, required=True)
    continuous.add_argument("--ps-stop-ma", type=int, default=1500)
    continuous.add_argument("--encoder-connected", action="store_true")
    continuous.add_argument("--sensor-in-motor-lead", action="store_true")
    continuous.add_argument("--external-current-limit", action="store_true")
    continuous.add_argument("--external-command-watchdog", action="store_true")
    continuous.add_argument("--encoder-ppr", type=int, default=500)
    continuous.add_argument("--gear-ratio", type=int, default=20)
    continuous.add_argument("--speed-step", action="append", type=parse_speed_step,
                            default=[], help="Change RPM at SECOND:RPM; repeat in increasing time order")
    continuous.add_argument("--pl-guard", action="store_true", help="Require hardware-guarded image 0x143/0x343")
    continuous.add_argument("--pl-current-limit-ma", type=int,
                            help="Explicit ADC-derived hardware trip threshold relative to this run's baseline")
    continuous.add_argument("--guard-watchdog-ms", type=int, default=100)
    return parser


def main(argv=None):
    parser = parser_definition()
    args = parser.parse_args(argv)
    if os.geteuid() != 0:
        parser.error("Run as root for /dev/mem access")
    if args.command in ("zero", "monitor", "trial", "continuous"):
        if not (20 <= args.baseline_samples <= 10000 and
                math.isfinite(args.interval) and args.interval >= 0.001):
            parser.error("baseline-samples >=20 and interval >=0.001 s required")
    if args.command == "monitor":
        if not 0 < args.seconds <= 3600 or args.report_interval < 0.1:
            parser.error("0 < seconds <=3600 and report-interval >=0.1 required")
    if args.command == "trial":
        if not (0 < args.motor_vm <= 12 and args.encoder_grounded and
                args.sensor_in_motor_lead and args.motor_unloaded and
                args.accept_no_hardware_current_cutoff and
                0 < args.ps_stop_ma < 2000):
            parser.error("trial requires confirmed VM <=12 V, encoder grounded, "
                         "ACS712 in AO1 lead, unloaded motor, acceptance of "
                         "NO hardware current cutoff, and 0<ps-stop-ma<2000")
    if args.command == "continuous":
        if not (math.isfinite(args.rated_rpm) and
                0 < args.motor_vm <= 12 and 0 < args.rpm <= args.rated_rpm and
                0 < args.seconds <= 3600 and 0 < args.ps_stop_ma < 2000 and
                0.001 <= args.interval <= 0.1 and args.report_interval >= 0.1 and
                args.encoder_connected and args.sensor_in_motor_lead and
                args.external_current_limit and (args.pl_guard or args.external_command_watchdog)):
            parser.error("continuous requires VM <=12 V, 0<rpm<=rated-rpm, "
                         "0<seconds<=3600, 0<ps-stop-ma<2000, wired encoder "
                         "and current sensor, and REAL external current limit "
                         "and command watchdog (or --pl-guard)")
        try:
            if args.encoder_ppr <= 0 or args.gear_ratio <= 0 or \
                    4 * args.encoder_ppr * args.gear_ratio > 0xffffffff:
                raise ValueError("Encoder PPR/gear ratio must be positive and fit a 32-bit x4 count")
            speed_plan(args, 4 * args.encoder_ppr * args.gear_ratio, PL_ENCODER_COUNTS)
            if args.pl_guard and not (args.pl_current_limit_ma is not None and
                    0 < args.pl_current_limit_ma < 2000 and
                    10 <= args.guard_watchdog_ms <= 1000 and
                    args.interval * 1000 <= args.guard_watchdog_ms / 5):
                raise ValueError("PL guard requires an explicit 0<pl-current-limit-ma<2000, "
                                 "10..1000 ms watchdog and polling at least five times faster")
        except ValueError as error:
            parser.error(str(error))
    if getattr(args, "csv", None) and os.path.exists(args.csv):
        parser.error("CSV already exists; choose a new path")
    def terminate(_number, _frame):
        raise KeyboardInterrupt

    old_term = signal.signal(signal.SIGTERM, terminate)
    try:
        with MotorDevice(exclusive=args.command != "stop") as device:
            if args.command in ("trial", "continuous"):
                if args.command == "continuous":
                    actual = u32(device.status, 0x54)
                    expected = ((actual if actual in CONTINUOUS_GUARDED_IMAGES else GUARDED_FEATURES)
                                if args.pl_guard else DMA_CONTINUOUS_FEATURES
                                if actual == DMA_CONTINUOUS_FEATURES
                                else CONTINUOUS_FEATURES)
                else:
                    expected = FEATURES
            else:
                expected = u32(device.status, 0x54)
                if expected not in (FEATURES, CONTINUOUS_FEATURES,
                                    DMA_CONTINUOUS_FEATURES, SAFE_DMA_FEATURES, *GUARDED_IMAGES):
                    raise RuntimeError("Unsupported PL feature flags 0x{:08X}".
                                       format(expected))
            device.verify_image(expected)
            if args.command == "status":
                show_status(device)
            elif args.command == "check":
                sample = device.check_adc()
                print("PASS: image 0x{:X} and fresh ADC frames; samples={} "
                      "ADC errors={} trial=0x{:08X}".format(
                          expected, sample.sample_count,
                          sample.adc_errors, sample.trial))
            elif args.command == "stop":
                if expected in GUARDED_IMAGES:
                    if u32(device.status, 0x100) != GUARD_ID or u32(device.status, 0x104) != ABI:
                        raise RuntimeError("PL guard ID/ABI mismatch")
                    w32(device.status, 0x108, GUARD_ESTOP)
                    if not u32(device.status, 0x124) & 0x80:
                        raise RuntimeError("PL guard did not acknowledge operator stop")
                else:
                    device.acquire_lock()
                device.neutralize()
                print("STOP: PL disarmed, GPIO command and target neutral")
            elif args.command == "clear-fault":
                if expected not in GUARDED_IMAGES:
                    raise RuntimeError("clear-fault requires a known guarded image")
                if u32(device.status, 0x100) != GUARD_ID or u32(device.status, 0x104) != ABI:
                    raise RuntimeError("PL guard ID/ABI mismatch")
                if u32(device.status, 0x120) & 1 or u32(device.status, 0x50) or \
                        u32(device.status, 0x48) & 0x40:
                    raise RuntimeError("Cannot acknowledge an active/core-faulted motor")
                device.neutralize()
                w32(device.status, 0x108, GUARD_CLEAR)
                if u32(device.status, 0x124):
                    raise RuntimeError("PL guard refused fault acknowledgement; inspect current/ADC/core state")
                print("ACK: run-guard fault cleared; motor remains disarmed")
            elif args.command == "zero":
                offset, vibration, low, high, _records = baseline(
                    device, args.baseline_samples, args.interval)
                print("No-drive baseline={:.1f} mA [{}..{}]; vibration={}".format(
                    offset, low, high, vibration))
            elif args.command == "monitor":
                run_monitor(device, args)
            elif args.command == "continuous":
                print("WARNING: motor VM={} V is user-confirmed, not measured; "
                      "external cutoff/watchdog confirmations are not measurable "
                      "by PS.".format(args.motor_vm))
                run_continuous(device, args)
            else:
                print("WARNING: VM={} V is user-confirmed, not measured; PS "
                      "polling cannot guarantee overcurrent protection.".format(
                          args.motor_vm))
                run_trial(device, args)
        return 0
    except KeyboardInterrupt:
        print("Interrupted; motor outputs are neutralized if they were armed.",
              file=sys.stderr)
        return 130
    except (OSError, RuntimeError) as error:
        print("FAIL: {}".format(error), file=sys.stderr)
        return 1
    finally:
        signal.signal(signal.SIGTERM, old_term)


if __name__ == "__main__":
    raise SystemExit(main())
