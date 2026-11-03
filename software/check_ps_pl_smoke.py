#!/usr/bin/env python3
"""Read-only PS-to-PL smoke check on the DR1 Linux board.

Uses only Python 3's standard library and /dev/mem; does not write registers.
Run only after booting the matching smoke BOOT.bin and system.dtb.
"""

import mmap
import os
import struct
import sys

BASE = 0x80000000
EXPECTED_ID = 0x4D535431
EXPECTED_ABI = 0x00010000


def main() -> int:
    if os.geteuid() != 0:
        print("Run as root.", file=sys.stderr)
        return 1
    try:
        fd = os.open("/dev/mem", os.O_RDONLY | os.O_SYNC)
        try:
            with mmap.mmap(
                fd,
                mmap.PAGESIZE,
                flags=mmap.MAP_SHARED,
                prot=mmap.PROT_READ,
                offset=BASE,
            ) as registers:
                device_id = struct.unpack_from("<I", registers, 0x00)[0]
                abi = struct.unpack_from("<I", registers, 0x04)[0]
        finally:
            os.close(fd)
    except OSError as error:
        print(f"Cannot read PL registers: {error}", file=sys.stderr)
        return 1

    print(f"ID  = 0x{device_id:08X} (expected 0x{EXPECTED_ID:08X})")
    print(f"ABI = 0x{abi:08X} (expected 0x{EXPECTED_ABI:08X})")
    if (device_id, abi) != (EXPECTED_ID, EXPECTED_ABI):
        print("FAIL: unexpected PL image or AXI address map.", file=sys.stderr)
        return 1
    print("PASS: PS can read the PL status-register block.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
