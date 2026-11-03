#!/usr/bin/env python3
"""Read the safe motor preflight image; never commands the motor driver.

The preflight image hardwires PWMA, AIN1, AIN2 and STBY low. This script
checks its image marker, ADC activity and encoder input counters. It cannot
measure the physical voltage on a pin or prove external wires are correct.
"""

import mmap
import os
import struct
import sys
import time

from check_adc_only import BASE, EXPECTED_ABI, EXPECTED_ID


def u32(regs, offset):
    return struct.unpack_from("<I", regs, offset)[0]


def capture(regs):
    struct.pack_into("<I", regs, 0x08, 1)
    return {
        "flags": u32(regs, 0x10),
        "raw": struct.unpack_from("<i", regs, 0x14)[0],
        "current": struct.unpack_from("<i", regs, 0x18)[0],
        "levels": u32(regs, 0x30) & 3,
        "counts": u32(regs, 0x34),
        "errors": u32(regs, 0x3C),
    }


def main():
    if os.geteuid() != 0:
        print("Run as root.", file=sys.stderr)
        return 1
    try:
        fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
        try:
            with mmap.mmap(fd, mmap.PAGESIZE, flags=mmap.MAP_SHARED,
                           prot=mmap.PROT_READ | mmap.PROT_WRITE,
                           offset=BASE) as regs:
                ident = u32(regs, 0x00)
                abi = u32(regs, 0x04)
                features = u32(regs, 0x54)
                print("ID=0x{:08X} ABI=0x{:08X} features=0x{:08X}".format(
                    ident, abi, features))
                if (ident, abi, features) != (EXPECTED_ID, EXPECTED_ABI, 0xF):
                    print("FAIL: not the output-disabled motor preflight image; "
                          "no writes made.")
                    return 1

                frames_before = u32(regs, 0x4C)
                first = capture(regs)
                print("PWMA/AIN1/AIN2/STBY: fixed LOW by image design; "
                      "physical pin voltage not measured.")
                print("IN5 raw={} current={} mA ADC errors={}".format(
                    first["raw"], first["current"], first["errors"]))
                print("Encoder A={} B={} rising counts A={} B={}".format(
                    first["levels"] & 1, (first["levels"] >> 1) & 1,
                    first["counts"] & 0xFFFF, first["counts"] >> 16))
                print("Waiting 5 s; turn the shaft by hand ONLY after A/B "
                      "voltage compatibility is confirmed.")
                time.sleep(5)
                second = capture(regs)
                frames_after = u32(regs, 0x4C)
                delta_a = ((second["counts"] & 0xFFFF) -
                           (first["counts"] & 0xFFFF)) & 0xFFFF
                delta_b = ((second["counts"] >> 16) -
                           (first["counts"] >> 16)) & 0xFFFF
                print("5 s: ADC frames={} encoder rising edges A={} B={} "
                      "ADC error delta={}".format(
                          (frames_after - frames_before) & 0xFFFFFFFF,
                          delta_a, delta_b,
                          (second["errors"] - first["errors"]) & 0xFFFFFFFF))
                if ((frames_after - frames_before) & 0xFFFFFFFF) == 0:
                    print("FAIL: no fresh ADC frames.")
                    return 1
                if second["errors"] != first["errors"]:
                    print("FAIL: ADC errors increased.")
                    return 1
                if (first["flags"] | second["flags"]) & 0x1C0:
                    print("FAIL: preflight status reports a motor output high.")
                    return 1
                print("PASS: safe preflight image and ADC live; encoder counts "
                      "require a separate A/B wiring test.")
                return 0
        finally:
            os.close(fd)
    except OSError as error:
        print("Cannot access PL registers: {}".format(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
