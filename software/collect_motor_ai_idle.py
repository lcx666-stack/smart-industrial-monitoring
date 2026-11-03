#!/usr/bin/env python3
"""Capture one operator-confirmed, motor-VM-off baseline session.

The program never arms or drives the motor. It refuses stale ADC data, active
motor outputs or latched motor faults before starting waveform DMA. The
resulting condition is metadata, not an automatically assigned fault label.
"""
import argparse
import datetime
import glob
import json
import os
import sys
import uuid

import check_blackbox_event
import motor_blackbox
import motor_ps


SCHEMA = "motor-ai-session-v1"
DEFAULT_ROOT = "/data/motor-ai-sessions"


def preflight():
    with motor_ps.MotorDevice() as device:
        device.verify_image(motor_ps.FILTER4_OBSERVE_FEATURES)
        sample = device.check_adc()
        guard_active = bool(motor_ps.u32(device.status, 0x120) & 1)
        bridge_active = bool(motor_ps.u32(device.status, 0x48) & 0x1C0)
        guard_faults = motor_ps.u32(device.status, 0x124)
        if guard_active or bridge_active or sample.ctrl or sample.target_q16:
            raise RuntimeError("Motor output or command is active; no capture started")
        if guard_faults or sample.fault_code:
            raise RuntimeError("Motor fault is latched; no baseline capture started")
        return {"pl_features": "0x{:08x}".format(motor_ps.FILTER4_OBSERVE_FEATURES),
                "adc_sample_count": sample.sample_count,
                "adc_errors_before": sample.adc_errors,
                "adc_age_cycles": sample.sample_age,
                "current_ma_uncalibrated": sample.current_ma,
                "vibration_raw_codes": list(sample.vibration),
                "guard_status": motor_ps.u32(device.status, 0x120),
                "guard_faults": guard_faults}


def capture_session(output_root, confirmed_vm_off, confirmed_stationary):
    if not confirmed_vm_off or not confirmed_stationary:
        raise ValueError("Explicit VM-off and stationary confirmations are required")
    output_root = os.path.abspath(output_root)
    if output_root == "/mnt/sdboot" or output_root.startswith("/mnt/sdboot/"):
        raise ValueError("Do not write AI event data to the BOOT FAT partition")
    observed = preflight()  # Only CAPTURE requests; no GPIO/guard control writes.
    os.makedirs(output_root, exist_ok=True)
    session_id = uuid.uuid4().hex
    session_dir = os.path.join(output_root, "session-" + session_id)
    os.mkdir(session_dir)  # Exclusive: do not overwrite a previous recording.
    result = motor_blackbox.main([
        "--output-dir", session_dir, "--parser", "native",
        "--seconds", "8", "--test-trigger-after", "3"])
    if result != 0:
        raise RuntimeError("Black-box capture failed; retain output for diagnosis")
    events = glob.glob(os.path.join(session_dir, "event-*.json"))
    if len(events) != 1:
        raise RuntimeError("Expected exactly one complete software event")
    verified = check_blackbox_event.verify_event(events[0], parser="python")
    if not verified["software_trigger"]:
        raise RuntimeError("Saved event was not the scheduled software trigger")
    manifest = {"schema": SCHEMA, "session_id": session_id,
                "condition": "motor_vm_off_stationary",
                "condition_source": "operator_confirmation_before_capture",
                "binary_fault_label": None,
                "motor_vm_off_confirmed": True,
                "stationary_confirmed": True,
                "board_wall_clock_trusted": False,
                "recorded_utc_untrusted": datetime.datetime.now(
                    datetime.timezone.utc).isoformat(),
                "preflight": observed,
                "capture": {"seconds": 8, "software_trigger_after_seconds": 3,
                            "pre_seconds": 2, "post_seconds": 2},
                "event_metadata": os.path.basename(events[0]),
                "event_frames": verified["frames"],
                "event_sha256": verified["sha256"]}
    with open(os.path.join(session_dir, "session.json"), "x", encoding="utf-8") as target:
        json.dump(manifest, target, ensure_ascii=False, indent=2)
    return session_dir, manifest


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--confirm-vm-off", action="store_true",
                        help="Operator confirms motor driver 12 V VM is physically off")
    parser.add_argument("--confirm-stationary", action="store_true",
                        help="Operator confirms motor is not moving")
    parser.add_argument("--output-root", default=DEFAULT_ROOT)
    args = parser.parse_args(argv)
    try:
        path, manifest = capture_session(args.output_root,
                                         args.confirm_vm_off,
                                         args.confirm_stationary)
    except (OSError, RuntimeError, ValueError, KeyError, TypeError) as error:
        print("FAIL: {}".format(error), file=sys.stderr)
        return 1
    print("PASS: verified, operator-annotated idle session at {} sha256={}".format(
        path, manifest["event_sha256"]))
    print("NOTE: binary_fault_label remains null; idle is not normal running")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
