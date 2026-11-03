#!/usr/bin/env python3
"""ADC-only board check after the matching PL image is loaded.

Requires root and Linux /dev/mem. Writes only the status block's snapshot
command at 0x80000008; does not touch the motor-control GPIO.
"""

import mmap
import os
import struct
import sys
import time

BASE = 0x80000000
EXPECTED_ID = 0x4D535431  # MST1
EXPECTED_ABI = 0x00010000
FEATURE_AD7606_BYTE = 0x00000001
FEATURE_CURRENT_IN5 = 0x00000002
FEATURE_CURRENT_RAW = 0x00000004  # ADC-only snapshot speed (0x14) holds signed raw ADC code.


def read_u32(regs, offset):
    return struct.unpack_from("<I", regs, offset)[0]


def read_i32(regs, offset):
    return struct.unpack_from("<i", regs, offset)[0]


def main(require_current_in5=False, require_raw_in5=False):
    if os.geteuid() != 0:
        print("Run as root.", file=sys.stderr)
        return 1

    try:
        fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
        try:
            with mmap.mmap(
                fd,
                mmap.PAGESIZE,
                flags=mmap.MAP_SHARED,
                prot=mmap.PROT_READ | mmap.PROT_WRITE,
                offset=BASE,
            ) as regs:
                device_id = read_u32(regs, 0x00)
                abi = read_u32(regs, 0x04)
                print(f"ID=0x{device_id:08X} ABI=0x{abi:08X}")
                if (device_id, abi) != (EXPECTED_ID, EXPECTED_ABI):
                    print("FAIL: wrong PL image or AXI map; no writes made.")
                    return 1

                features = read_u32(regs, 0x54)
                print(f"features=0x{features:08X}")
                if not (features & FEATURE_AD7606_BYTE):
                    print("FAIL: PL does not identify as AD7606 8-bit byte mode; "
                          "do not test rewired ADC with this image.")
                    return 1
                current_input = "IN5" if features & FEATURE_CURRENT_IN5 else "IN1"
                print(f"current input={current_input}")
                if require_current_in5 and current_input != "IN5":
                    print("FAIL: PL is not the IN5 current diagnostic image; "
                          "no writes made.")
                    return 1
                if require_raw_in5 and (features & 0x7) != 0x7:
                    print("FAIL: PL is not the raw-IN5 diagnostic image; "
                          "no writes made.")
                    return 1

                before = read_u32(regs, 0x4C)
                time.sleep(0.2)
                after = read_u32(regs, 0x4C)
                delta = (after - before) & 0xFFFFFFFF
                live_flags = read_u32(regs, 0x48)
                print(f"valid frames in 0.2 s: {delta}")
                print(f"live flags=0x{live_flags:08X} "
                      f"sample_seen={(live_flags >> 1) & 1} "
                      f"adc_error={(live_flags >> 2) & 1}")

                # Capture one coherent set; the command does not drive a motor.
                struct.pack_into("<I", regs, 0x08, 1)
                seq_before = read_u32(regs, 0x0C)
                snap_flags = read_u32(regs, 0x10)
                raw_code = read_i32(regs, 0x14) if features & FEATURE_CURRENT_RAW else None
                current = read_i32(regs, 0x18)
                vib1 = read_i32(regs, 0x1C)
                vib2 = read_i32(regs, 0x20)
                vib3 = read_i32(regs, 0x24)
                snap_count = read_u32(regs, 0x28)
                error_count = read_u32(regs, 0x3C)
                seq_after = read_u32(regs, 0x0C)
                print(f"snapshot sequence={seq_after} flags=0x{snap_flags:08X}")
                print(f"current={current} mA, vibration raw codes="
                      f"[{vib1}, {vib2}, {vib3}]")
                if raw_code is not None:
                    print(f"{current_input} ADC raw code={raw_code} "
                          f"(0x{raw_code & 0xFFFF:04X}); "
                          "0 V at ADC input should give a code near 0")
                print(f"snapshot sample_count={snap_count}, "
                      f"adc_error_count={error_count}")

                if seq_before != seq_after or not (snap_flags & 1):
                    print("FAIL: snapshot was not coherent.")
                    return 1
                if delta == 0 or not (live_flags & 2):
                    print("FAIL: no valid ADC frames. Check loaded image, "
                          "BUSY/FDA, control lines and J8 configuration.")
                    return 1
                if live_flags & 4:
                    print("FAIL: ADC is currently reporting a frame error.")
                    return 1
                print("PASS: PS reads fresh ADC frames through PL.")
                return 0
        finally:
            os.close(fd)
    except OSError as error:
        print(f"Cannot access PL registers: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    if sys.argv[1:] not in ([], ["--require-current-in5"], ["--require-raw-in5"]):
        print("Usage: check_adc_only.py [--require-current-in5|--require-raw-in5]",
              file=sys.stderr)
        raise SystemExit(2)
    raise SystemExit(main(require_current_in5=sys.argv[1:] == ["--require-current-in5"],
                          require_raw_in5=sys.argv[1:] == ["--require-raw-in5"]))
