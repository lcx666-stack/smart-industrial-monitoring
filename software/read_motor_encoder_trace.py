#!/usr/bin/env python3
"""Read the frozen ETR1 first-fault waveform. Never ARM, STOP, CLEAR or CAPTURE."""
import argparse
import json
import os
import sys

import motor_ps as ps

FEATURES = 0x343
TRACE_ID = 0x45545231
MASK64 = (1 << 64)-1


def read_trace(device, bypass=False, observe=False, filter4=False):
    if sum(bool(item) for item in (bypass, observe, filter4)) > 1:
        raise RuntimeError("Select one trace profile")
    expected_features = (ps.FILTER4_OBSERVE_FEATURES if filter4 else ps.OBSERVE_GUARDED_FEATURES if observe else
                         ps.BYPASS_GUARDED_FEATURES if bypass else FEATURES)
    device.verify_image(expected_features)
    if (ps.u32(device.status, 0x100), ps.u32(device.status, 0x104),
            ps.u32(device.status, 0x200), ps.u32(device.status, 0x204)) != (
                ps.GUARD_ID, ps.ABI, TRACE_ID, ps.ABI):
        raise RuntimeError("Guard/trace ID or ABI mismatch; no writes made")
    if ps.u32(device.status, 0x208) & 3 != 3:
        raise RuntimeError("First-fault trace has not frozen; this reader never requests a drive")
    count = ps.u32(device.status, 0x20c)
    next_index = ps.u32(device.status, 0x210)
    trigger_index = ps.u32(device.status, 0x214)
    trigger_tick = ps.u32(device.status, 0x218) | ps.u32(device.status, 0x21c) << 32
    first_tick = ps.u32(device.status, 0x220) | ps.u32(device.status, 0x224) << 32
    stable_cycles = ps.u32(device.status, 0x228)
    if (bypass or observe) and stable_cycles != 1:
        raise RuntimeError("Bypass trace must have one-sample qualification")
    if filter4 and stable_cycles != 4:
        raise RuntimeError("Filter4 trace must have four-sample qualification")
    depth = ps.u32(device.status, 0x22c)
    post = ps.u32(device.status, 0x230)
    reason = ps.u32(device.status, 0x234)
    rejected = ps.u32(device.status, 0x238)
    clock = ps.u32(device.status, 0x134)
    if (depth < 4 or depth > 128 or depth & (depth-1) or not 1 <= post <= depth-2 or
            not post+1 <= count <= depth or not 0 <= next_index < depth or
            not 0 <= trigger_index < depth or not 1 <= reason <= 7 or
            not 1 <= stable_cycles <= 65536 or clock != 100000000):
        raise RuntimeError("Malformed trace header or unsupported clock")
    oldest = next_index if count == depth else 0
    trigger_offset = (trigger_index-oldest) & (depth-1)
    if (trigger_offset != count-post-1 or
            (trigger_tick-first_tick) & MASK64 != trigger_offset):
        raise RuntimeError("Trace timestamps/index disagree")
    records = []
    for index in range(count):
        physical = (oldest+index) & (depth-1)
        word = ps.u32(device.status, 0x280+4*physical)
        records.append({
            "tick": (first_tick+index) & MASK64,
            "relative_ns": (index-trigger_offset)*1e9/clock,
            "raw_ab": [word & 1, word >> 1 & 1],
            "qualified_ab": [word >> 2 & 1, word >> 3 & 1],
            "raw_ready": bool(word & 1 << 4),
            "qualified_ready": bool(word & 1 << 5),
            "raw_activity": bool(word & 1 << 6),
            "encoder_step": bool(word & 1 << 7),
            "encoder_invalid": bool(word & 1 << 8),
            "core_fault": bool(word & 1 << 9),
            "guard_fault": bool(word & 1 << 10),
            "drive_permit": bool(word & 1 << 11),
            "pwm": bool(word & 1 << 12),
            "stby": bool(word & 1 << 13),
            "an1": bool(word & 1 << 14),
            "an2": bool(word & 1 << 15),
            "duty_percent": word >> 16 & 0x7f,
            "ctrl": word >> 23 & 3,
        })
    if ps.u32(device.status, 0x208) & 3 != 3 or (
            ps.u32(device.status, 0x218) | ps.u32(device.status, 0x21c) << 32) != trigger_tick:
        raise RuntimeError("Trace changed during read; possible system reset")
    return {"features": expected_features, "trace_id": "ETR1", "clock_hz": clock,
            "filter_stable_cycles": stable_cycles, "rejected_candidates": rejected,
            "trigger_reason": [name for bit, name in enumerate(
                ("qualified encoder invalid", "core fault rising", "guard fault rising")) if reason & 1 << bit],
            "trigger_tick": trigger_tick, "pre_samples": trigger_offset,
            "post_samples": post, "samples": records}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    profile = parser.add_mutually_exclusive_group()
    profile.add_argument("--encoder-bypass", action="store_true", help="Read the 0x743 comparison image, not 0x343")
    profile.add_argument("--encoder-observe", action="store_true", help="Read the short ETR1 trace from 0xF43")
    profile.add_argument("--encoder-filter4", action="store_true", help="Read the short ETR1 trace from 0x1B43")
    args = parser.parse_args(argv)
    if os.geteuid() != 0:
        raise SystemExit("Run as root for read-only MMIO diagnostics")
    try:
        with ps.MotorDevice() as device:
            result = read_trace(device, args.encoder_bypass, args.encoder_observe, args.encoder_filter4)
        print(json.dumps(result, ensure_ascii=True, indent=2))
        return 0
    except (OSError, RuntimeError) as error:
        print("FAIL: {}".format(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
