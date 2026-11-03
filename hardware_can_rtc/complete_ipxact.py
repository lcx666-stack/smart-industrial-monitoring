"""Keep the generated PS metadata consistent with the RTC I2C1 RTL wiring."""
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent
SIGNALS = ("i2c1_scl_in", "i2c1_scl_oe", "i2c1_sda_in", "i2c1_sda_oe")
PS = Path("system/ip/system_ARM_Processor_System_0")


def update(path, anchor, insertion):
    file = ROOT / path
    original = file.read_text(encoding="utf-8")
    if original.count(anchor) != 1 or any(name in original for name in ("w_net__i2c1_scl_in",)):
        raise RuntimeError("unexpected IP-XACT source: " + str(path))
    changed = original.replace(anchor, anchor + insertion, 1)
    ET.fromstring(changed)
    file.write_text(changed, encoding="utf-8", newline="\n")


def ports():
    blocks = []
    for name in SIGNALS:
        direction = "in" if name.endswith("_in") else "out"
        blocks.append("""\n            <ipxact:port>
                <ipxact:name>{name}</ipxact:name>
                <ipxact:displayName>{name}</ipxact:displayName>
                <ipxact:wire><ipxact:direction>{direction}</ipxact:direction></ipxact:wire>
            </ipxact:port>""".format(name=name, direction=direction))
    return "".join(blocks)


def connections(instance):
    blocks = []
    for name in SIGNALS:
        blocks.append("""\n        <ipxact:adHocConnection>
            <ipxact:name>w_net__{name}</ipxact:name>
            <ipxact:portReferences>
                <ipxact:internalPortReference componentRef="{instance}" portRef="{name}"/>
                <ipxact:externalPortReference portRef="{name}"/>
            </ipxact:portReferences>
        </ipxact:adHocConnection>""".format(instance=instance, name=name))
    return "".join(blocks)


update(Path("system/system.xml"), "        <ipxact:ports>", ports())
update(PS / "system_ARM_Processor_System_0.xml", "        <ipxact:ports>", ports())
update(Path("system/Design.xml"), "    <ipxact:adHocConnections>", connections("ARM_Processor_System_0"))
update(PS / "Design.xml", "    <ipxact:adHocConnections>",
       connections("ARM_Processor_System_system_ARM_Processor_System_0_Inst"))

port_file = ROOT / PS / ".ports_system_ARM_Processor_System_0.txt"
data = port_file.read_text(encoding="utf-8")
for name in SIGNALS:
    old = name + "; 0"
    if data.count(old) != 1:
        raise RuntimeError("unexpected PS port table: " + old)
    data = data.replace(old, name + "; 1", 1)
port_file.write_text(data, encoding="utf-8", newline="\n")

for name in ("DesignTmp.xml", "GuiFinal.xml"):
    path = ROOT / PS / name
    data = path.read_text(encoding="utf-8")
    if name == "DesignTmp.xml":
        for key in ("I2C1_Dot_Enable", "I2C1_Available"):
            old = 'referenceId="{}">0<'.format(key)
            if data.count(old) != 1:
                raise RuntimeError("unexpected PS temporary design " + key)
            data = data.replace(old, 'referenceId="{}">1<'.format(key), 1)
    else:
        for key in ("I2C1_Dot_Enable", "I2C1_Available"):
            old = 'parameterId="{}" value="0" enable="1"'.format(key)
            if data.count(old) != 1:
                raise RuntimeError("unexpected PS GUI cache " + key)
            data = data.replace(old, 'parameterId="{}" value="1" enable="1"'.format(key), 1)
    ET.fromstring(data)
    path.write_text(data, encoding="utf-8", newline="\n")

print("RTC PS IP-XACT metadata consistent")
