#!/usr/bin/env python3
"""Guarded open-loop motor control for exact PL image 0x4143.

No encoder/RPM interpretation. Duty is an integer percent. The old motor
image and scripts remain distinct. This file has no automatic fault clear or
retry, and never substitutes AI output for the PL safety guard.
"""
import argparse
import csv
import math
import os
import signal
import stat
import sys
import time

import motor_ps as ps


OPEN_LOOP_ID = 0x4F4C5031  # OLP1
DUTY_MIN = 15
DUTY_MAX = 60
MG310_RATED_VOLTAGE_V = 7.4
MG310_RATED_CURRENT_MA = 500
MG310_STALL_CURRENT_MA = 2000
DRIVER_VM_MIN_V = 8.0    # User-reported driver supply requirement: 8..15 V.
DRIVER_VM_MAX_V = 15.0
SOFTWARE_VM_MAX_V = 12.0  # Candidate policy; 13..15 V has not been validated.
# Engineering startup value, not a datasheet limit or a calibrated trip test.
# It is above the rated reference and below the specified stall current.
DEFAULT_PL_TRIP_MA = 1000
WATCHDOG_MS = 100
POLL_S = .005
BASELINE_SAMPLES = 100
LEASE_MAX_AGE_S = 5.0


def require_live_lease(path):
    if not path:
        return
    info = os.stat(path, follow_symlinks=False)
    age = time.time() - info.st_mtime
    if not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or age < 0 or age > LEASE_MAX_AGE_S:
        raise RuntimeError("desktop motor lease expired or invalid; stop")


def verify_image(device):
    device.verify_image(ps.OPEN_LOOP_FEATURES)
    expected = ((0x100, ps.GUARD_ID), (0x104, ps.ABI),
                (0x130, 40000), (0x134, 100000000),
                (0x160, OPEN_LOOP_ID), (0x164, ps.ABI),
                (0x16c, DUTY_MIN), (0x170, DUTY_MAX),
                (0x174, 10000), (0x178, 10))
    if any(ps.u32(device.status, addr) != value for addr, value in expected):
        raise RuntimeError("Wrong open-loop/guard identity or metadata; no drive writes")


def require_idle(device):
    if ps.u32(device.status, 0x120) & 3 or ps.u32(device.status, 0x124):
        raise RuntimeError("Guard active/faulted; no automatic clear or retry")
    if ps.u32(device.status, 0x48) & 0x1d0 or ps.u32(device.status, 0x50):
        raise RuntimeError("Motor outputs active or core fault present")
    if ps.u32(device.gpio, 0) or ps.u32(device.gpio, 8):
        raise RuntimeError("GPIO target/control not neutral; no arming")


def preflight(device):
    verify_image(device)
    device.map_gpio()
    require_idle(device)
    device.check_adc()
    offset, vib_zero, low, high, records = ps.baseline(
        device, BASELINE_SAMPLES, .002)
    require_idle(device)
    if max(abs(low - offset), abs(high - offset)) >= 400:
        raise RuntimeError("No-drive current varies by >=400 mA; no arming")
    print("Preflight: 0x4143, ADC fresh, outputs disabled, no encoder required")
    print("No-drive current baseline={:.1f} mA range=[{},{}]; vibration={}".format(
        offset, low, high, vib_zero))
    return offset, vib_zero, records[-1][2]


def verify_disabled(device):
    deadline = time.monotonic() + .05
    while True:
        if (not ps.u32(device.status, 0x120) & 1 and
                not ps.u32(device.status, 0x48) & 0x1c0 and
                not ps.u32(device.gpio, 0) and
                not ps.u32(device.gpio, 8) and
                ps.u32(device.status, 0x168) == 0):
            return
        if time.monotonic() >= deadline:
            raise RuntimeError("STOP readback failed; disconnect motor VM")
        time.sleep(.001)


def run_motor(device, args, offset, vib_zero, sample):
    min_current = max_current = 0.0
    vibration_peaks = [0, 0, 0]
    peak_duty = 0
    snapshots = 0
    output = open(args.csv, "x", newline="") if args.csv else None
    if args.continuous:
        print("Forward open-loop: requested duty={}%, no duration limit; "
              "PL heartbeat/ADC/current guard remains active".format(args.duty_percent))
    else:
        print("Forward open-loop: requested duty={}%, PS limit={}s, PL limit=PS+100ms".format(
            args.duty_percent, args.seconds))
    print("MG310: rated <= {}mA at {}V; stall <= {}mA; PL trip={}mA "
          "(provisional, not stall detection)".format(
              MG310_RATED_CURRENT_MA, MG310_RATED_VOLTAGE_V,
              MG310_STALL_CURRENT_MA, args.pl_current_limit_ma))
    print("Driver VM={}V (operator-reported; driver input requirement {}..{}V). "
          "Motor winding rating={}V is a separate specification.".format(
              args.motor_vm, DRIVER_VM_MIN_V, DRIVER_VM_MAX_V,
              MG310_RATED_VOLTAGE_V))
    if args.motor_vm > MG310_RATED_VOLTAGE_V:
        print("WARNING: PWM applies VM-height pulses to the winding; "
              "VM x duty is not a substitute for measuring current and heating")
    print("PL: ADC-fresh/current trip, 100ms heartbeat, invalid-command cutoff; "
          "hard deadline only in timed mode")
    print("WARNING: PL current trip uses the same sensor/ADC as telemetry; "
          "validate the trip path before extended operation")
    try:
        writer = csv.writer(output) if output else None
        if writer:
            writer.writerow(("time_s", "sample_count", "sample_ticks",
                             "current_raw_ma", "current_corrected_ma",
                             "vibration1_code", "vibration2_code", "vibration3_code",
                             "vibration1_delta", "vibration2_delta", "vibration3_delta",
                             "duty_requested_percent", "duty_applied_percent",
                             "adc_age_cycles", "adc_errors", "motor_fault", "guard_fault"))
        device.neutralize()
        require_idle(device)
        sample = device.check_fresh(sample.sample_count, sample.adc_errors)
        started = time.monotonic()  # Configuration time is inside the PS deadline.
        config = argparse.Namespace(pl_current_limit_ma=args.pl_current_limit_ma,
                                    guard_watchdog_ms=WATCHDOG_MS,
                                    seconds=args.seconds,
                                    continuous=args.continuous)
        if args.continuous:
            require_live_lease(args.lease_file)
        token = ps.prepare_guard(device, config, offset)
        token = ps.refresh_guard(device, token)
        if not args.continuous and time.monotonic() - started >= args.seconds:
            raise RuntimeError("Configuration exceeded run deadline")
        ps.w32(device.gpio, 0, args.duty_percent)
        ps.w32(device.gpio, 8, 1)
        while True:
            if args.continuous:
                require_live_lease(args.lease_file)
            if args.continuous:
                time.sleep(POLL_S)
            else:
                remaining = args.seconds - (time.monotonic() - started)
                if remaining <= 0:
                    break
                time.sleep(min(POLL_S, remaining))
                if time.monotonic() - started >= args.seconds:
                    break
            sample = device.check_fresh(sample.sample_count, sample.adc_errors)
            snapshots += 1
            corrected = sample.current_ma - offset
            min_current = min(min_current, corrected)
            max_current = max(max_current, corrected)
            vibration_delta = tuple(sample.vibration[i] - vib_zero[i] for i in range(3))
            for i in range(3):
                vibration_peaks[i] = max(vibration_peaks[i], abs(vibration_delta[i]))
            applied = ps.u32(device.status, 0x168)
            peak_duty = max(peak_duty, applied)
            guard_fault = ps.u32(device.status, 0x124)
            if writer:
                writer.writerow((time.monotonic() - started, sample.sample_count,
                                 sample.ticks, sample.current_ma, corrected,
                                 *sample.vibration, *vibration_delta,
                                 args.duty_percent, applied, sample.sample_age,
                                 sample.adc_errors, sample.fault_code, guard_fault))
            if applied > args.duty_percent or applied > DUTY_MAX:
                raise RuntimeError("PL applied duty exceeded request/ceiling")
            if sample.target_q16 != args.duty_percent or sample.ctrl != 1:
                raise RuntimeError("Duty/control command readback mismatch")
            if abs(corrected) >= args.pl_current_limit_ma:
                raise RuntimeError("PS observed current at/above PL trip setting")
            if sample.fault_code or ps.u32(device.status, 0x50) or guard_fault:
                raise RuntimeError("Motor/guard fault latched; stop")
            token = ps.refresh_guard(device, token)
    except KeyboardInterrupt:
        if not args.continuous:
            raise
        print("Operator interrupted continuous run; stopping")
    finally:
        try:
            device.neutralize()
            verify_disabled(device)
            print("STOP verified: guard disabled, duty target=0, ctrl=FREE, bridge inactive")
            print("snapshots={} applied_duty_peak={} current_delta=[{:+.1f},{:+.1f}]mA "
                  "vibration_peak_delta={}".format(
                      snapshots, peak_duty, min_current, max_current, vibration_peaks))
        finally:
            if output:
                output.close()
    if ps.u32(device.status, 0x124) or ps.u32(device.status, 0x50):
        raise RuntimeError("Fault latched at STOP: guard=0x{:02x} core=0x{:02x}".format(
            ps.u32(device.status, 0x124), ps.u32(device.status, 0x50)))
    print("PASS: guarded open-loop run ended normally; true RPM was not measured")


def parser_definition():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--arm", action="store_true", help="Explicitly run one forward session")
    modes.add_argument("--stop", action="store_true", help="Explicitly stop this image")
    parser.add_argument("--duty-percent", type=int, default=15)
    parser.add_argument("--seconds", type=float)
    parser.add_argument("--continuous", action="store_true",
                        help="No duration limit; still requires uninterrupted PS/PL heartbeat")
    parser.add_argument("--lease-file", help="Board-local root-owned file refreshed by desktop controller")
    parser.add_argument("--motor-vm", type=float)
    parser.add_argument("--sensor-in-motor-lead", action="store_true")
    parser.add_argument("--pl-current-limit-ma", type=int, default=DEFAULT_PL_TRIP_MA,
                        help="PL cutoff in mA; default 1000, provisional MG310 setting")
    parser.add_argument("--csv", help="Optional new 200 Hz PS snapshot log; use DMA for 50 kHz waveforms")
    return parser


def validate_args(parser, args):
    if not args.arm:
        return
    if args.csv and os.path.exists(args.csv):
        parser.error("CSV already exists; choose a new file")
    if (args.lease_file and not args.continuous) or (
            args.continuous and args.seconds is not None) or (
            not args.continuous and (args.seconds is None or
                                     not math.isfinite(args.seconds) or
                                     not 0 < args.seconds <= 3600)) or (
            args.motor_vm is None or not math.isfinite(args.motor_vm) or
            not DRIVER_VM_MIN_V <= args.motor_vm <= SOFTWARE_VM_MAX_V or
            not args.sensor_in_motor_lead or
            not 0 < args.pl_current_limit_ma <= 1000 or
            not DUTY_MIN <= args.duty_percent <= DUTY_MAX):
        parser.error("ARM requires --continuous or 0<seconds<=3600, driver VM 8..12V "
                     "(this candidate limits the user-reported 8..15V input range), "
                     "current sensor in motor lead, "
                     "1..1000mA PL trip (default 1000) and 15..60% duty")


def main(argv=None):
    parser = parser_definition()
    args = parser.parse_args(argv)
    validate_args(parser, args)  # No MMIO access before argument validation.
    if os.geteuid() != 0:
        parser.error("Run as root for MMIO access")
    old_handler = signal.getsignal(signal.SIGTERM)
    def interrupted(_signum, _frame):
        raise KeyboardInterrupt()
    signal.signal(signal.SIGTERM, interrupted)
    try:
        # STOP must remain available from a second shell while the controller
        # owns the normal exclusive lock.
        with ps.MotorDevice(exclusive=not args.stop) as device:
            verify_image(device)
            if args.stop:
                ps.w32(device.status, 0x108, ps.GUARD_ESTOP)
                if not ps.u32(device.status, 0x124) & 0x80:
                    raise RuntimeError("PL did not latch operator stop")
                device.neutralize()
                verify_disabled(device)
                print("PASS: open-loop outputs disabled; operator stop latched")
            else:
                offset, vib_zero, sample = preflight(device)
                if args.arm:
                    run_motor(device, args, offset, vib_zero, sample)
                else:
                    print("PASS: preflight only; motor NOT armed")
        return 0
    except KeyboardInterrupt:
        print("Interrupted; no automatic clear or retry", file=sys.stderr)
        return 130
    except (OSError, RuntimeError) as error:
        print("FAIL: {}".format(error), file=sys.stderr)
        return 1
    finally:
        signal.signal(signal.SIGTERM, old_handler)


if __name__ == "__main__":
    raise SystemExit(main())
