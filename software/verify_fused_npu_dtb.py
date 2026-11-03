#!/usr/bin/env python3
"""Fail closed on the offline soft-NPU DTB contract before SD staging."""

import argparse
import hashlib
from pathlib import Path

from verify_motor_wave_dtb import cells, parse_dtb, string_prop


NPU_ADDRESS = 0x1F0000000
NPU_SIZE = 0x10000


def verify(nodes):
    matches = [(path, props) for path, props in nodes.items()
               if b"anlogic,soft_npu" in props.get("compatible", b"").split(b"\0")
               and string_prop(props, "status", "okay") == "okay"]
    if len(matches) != 1:
        raise ValueError(f"expected exactly one enabled soft-NPU node, found {len(matches)}")
    path, props = matches[0]
    if not path.endswith("/soft_npu@1f0000000"):
        raise ValueError(f"unexpected soft-NPU node path: {path}")
    parent = path.rsplit("/", 1)[0] or "/"
    if cells(nodes[parent].get("#address-cells", b"")) != (2,) or \
       cells(nodes[parent].get("#size-cells", b"")) != (2,):
        raise ValueError("soft-NPU parent must use two address and two size cells")
    if cells(props.get("reg", b"")) != (1, 0xF0000000, 0, NPU_SIZE):
        raise ValueError("soft-NPU register window mismatch")
    if cells(props.get("interrupts", b"")) != (0, 97, 4):
        raise ValueError("soft-NPU interrupt must be GIC SPI 97 level-high")
    interrupt_parent = props.get("interrupt-parent", nodes[parent].get("interrupt-parent"))
    if interrupt_parent is None or len(cells(interrupt_parent)) != 1:
        raise ValueError("soft-NPU interrupt parent is not explicit or inherited")
    controller_phandle = cells(interrupt_parent)[0]
    controllers = [controller for controller in nodes.values()
                   if "interrupt-controller" in controller
                   and cells(controller.get("phandle", b"")) == (controller_phandle,)
                   and cells(controller.get("#interrupt-cells", b"")) == (3,)]
    if len(controllers) != 1:
        raise ValueError("soft-NPU interrupt parent is not a unique three-cell controller")

    for other_path, other in nodes.items():
        if other_path == path or other_path.rsplit("/", 1)[0] != parent or \
           string_prop(other, "status", "okay") == "disabled":
            continue
        reg = other.get("reg", b"")
        if len(reg) % 16:
            continue
        entries = cells(reg)
        for index in range(0, len(entries), 4):
            address = (entries[index] << 32) | entries[index + 1]
            size = (entries[index + 2] << 32) | entries[index + 3]
            if size and address < NPU_ADDRESS + NPU_SIZE and address + size > NPU_ADDRESS:
                raise ValueError(f"enabled MMIO overlap with {other_path}")
    return path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dtb", type=Path)
    args = parser.parse_args()
    data = args.dtb.read_bytes()
    path = verify(parse_dtb(data))
    print(f"PASS: {path}, reg=0x{NPU_ADDRESS:x}/0x{NPU_SIZE:x}, GIC SPI 97 level-high")
    print(f"SHA-256: {hashlib.sha256(data).hexdigest()}")


if __name__ == "__main__":
    try:
        main()
    except (KeyError, OSError, UnicodeDecodeError, ValueError) as error:
        raise SystemExit(f"FAIL: {error}") from error
