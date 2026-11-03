#!/usr/bin/env python3
"""Bounded electric-start test for guarded images; disarmed by default."""

import argparse
import math
import os
import signal
import sys
import time
from collections import namedtuple

import motor_ps as ps


SECONDS = 1.5
WATCHDOG_MS = 100
INTERVAL = .002
BASELINE_SAMPLES = 100
TARGET_RAW = 1  # Nonzero enable request, NOT a meaningful regulated RPM target.
ENCODER_ID = 0x454e4331
USED_PATH = "/run/motor_guarded_trial.used"
Encoder = namedtuple("Encoder", "levels a b steps invalid forward reverse")


def require_idle(device):
    if ps.u32(device.status, 0x120) & 3 or ps.u32(device.status, 0x124):
        raise RuntimeError("Guard active/faulted; no automatic clear or retry")
    if ps.u32(device.status, 0x48) & 0x1d0 or ps.u32(device.status, 0x50):
        raise RuntimeError("Motor outputs active or core fault latched")


def selected_features(filtered=False, bypass=False, observe=False, filter4=False):
    if sum(bool(item) for item in (filtered, bypass, observe, filter4)) > 1:
        raise RuntimeError("Select exactly one encoder profile; no writes made")
    return (ps.FILTER4_OBSERVE_FEATURES if filter4 else ps.OBSERVE_GUARDED_FEATURES if observe else ps.BYPASS_GUARDED_FEATURES if bypass else
            ps.FILTERED_GUARDED_FEATURES if filtered else ps.GUARDED_FEATURES)


def verify_image(device, filtered=False, bypass=False, observe=False, filter4=False):
    device.verify_image(selected_features(filtered, bypass, observe, filter4))
    expected = ((0x100, ps.GUARD_ID), (0x104, ps.ABI),
                (0x160, ENCODER_ID), (0x164, ps.ABI),
                (0x130, 40000), (0x134, 100000000))
    if any(ps.u32(device.status, address) != value for address, value in expected):
        raise RuntimeError("Guard/encoder identity, scale or clock mismatch; no writes made")
    if filtered or bypass or observe or filter4:
        if any(ps.u32(device.status, address) != value for address, value in
               ((0x228, 4 if filter4 else 1 if bypass or observe else 16), (0x22c, 64), (0x230, 16))):
            raise RuntimeError("Selected encoder trial profile does not match its stable-cycle/trace metadata")
        if ps.u32(device.status, 0x208) & 12 != 12:
            raise RuntimeError("Filtered encoder initial state is not ready; no writes made")
    if observe or filter4:
        if any(ps.u32(device.status, address) != value for address, value in
               ((0x40c, 100000000), (0x410, 64), (0x414, 64), (0x438, 200000),
                (0x448, 4), (0x44c, 128), (0x450, 0x800))):
            raise RuntimeError("Long observation layout/interval mismatch; no writes made")
        if ps.u32(device.status, 0x408) & 15 != 12:
            raise RuntimeError("Long observation not ready or already fault-triggered; no writes made")
    require_idle(device)


def encoder_snapshot(device, sample):
    value = Encoder(*(ps.u32(device.status, address) for address in
                      (0x168, 0x16c, 0x170, 0x174, 0x178, 0x17c, 0x180)))
    if sample.seq != ps.u32(device.status, 0x0c):
        raise RuntimeError("Snapshot changed; stop other snapshot-reading programs")
    if not value.levels & 4:
        raise RuntimeError("Encoder synchronizers are not ready")
    return value


def deltas(first, last):
    return {name: (getattr(last, name) - getattr(first, name)) & 0xffffffff
            for name in ("a", "b", "steps", "invalid", "forward", "reverse")}


def require_stationary(first, last):
    if any(deltas(first, last).values()):
        raise RuntimeError("Encoder activity while disarmed; no electric-start attempt made")


def preflight(device, filtered=False, bypass=False, observe=False, filter4=False):
    verify_image(device, filtered, bypass, observe, filter4)  # Reject unknown images before even CAPTURE writes.
    traced = filtered or bypass or observe or filter4
    rejected_before = ps.u32(device.status, 0x238) if traced else 0
    first_sample = device.check_adc()
    first_encoder = encoder_snapshot(device, first_sample)
    offset, _vibration, low, high, records = ps.baseline(
        device, BASELINE_SAMPLES, INTERVAL)
    require_idle(device)  # A concurrent ESTOP during baseline must prevent late ARM.
    last_sample = records[-1][2]
    last_encoder = encoder_snapshot(device, last_sample)
    require_stationary(first_encoder, last_encoder)
    if traced and ps.u32(device.status, 0x238) != rejected_before:
        raise RuntimeError("Rejected raw encoder activity while disarmed; no start attempt made")
    print("Preflight: features=0x{:X} ADC fresh, outputs disabled, encoder stationary".format(
        selected_features(filtered, bypass, observe, filter4)))
    print("No-drive current baseline={:.1f} mA range=[{},{}]".format(offset, low, high))
    return offset, last_sample, last_encoder


def claim_trial():
    # Application-level one-attempt marker in RAM. This is NOT a PL one-shot latch.
    flags = os.O_CREAT | os.O_EXCL | os.O_WRONLY | getattr(os, "O_NOFOLLOW", 0)
    try:
        fd = os.open(USED_PATH, flags, 0o600)
    except FileExistsError:
        raise RuntimeError("This boot already attempted a guarded trial; inspect before retry")
    try:
        os.write(fd, b"guarded start attempt; do not automatically remove or retry\n")
        os.fsync(fd)
    finally:
        os.close(fd)


def verify_disabled(device):
    deadline = time.monotonic() + .05
    while True:
        if (not ps.u32(device.status, 0x120) & 1 and
                not ps.u32(device.status, 0x48) & 0x1c0 and
                ps.u32(device.gpio, 0x00) == 0 and
                ps.u32(device.gpio, 0x08) == 0):
            return
        if time.monotonic() >= deadline:
            raise RuntimeError("STOP readback failed; disconnect the adapter")
        time.sleep(.001)


def require_feedback(difference):
    if difference["invalid"]:
        raise RuntimeError("Invalid A/B transitions: {}".format(difference["invalid"]))
    if not difference["a"] or not difference["b"] or difference["steps"] < 4:
        raise RuntimeError("No sufficient legal encoder feedback; do not extend or repeat automatically")
    if difference["steps"] != (difference["forward"] + difference["reverse"]) & 0xffffffff:
        raise RuntimeError("Inconsistent encoder counters")


def run_trial(device, args, offset, previous_sample, first_encoder):
    claim_trial()  # Fail before any GPIO/ARM writes if already used this boot.
    last_encoder = first_encoder
    captures = 0
    min_current = max_current = 0.0
    print("WARNING: no independent adjustable current limit; ADC trip depends on sensor wiring")
    print("Single forward start: PS limit=1.5 s, PL deadline=1.6 s, heartbeat=100 ms")
    print("Existing PL controller: 10 kHz PWM, 15% starting duty; not fixed 20% or RPM validation")
    if args.encoder_filtered:
        print("Filtered image: immediate initial duty; later duty updates still use speed windows")
    if args.encoder_bypass:
        print("Bypass comparison: two-stage CDC retained, no multi-cycle deglitch; fault protections remain")
    if args.encoder_observe:
        print("Long observation: passive event/pulse logging, 2 ms post-fault freeze; all stop protections remain")
    if args.encoder_filter4:
        print("Four-sample whole-AB qualification at 100 MHz; persistent diagonal still trips protection")
        print("Long raw/qualified observation retained; no automatic clear/retry or continuous drive")
    try:
        device.neutralize()
        require_idle(device)
        previous_sample = device.check_fresh(previous_sample.sample_count, previous_sample.adc_errors)
        require_stationary(first_encoder, encoder_snapshot(device, previous_sample))
        # Start the PS deadline BEFORE ARM, so configuration time cannot extend it.
        started = time.monotonic()
        config = argparse.Namespace(pl_current_limit_ma=args.pl_current_limit_ma,
                                    guard_watchdog_ms=WATCHDOG_MS, seconds=SECONDS)
        token = ps.prepare_guard(device, config, offset)
        token = ps.refresh_guard(device, token)
        if time.monotonic() - started >= SECONDS:
            raise RuntimeError("Startup exceeded the command deadline")
        ps.w32(device.gpio, 0x00, TARGET_RAW)
        ps.w32(device.gpio, 0x08, 1)
        while True:
            remaining = SECONDS - (time.monotonic() - started)
            if remaining <= 0:
                break
            time.sleep(min(INTERVAL, remaining))
            if time.monotonic() - started >= SECONDS:
                break
            sample = device.check_fresh(previous_sample.sample_count, previous_sample.adc_errors)
            previous_sample = sample
            last_encoder = encoder_snapshot(device, sample)
            captures += 1
            corrected = sample.current_ma - offset
            min_current, max_current = min(min_current, corrected), max(max_current, corrected)
            if sample.fault_code or sample.flags & 0x10 or ps.u32(device.status, 0x50):
                raise RuntimeError("Motor core fault latched; outputs will be disabled")
            if deltas(first_encoder, last_encoder)["invalid"]:
                raise RuntimeError("Invalid A/B transition during electric start")
            if abs(corrected) >= args.pl_current_limit_ma:
                raise RuntimeError("PS observed current at/above the confirmed trip threshold")
            if sample.target_q16 != TARGET_RAW or sample.ctrl != 1:
                raise RuntimeError("Target/direction readback mismatch")
            if time.monotonic() - started >= SECONDS + .1:
                raise RuntimeError("PS execution exceeded the PL command deadline")
            if time.monotonic() - started >= SECONDS:
                break
            token = ps.refresh_guard(device, token)
    finally:
        device.neutralize()
        verify_disabled(device)
        print("STOP verified: guard disabled, target=0, ctrl=FREE, bridge outputs inactive")
        difference = deltas(first_encoder, last_encoder)
        print("snapshots={} A_rises={} B_rises={} steps={} invalid={} current=[{:+.1f},{:+.1f}]mA".format(
            captures, difference["a"], difference["b"], difference["steps"],
            difference["invalid"], min_current, max_current))
    if ps.u32(device.status, 0x124) or ps.u32(device.status, 0x50):
        raise RuntimeError("Fault latched at STOP: guard=0x{:02x} core=0x{:02x}".format(
            ps.u32(device.status, 0x124), ps.u32(device.status, 0x50)))
    require_feedback(difference)
    print("PASS: short electric start produced legal A/B feedback and returned outputs to disabled")
    print("This does NOT validate rated RPM, continuous regulation, or independent current protection.")


def parser_definition():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arm", action="store_true", help="Explicitly request the single short electric start")
    encoder_profile = parser.add_mutually_exclusive_group()
    encoder_profile.add_argument("--encoder-filtered", action="store_true", help="Explicitly select the 0x343 filtered image")
    encoder_profile.add_argument("--encoder-bypass", action="store_true", help="Explicitly select the bounded 0x743 no-deglitch comparison")
    encoder_profile.add_argument("--encoder-observe", action="store_true", help="Explicitly select bounded 0xF43 passive long observation")
    encoder_profile.add_argument("--encoder-filter4", action="store_true", help="Explicitly select bounded 0x1B43 four-sample qualification with long observation")
    parser.add_argument("--motor-vm", type=float)
    parser.add_argument("--motor-unloaded", action="store_true")
    parser.add_argument("--encoder-connected", action="store_true")
    parser.add_argument("--sensor-in-motor-lead", action="store_true")
    parser.add_argument("--accept-no-external-current-limit", action="store_true")
    parser.add_argument("--pl-current-limit-ma", type=int, help="Required confirmed experimental trip, 1..1000 mA")
    return parser


def validate_args(parser, args):
    if args.arm and not (args.motor_vm is not None and math.isfinite(args.motor_vm) and
                         0 < args.motor_vm <= 12 and args.motor_unloaded and
                         args.encoder_connected and args.sensor_in_motor_lead and
                         args.accept_no_external_current_limit and
                         args.pl_current_limit_ma is not None and 0 < args.pl_current_limit_ma <= 1000):
        parser.error("ARM requires VM<=12 V, unloaded motor, connected encoder, current sensor in motor lead, "
                     "explicit acceptance of no external current limit, and a confirmed 1..1000 mA trip")


def main(argv=None):
    parser = parser_definition()
    args = parser.parse_args(argv)
    validate_args(parser, args)  # Reject incomplete confirmation BEFORE opening MMIO.
    if os.geteuid() != 0:
        parser.error("Run as root for /dev/mem access")
    previous_handler = signal.getsignal(signal.SIGTERM)
    def interrupted(_signum, _frame):
        raise KeyboardInterrupt()
    signal.signal(signal.SIGTERM, interrupted)
    try:
        with ps.MotorDevice() as device:
            offset, sample, encoder = preflight(device, args.encoder_filtered, args.encoder_bypass, args.encoder_observe, args.encoder_filter4)
            if args.arm:
                run_trial(device, args, offset, sample, encoder)
            else:
                print("PASS: no-drive preflight only; motor NOT armed, no GPIO/control writes")
        return 0
    except KeyboardInterrupt:
        print("Interrupted; no automatic retry", file=sys.stderr)
        return 130
    except (OSError, RuntimeError) as error:
        print("FAIL: {}".format(error), file=sys.stderr)
        return 1
    finally:
        signal.signal(signal.SIGTERM, previous_handler)


if __name__ == "__main__":
    raise SystemExit(main())
