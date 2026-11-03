#!/usr/bin/env python3
"""PS-side current/vibration telemetry during one guarded open-loop motor pulse.

Use only when the ACS712 current path is in series with the AO1 motor lead
and its OUT pin goes to AD7606 IN5. Encoder A/B are still grounded, so speed
is not measured. The existing PL image has NO motor-current cutoff; PS polling
can miss short peaks and is not a protection mechanism. The image limits output
to 20% PWM for 0.5 s, once per PL boot.
"""

import argparse
import csv
import mmap
import os
import statistics
import struct
import sys
import time

STATUS_BASE = 0x80000000
GPIO_BASE = 0x80001000
EXPECTED_ID = 0x4D535431
EXPECTED_ABI = 0x00010000
EXPECTED_FEATURES = 0x00000033
ARM_MAGIC = 0x53414645


def read32(page, offset):
    return struct.unpack_from("<I", page, offset)[0]


def read_i32(page, offset):
    return struct.unpack_from("<i", page, offset)[0]


def write32(page, offset, value):
    struct.pack_into("<I", page, offset, value)


def snapshot(status):
    previous = read32(status, 0x0C)
    for _ in range(3):
        write32(status, 0x08, 1)
        seq_before = read32(status, 0x0C)
        flags = read32(status, 0x10)
        current = read_i32(status, 0x18)
        vibration = tuple(read_i32(status, offset)
                          for offset in (0x1C, 0x20, 0x24))
        sample_count = read32(status, 0x28)
        errors = read32(status, 0x3C)
        seq_after = read32(status, 0x0C)
        if seq_before != previous and seq_before == seq_after and (flags & 1):
            return current, vibration, sample_count, errors, flags
        previous = seq_after
    raise RuntimeError("No coherent snapshot; stop other snapshot readers")


def check_sample(sample, previous_count, previous_errors):
    _current, _vibration, count, errors, flags = sample
    if not (flags & 2) or (flags & 4):
        raise RuntimeError("ADC has no valid frame or is reporting an error")
    if previous_count is not None and count == previous_count:
        raise RuntimeError("ADC samples stopped; refusing stale data")
    if previous_errors is not None and errors != previous_errors:
        raise RuntimeError("ADC error count increased")


def baseline_summary(samples):
    if not samples:
        raise ValueError("At least one no-drive sample is required")
    current = [sample[0] for sample in samples]
    vibration = tuple(statistics.median(sample[1][channel]
                                        for sample in samples)
                      for channel in range(3))
    return statistics.median(current), min(current), max(current), vibration


def write_csv(path, records, zero_current):
    """Export only PS snapshots; this is not the complete 50 kSPS waveform."""
    with open(path, "x", newline="") as output:
        writer = csv.writer(output)
        writer.writerow(("phase", "phase_time_s", "current_raw_ma",
                         "current_corrected_ma", "vibration1_code",
                         "vibration2_code", "vibration3_code",
                         "adc_sample_count", "adc_error_count", "trial_status"))
        for phase, seconds, sample, trial in records:
            current, vibration, count, errors, _flags = sample
            writer.writerow((phase, "{:.6f}".format(seconds), current,
                             "{:.1f}".format(current - zero_current),
                             vibration[0], vibration[1], vibration[2],
                             count, errors, "0x{:08X}".format(trial)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arm", action="store_true", help="run one 0.5 s pulse")
    parser.add_argument("--motor-vm", type=float, help="actual motor VM setting in volts")
    parser.add_argument("--direction", choices=("forward", "reverse"),
                        default="forward")
    parser.add_argument("--encoder-grounded", action="store_true")
    parser.add_argument("--sensor-in-motor-lead", action="store_true")
    parser.add_argument("--accept-no-hardware-current-cutoff", action="store_true")
    parser.add_argument("--motor-unloaded", action="store_true")
    parser.add_argument("--baseline-samples", type=int, default=100)
    parser.add_argument("--sample-interval", type=float, default=0.002)
    parser.add_argument("--csv", help="save PS snapshots to a CSV file")
    args = parser.parse_args()
    if os.geteuid() != 0:
        parser.error("run as root")
    if args.baseline_samples < 20 or args.sample_interval < 0.001:
        parser.error("Use at least 20 baseline samples and interval >= 0.001 s")
    if args.csv and os.path.exists(args.csv):
        parser.error("CSV file already exists; choose a new name to preserve it")
    if args.arm and not (args.motor_vm is not None and 0 < args.motor_vm <= 12.0
                         and args.encoder_grounded and args.sensor_in_motor_lead
                         and args.accept_no_hardware_current_cutoff
                         and args.motor_unloaded):
        parser.error("arm requires actual VM <= 12 V, J12-15/16 grounded, "
                     "ACS712 in series with AO1, motor free to spin, and "
                     "acknowledgement that PL has NO motor-current cutoff")

    fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
    try:
        with mmap.mmap(fd, mmap.PAGESIZE, flags=mmap.MAP_SHARED,
                       prot=mmap.PROT_READ | mmap.PROT_WRITE,
                       offset=STATUS_BASE) as status:
            ident = read32(status, 0x00)
            abi = read32(status, 0x04)
            features = read32(status, 0x54)
            print("ID=0x{:08X} ABI=0x{:08X} features=0x{:08X}".format(
                ident, abi, features))
            if (ident, abi, features) != (EXPECTED_ID, EXPECTED_ABI,
                                         EXPECTED_FEATURES):
                print("FAIL: motor trial PL image is not loaded; no control writes")
                return 1

            before = read32(status, 0x4C)
            old_errors = read32(status, 0x3C)
            time.sleep(0.2)
            frames = (read32(status, 0x4C) - before) & 0xFFFFFFFF
            live = read32(status, 0x48)
            trial = read32(status, 0x58)
            first = snapshot(status)
            current, _vibration, sample_count, errors, _flags = first
            print("frames/0.2s={} live=0x{:08X} trial=0x{:08X} "
                  "IN5_raw_current={}mA ADC_errors={}".format(
                      frames, live, trial, current, errors))
            if frames == 0 or not (live & 2) or (live & 4) or errors != old_errors:
                print("FAIL: ADC frames are missing or errors are increasing")
                return 1
            if (trial & 1) or (live & 0x40):
                print("FAIL: motor drive is active; cannot take no-drive baseline")
                return 1
            if args.arm and (trial != 0 or (live & 0x10)):
                print("FAIL: trial already used or faulted; power-cycle to retry")
                return 1
            baseline = []
            records = []
            previous_count = sample_count
            baseline_start = time.monotonic()
            for _ in range(args.baseline_samples):
                time.sleep(args.sample_interval)
                sample = snapshot(status)
                check_sample(sample, previous_count, errors)
                previous_count = sample[2]
                baseline.append(sample)
                records.append(("baseline", time.monotonic() - baseline_start,
                                sample, trial))
            zero_current, idle_min, idle_max, baseline_vib = baseline_summary(baseline)
            print("No-drive IN5 baseline: median={:.1f}mA range=[{},{}]mA; "
                  "vibration codes={}".format(
                      zero_current, idle_min, idle_max, baseline_vib))
            if abs(zero_current) >= 1000:
                print("FAIL: no-drive IN5 reading is >1A from nominal zero; "
                      "check sensor OUT/GND and ADC input before arming")
                return 1
            if not args.arm:
                if args.csv:
                    write_csv(args.csv, records, zero_current)
                    print("Saved {} PS snapshots to {}".format(
                        len(records), args.csv))
                print("PASS: image and ADC ready; PWM/direction remain low. "
                      "No motor speed or hardware-current-cutoff test performed.")
                return 0

            print("WARNING: VM={}V is user-reported, not measured. IN5 current "
                  "is PS telemetry only; no hardware current cutoff or encoder "
                  "speed. Short unloaded pulse only.".format(args.motor_vm))

            with mmap.mmap(fd, mmap.PAGESIZE, flags=mmap.MAP_SHARED,
                           prot=mmap.PROT_READ | mmap.PROT_WRITE,
                           offset=GPIO_BASE) as gpio:
                try:
                    # Write neutral values before changing GPIO direction.
                    write32(gpio, 0x00, 0)
                    write32(gpio, 0x08, 0)
                    write32(gpio, 0x04, 0)  # target channel: output
                    write32(gpio, 0x0C, 0)  # ctrl channel: output
                    write32(gpio, 0x00, 1 << 16)  # 1 rev/s request
                    write32(gpio, 0x08, 1 if args.direction == "forward" else 2)
                    time.sleep(0.15)             # core waits for stopped encoder
                    write32(status, 0x58, ARM_MAGIC)
                    armed = read32(status, 0x58)
                    if not (armed & 3) == 3:
                        print("FAIL: hardware guard refused arm: 0x{:08X}".format(armed))
                        return 1
                    print("ARMED: {} one 0.5s pulse, fixed 20% duty at 1kHz".format(
                        args.direction))
                    peaks = [0, 0, 0]
                    captures = 0
                    latest_errors = errors
                    current_min = 0.0
                    current_max = 0.0
                    start = time.monotonic()
                    deadline = time.monotonic() + 0.75
                    while time.monotonic() < deadline:
                        sample = snapshot(status)
                        check_sample(sample, previous_count, errors)
                        raw_current, vibration, previous_count, latest_errors, _flags = sample
                        captures += 1
                        records.append(("pulse", time.monotonic() - start,
                                        sample, read32(status, 0x58)))
                        corrected = raw_current - zero_current
                        current_min = min(current_min, corrected)
                        current_max = max(current_max, corrected)
                        for index in range(3):
                            peaks[index] = max(peaks[index],
                                               abs(vibration[index] - baseline_vib[index]))
                        trial = read32(status, 0x58)
                        if not (trial & 1):
                            break
                        time.sleep(args.sample_interval)
                    elapsed = time.monotonic() - start
                    final = read32(status, 0x58)
                    print("trial final=0x{:08X} elapsed={:.3f}s "
                          "PS-observed current range=[{:+.1f},{:+.1f}]mA "
                          "peak |current|={:.1f}mA vibration peak |delta| "
                          "codes={} captures={} "
                          "ADC_errors={}".format(
                              final, elapsed, current_min, current_max,
                              max(abs(current_min), abs(current_max)),
                              peaks, captures, latest_errors))
                    failure = None
                    if latest_errors != errors or (final & 0x1) or not (final & 0x2):
                        failure = "ADC error or hardware pulse did not finish"
                    elif final & 0x1C:
                        failure = ("hardware interlock tripped; PL current "
                                   "cutoff is disabled in this image")
                    elif (final & 0x20) and elapsed < 0.45:
                        failure = "pulse ended early before normal 0.5s limit"
                finally:
                    write32(gpio, 0x08, 0)
                    write32(gpio, 0x00, 0)
                    write32(status, 0x58, 0)
            if args.csv:
                write_csv(args.csv, records, zero_current)
                print("Saved {} PS snapshots to {}".format(len(records), args.csv))
            if failure:
                print("FAIL: {}".format(failure))
                return 1
            print("PASS: pulse command completed; visually confirm motor "
                  "rotation. Current values are PS snapshots, not a "
                  "guaranteed peak or overcurrent protection; speed is untested.")
            return 0
    finally:
        os.close(fd)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError) as error:
        print("FAIL: {}".format(error), file=sys.stderr)
        sys.exit(1)
