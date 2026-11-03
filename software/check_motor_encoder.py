#!/usr/bin/env python3
"""Observe guarded-image encoder counters with NO motor enable/GPIO writes."""
import argparse
import math
import os
import sys
import time
from collections import namedtuple

from motor_ps import ABI, GUARD_ID, GUARDED_FEATURES, MotorDevice, u32

ENCODER_ID = 0x454e4331
Encoder = namedtuple("Encoder", "levels a b steps invalid forward reverse")


def require_disarmed(device):
    if u32(device.status, 0x100) != GUARD_ID or u32(device.status, 0x104) != ABI:
        raise RuntimeError("Guard ID/ABI mismatch; no control writes made")
    if u32(device.status, 0x120) & 1 or u32(device.status, 0x48) & 0x1c0:
        raise RuntimeError("Motor is not disabled; remove motor power and inspect the controller")
    faults, core = u32(device.status, 0x124), u32(device.status, 0x50)
    if faults or core:
        raise RuntimeError("Latched fault: guard=0x{:02x} core=0x{:02x}; inspect A/B wiring".format(faults, core))


def encoder_snapshot(device, sample):
    require_disarmed(device)
    if (u32(device.status, 0x160), u32(device.status, 0x164)) != (ENCODER_ID, ABI):
        raise RuntimeError("Encoder diagnostics missing: load the matching guarded candidate")
    result = Encoder(*(u32(device.status, address) for address in
                       (0x168, 0x16c, 0x170, 0x174, 0x178, 0x17c, 0x180)))
    if sample.seq != u32(device.status, 0x0c):
        raise RuntimeError("Snapshot changed; stop other snapshot-reading programs")
    if not result.levels & 4:
        raise RuntimeError("Encoder synchronizers are not ready")
    return result


def deltas(first, last):
    return {name: (getattr(last, name) - getattr(first, name)) & 0xffffffff
            for name in ("a", "b", "steps", "invalid", "forward", "reverse")}


def assess(first, last):
    difference = deltas(first, last)
    if difference["invalid"]:
        raise RuntimeError("Invalid A/B transitions observed: {}".format(difference["invalid"]))
    if not difference["a"] or not difference["b"]:
        raise RuntimeError("Both phases must advance: A rises={} B rises={}; turn shaft by hand and check both wires".format(
            difference["a"], difference["b"]))
    if difference["steps"] < 4:
        raise RuntimeError("Too few quadrature steps; turn shaft further")
    if difference["steps"] != (difference["forward"] + difference["reverse"]) & 0xffffffff:
        raise RuntimeError("Inconsistent encoder counters")
    return difference


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seconds", type=float, default=15)
    parser.add_argument("--interval", type=float, default=.05)
    args = parser.parse_args(argv)
    if not (math.isfinite(args.seconds) and 2 <= args.seconds <= 60 and
            math.isfinite(args.interval) and .02 <= args.interval <= .2):
        parser.error("seconds must be 2..60 and interval .02...2 s")
    if os.geteuid() != 0:
        parser.error("Run as root for /dev/mem access")
    try:
        with MotorDevice() as device:
            device.verify_image(GUARDED_FEATURES)  # Reject old images before CAPTURE writes.
            require_disarmed(device)
            # Check diagnostic ID before check_adc can issue a snapshot request.
            if (u32(device.status, 0x160), u32(device.status, 0x164)) != (ENCODER_ID, ABI):
                raise RuntimeError("Encoder diagnostic ID/ABI mismatch; no writes made")
            sample = device.check_adc()
            first = last = encoder_snapshot(device, sample)
            count, errors = sample.sample_count, sample.adc_errors
            print("features=0x143 encoder=ENC1; drive DISARMED; motor power must be OFF")
            print("Turn output shaft by hand for {} s. This program NEVER arms the motor.".format(args.seconds))
            started = time.monotonic()
            report = 0.0
            while time.monotonic() - started < args.seconds:
                time.sleep(args.interval)
                require_disarmed(device)
                sample = device.check_fresh(count, errors)
                count = sample.sample_count
                last = encoder_snapshot(device, sample)
                elapsed = time.monotonic() - started
                if elapsed >= report:
                    diff = deltas(first, last)
                    print("t={:.1f}s A={} B={} A_rises={} B_rises={} x4_steps={} invalid={} F={} R={}".format(
                        elapsed, last.levels & 1, (last.levels >> 1) & 1,
                        diff["a"], diff["b"], diff["steps"], diff["invalid"], diff["forward"], diff["reverse"]))
                    report = elapsed + 1.0
            require_disarmed(device)
            difference = assess(first, last)
            print("PASS: both A/B counters advanced, x4_steps={}, invalid=0, drive remained disarmed.".format(difference["steps"]))
            print("Physical voltage, pulses/revolution and RPM accuracy are NOT measured by this test.")
        return 0
    except KeyboardInterrupt:
        print("Interrupted; this test made no motor-enable or GPIO writes.", file=sys.stderr)
        return 130
    except (OSError, RuntimeError) as error:
        print("FAIL: {}".format(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
