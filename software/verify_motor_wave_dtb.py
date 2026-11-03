#!/usr/bin/env python3
"""Check an offline motor-wave DTB without needing third-party Python packages."""

import argparse
import hashlib
import struct
from pathlib import Path


FDT_MAGIC = 0xD00DFEED
FDT_BEGIN_NODE = 1
FDT_END_NODE = 2
FDT_PROP = 3
FDT_NOP = 4
FDT_END = 9
OLD_NODE_NAMES = {
    "axi_dma0@80000000",
    "spi@80000000",
    "canfd@80000000",
    "axi_dma_eth@80000000",
}


def read_u32(data, offset):
    if offset + 4 > len(data):
        raise ValueError("truncated device tree")
    return struct.unpack_from(">I", data, offset)[0]


def read_cstring(data, offset, limit):
    end = data.find(b"\0", offset, limit)
    if end < 0:
        raise ValueError("unterminated device-tree string")
    return data[offset:end].decode("ascii"), end + 1


def align4(value):
    return (value + 3) & ~3


def parse_dtb(data):
    if len(data) < 40 or read_u32(data, 0) != FDT_MAGIC:
        raise ValueError("not a valid flattened device tree")
    total_size = read_u32(data, 4)
    struct_offset = read_u32(data, 8)
    strings_offset = read_u32(data, 12)
    strings_size = read_u32(data, 32)
    struct_size = read_u32(data, 36)
    if total_size > len(data) or struct_offset + struct_size > total_size:
        raise ValueError("invalid device-tree structure bounds")
    if strings_offset + strings_size > total_size:
        raise ValueError("invalid device-tree strings bounds")

    struct_end = struct_offset + struct_size
    strings_end = strings_offset + strings_size
    offset = struct_offset
    stack = []
    nodes = {}
    while offset < struct_end:
        token = read_u32(data, offset)
        offset += 4
        if token == FDT_BEGIN_NODE:
            name, offset = read_cstring(data, offset, struct_end)
            offset = align4(offset)
            path = "/" if not stack else stack[-1].rstrip("/") + "/" + name
            if path in nodes:
                raise ValueError(f"duplicate node: {path}")
            nodes[path] = {}
            stack.append(path)
        elif token == FDT_END_NODE:
            if not stack:
                raise ValueError("unbalanced device-tree nodes")
            stack.pop()
        elif token == FDT_PROP:
            if not stack:
                raise ValueError("property outside a node")
            length = read_u32(data, offset)
            name_offset = read_u32(data, offset + 4)
            offset += 8
            if offset + length > struct_end or name_offset >= strings_size:
                raise ValueError("invalid device-tree property bounds")
            name, _ = read_cstring(data, strings_offset + name_offset, strings_end)
            nodes[stack[-1]][name] = data[offset:offset + length]
            offset = align4(offset + length)
        elif token == FDT_NOP:
            continue
        elif token == FDT_END:
            if stack:
                raise ValueError("unbalanced device-tree nodes")
            return nodes
        else:
            raise ValueError(f"unknown device-tree token: {token}")
    raise ValueError("missing device-tree end token")


def string_prop(properties, name, default=""):
    raw = properties.get(name)
    return default if raw is None else raw.split(b"\0", 1)[0].decode("ascii")


def cells(raw):
    if len(raw) % 4:
        raise ValueError("property length is not a whole number of cells")
    return struct.unpack(f">{len(raw) // 4}I", raw)


def verify(nodes):
    matches = [path for path in nodes if path.endswith("/motor-wave-dma@80000000")]
    if len(matches) != 1:
        raise ValueError(f"expected one motor-wave-dma node, found {len(matches)}")
    target = matches[0]
    parent = target.rsplit("/", 1)[0] or "/"
    parent_props = nodes[parent]
    if cells(parent_props["#address-cells"]) != (2,):
        raise ValueError(f"{parent} does not use two address cells")
    if cells(parent_props["#size-cells"]) != (2,):
        raise ValueError(f"{parent} does not use two size cells")

    props = nodes[target]
    compatible = props.get("compatible", b"").split(b"\0")
    if b"qrs,motor-wave-dma" not in compatible:
        raise ValueError("motor-wave-dma compatible does not match the driver")
    if string_prop(props, "status", "okay") != "okay":
        raise ValueError("motor-wave-dma is not enabled")
    if cells(props.get("reg", b"")) != (0, 0x80000000, 0, 0x1000):
        raise ValueError("motor-wave-dma reg does not match 0x80000000/4 KiB")

    found_old = []
    for path, other_props in nodes.items():
        if path.rsplit("/", 1)[-1] in OLD_NODE_NAMES:
            status = string_prop(other_props, "status", "okay")
            found_old.append((path, status))
            if status != "disabled":
                raise ValueError(f"old same-address node is enabled: {path}")

        # A sibling shares the same bus address space. Reject any enabled MMIO
        # window overlapping the new node, including nodes not in OLD_NODE_NAMES.
        if path == target or path.rsplit("/", 1)[0] != parent:
            continue
        if string_prop(other_props, "status", "okay") == "disabled":
            continue
        reg = other_props.get("reg", b"")
        if len(reg) % 16:
            continue
        entries = cells(reg)
        for index in range(0, len(entries), 4):
            address = (entries[index] << 32) | entries[index + 1]
            size = (entries[index + 2] << 32) | entries[index + 3]
            if size and address < 0x80001000 and address + size > 0x80000000:
                raise ValueError(f"enabled MMIO overlap: {path}")

    return target, found_old


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dtb", type=Path)
    parser.add_argument("--inspect-only", action="store_true",
                        help="show the model and same-address nodes without requiring the new node")
    args = parser.parse_args()
    data = args.dtb.read_bytes()
    nodes = parse_dtb(data)
    print(f"DTB: {args.dtb}")
    print(f"Model: {string_prop(nodes['/'], 'model', '(not specified)')}")
    print(f"SHA-256: {hashlib.sha256(data).hexdigest()}")
    if args.inspect_only:
        for path, props in nodes.items():
            if path.rsplit("/", 1)[-1] in OLD_NODE_NAMES or path.endswith("/motor-wave-dma@80000000"):
                print(f"{path}: status={string_prop(props, 'status', 'okay')}")
        return
    target, found_old = verify(nodes)
    print(f"Motor node: {target}, enabled, 0x80000000/4 KiB")
    print(f"Old same-address nodes disabled: {len(found_old)}")
    print("PASS: offline DTB structure and same-bus resource checks")


if __name__ == "__main__":
    try:
        main()
    except (KeyError, OSError, UnicodeDecodeError, ValueError) as error:
        raise SystemExit(f"FAIL: {error}") from error
