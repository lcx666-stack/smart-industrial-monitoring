#!/usr/bin/env python3
"""Read-only preflight for the motor + CS500 + PL NPU Design Integrator design.

This does not prove routing, timing, Linux driver binding, or inference.
"""

import argparse
import json
import xml.etree.ElementTree as ET


NPU_BASE = 0x1F0000000
MOTOR_ERAM_BASE = 0x80000000
MOTOR_GPIO_BASE = 0x80001000


def local(tag):
    return tag.rsplit("}", 1)[-1]


def child_text(element, name):
    return next((part.text for part in element if local(part.tag) == name), None)


def inspect(design_xml, address_xml):
    design = ET.parse(design_xml).getroot()
    address = ET.parse(address_xml).getroot()
    instances = {part.text for part in design.iter() if local(part.tag) == "instanceName"}
    settings = {}
    for part in design.iter():
        if local(part.tag) == "configurableElementValue":
            settings[part.get("referenceId")] = part.text

    routes = set()
    for source in address.iter():
        if local(source.tag) != "addressSource":
            continue
        source_name = child_text(source, "displayName")
        source_port = child_text(source, "interfaceName")
        for dest in source.iter():
            if local(dest.tag) != "addressDest":
                continue
            base_text = child_text(dest, "baseAddress")
            routes.add((source_name, source_port, child_text(dest, "displayName"),
                        child_text(dest, "interfaceName"),
                        int(base_text, 0) if base_text is not None else None))

    nets = []
    for net in design.iter():
        if local(net.tag) == "adHocConnection":
            nets.append({(port.get("componentRef"), port.get("portRef"))
                         for port in net.iter()
                         if local(port.tag) == "internalPortReference"})

    def linked(endpoint, peer=None):
        return any(endpoint in net and len(net) > 1 and
                   (peer is None or peer in net) for net in nets)

    ps = "ARM_Processor_System_0"
    checks = {
        "motor_eram_present": "AXI_ERAM_Controller_0" in instances,
        "motor_gpio_present": "AXI_GPIO_0" in instances,
        "motor_eram_address_preserved":
            (ps, "M_AXI_GP0", "AXI_ERAM_Controller_0", "S_AXI", MOTOR_ERAM_BASE) in routes,
        "motor_gpio_address_preserved":
            (ps, "M_AXI_GP0", "AXI_GPIO_0", "S_AXI_Lite", MOTOR_GPIO_BASE) in routes,
        "video_npu_present": "Video_NPU_0" in instances,
        "ps_gp1_enabled": settings.get("Master_AXI_GP1_Interface") == "1",
        "ps_hp1_enabled": settings.get("Slave_AXI_HP1_Interface") == "1",
        "npu_control_address":
            (ps, "M_AXI_GP1", "Video_NPU_0", "S_AXI_Lite", NPU_BASE) in routes,
        "npu_dma_on_separate_hp1":
            any(route[:4] == ("Video_NPU_0", "M_AXI", ps, "S_AXI_HP1")
                for route in routes),
        "npu_axi_clocks_connected":
            all(linked(("Video_NPU_0", port))
                for port in ("S_AXILite_ACLK", "M_AXI_ACLK")),
        "npu_axi_resets_connected":
            all(linked(("Video_NPU_0", port))
                for port in ("S_AXILite_AResetn", "M_AXI_AResetn")),
        "npu_irq_to_ps":
            linked(("Video_NPU_0", "npu_soft_intr"), ("Concat_0", "In15"))
            and linked(("Concat_0", "Dout"), (ps, "f2p_irq")),
    }
    return {"schema": "fused-npu-di-preflight-v1", "checks": checks,
            "ready_for_synthesis": all(checks.values()),
            "limitations": "Static DI check only; no timing, bitstream, DT, driver, or inference proof"}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("design_xml")
    parser.add_argument("address_xml")
    args = parser.parse_args(argv)
    result = inspect(args.design_xml, args.address_xml)
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result["ready_for_synthesis"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
