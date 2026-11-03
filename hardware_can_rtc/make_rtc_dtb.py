"""Add the PT7C4337 (DS1337 compatible) to a copy of the live board DTB."""
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "board_system_before_rtc.dtb"
TARGET = ROOT / "system_rtc_candidate.dtb"
BEGIN, END_NODE, PROP, NOP, END = 1, 2, 3, 4, 9


def u32(data, offset):
    return struct.unpack_from(">I", data, offset)[0]


def put32(value):
    return struct.pack(">I", value)


def pad4(data):
    return data + b"\0" * (-len(data) % 4)


def tree_nodes(structure, strings):
    pos, stack = 0, []
    while pos < len(structure):
        start = pos
        tag = u32(structure, pos)
        pos += 4
        if tag == BEGIN:
            end = structure.index(b"\0", pos)
            name = structure[pos:end].decode("ascii")
            stack.append(name)
            pos = (end + 4) & ~3
            yield "/".join(stack), "begin", start, None, None
        elif tag == PROP:
            length, nameoff = struct.unpack_from(">II", structure, pos)
            pos += 8
            end = strings.index(b"\0", nameoff)
            name = strings[nameoff:end].decode("ascii")
            value = structure[pos:pos + length]
            pos += (length + 3) & ~3
            yield "/".join(stack), "property", start, name, value
        elif tag == END_NODE:
            yield "/".join(stack), "end", start, None, None
            stack.pop()
        elif tag == NOP:
            continue
        elif tag == END:
            if stack:
                raise ValueError("unclosed nodes")
            return
        else:
            raise ValueError(f"invalid FDT tag {tag} at {start}")
    raise ValueError("FDT_END missing")


blob = SOURCE.read_bytes()
if TARGET.exists():
    raise SystemExit("refusing to overwrite RTC DTB candidate")
header = list(struct.unpack_from(">10I", blob))
if header[0] != 0xD00DFEED or header[1] != len(blob):
    raise ValueError("invalid DTB header")
off_struct, off_strings, size_strings, size_struct = header[2], header[3], header[8], header[9]
structure = blob[off_struct:off_struct + size_struct]
strings = bytearray(blob[off_strings:off_strings + size_strings])
nodes = list(tree_nodes(structure, strings))
matches = [x for x in nodes if x[0].endswith("/i2c1@f8415000") and x[1] == "end"]
if len(matches) != 1 or any(x[0] == "/soc/i2c1@f8415000/rtc@68" for x in nodes):
    raise ValueError("missing I2C1 node or RTC already exists on I2C1")
parent = matches[0][0]
properties = {x[3]: x[4] for x in nodes if x[0] == parent and x[1] == "property"}
if u32(properties["#address-cells"], 0) != 1 or u32(properties["#size-cells"], 0) != 0:
    raise ValueError("unexpected I2C1 address format")
if properties.get("status", b"okay\0").rstrip(b"\0") != b"okay":
    raise ValueError("I2C1 is disabled in the running DTB")


def name_offset(name):
    marker = name.encode() + b"\0"
    where = strings.find(marker)
    if where < 0:
        where = len(strings)
        strings.extend(marker)
    return where


def prop(name, value):
    return put32(PROP) + put32(len(value)) + put32(name_offset(name)) + pad4(value)


new_node = (put32(BEGIN) + pad4(b"rtc@68\0")
            + prop("compatible", b"dallas,ds1337\0")
            + prop("reg", put32(0x68))
            + prop("status", b"okay\0")
            + put32(END_NODE))
insert = matches[0][2]
new_structure = structure[:insert] + new_node + structure[insert:]
new_strings = bytes(strings)
new_blob = (blob[:off_struct] + new_structure
            + blob[off_struct + size_struct:off_strings]
            + new_strings + blob[off_strings + size_strings:])
header[1] = len(new_blob)
header[3] = off_strings + len(new_node)
header[8] = len(new_strings)
header[9] = len(new_structure)
new_blob = struct.pack(">10I", *header) + new_blob[40:]
check = list(tree_nodes(new_structure, new_strings))
rtc = [x for x in check if x[0] == parent + "/rtc@68"]
assert {x[3] for x in rtc if x[1] == "property"} == {"compatible", "reg", "status"}
assert len(check) == len(nodes) + 5
TARGET.write_bytes(new_blob)
print(f"{TARGET.name}: {len(blob)} -> {len(new_blob)} bytes; {parent}/rtc@68")
