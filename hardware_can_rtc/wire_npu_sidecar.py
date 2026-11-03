"""Mechanically expose the dormant PS GP1/HP1/IRQ pins in this isolated copy.

The original board-tested project is never an output. Re-run only from a fresh
copy: every replacement is guarded and refuses already-modified inputs.
"""

import pathlib
import re


ROOT = pathlib.Path(__file__).resolve().parent
assert ROOT.name == "motor_camera_npu_eth_candidate_20261012"
VENDOR = ROOT.parent / "merged_candidate_soc_prj" / "design_0" / "ip"
WRAPPER = ROOT / "system/ip/system_ARM_Processor_System_0/system_ARM_Processor_System_0.v"
CORE = ROOT / "system/ip/system_ARM_Processor_System_0/RTL/ARM_Processor_System_system_ARM_Processor_System_0.v"
SYSTEM = ROOT / "system/hdl/system.v"
SIDECAR = ROOT / "npu_sidecar.v"
VENDOR_PS = VENDOR / "design_0_ARM_Processor_System_0/design_0_ARM_Processor_System_0.v"
CONVERTER = ROOT / "npu_ip/design_0_AXI_Protocol_Converter_1/design_0_AXI_Protocol_Converter_1.v"
NPU = ROOT / "npu_ip/design_0_Video_NPU_0/design_0_Video_NPU_0.v"

PORT = re.compile(r"^\s*(input|output)\s+(?:wire\s+)?(\[[^\]]+\])?\s*(\w+)\s*,?\s*$", re.M)


def ports(path):
    source = path.read_text(encoding="utf-8")
    header = source.split(");", 1)[0]
    return [(direction, width or "", name) for direction, width, name in PORT.findall(header)]


def once(source, old, new, label):
    count = source.count(old)
    if count != 1:
        raise RuntimeError("{} expected once, found {}".format(label, count))
    return source.replace(old, new, 1)


def declaration(direction, width, name):
    return "  {} wire {}{},\n".format(direction, width + " " if width else "", name)


def main():
    ps_extra = [(d, w, n) for d, w, n in ports(VENDOR_PS)
                if n.startswith("slave_hp1_axi_") or
                   n.startswith("master_gp1_axi_") or n == "f2p_irq"]
    assert len(ps_extra) > 70 and len({n for _, _, n in ps_extra}) == len(ps_extra)
    excluded_clocks = {"slave_hp1_axi_aclk", "master_gp1_axi_aclk"}
    data_ports = [(d, w, n) for d, w, n in ps_extra if n not in excluded_clocks]

    replacement = {}
    for path in (CORE, WRAPPER):
        source = path.read_text(encoding="utf-8")
        decls = "".join(declaration(d, w, n) for d, w, n in ps_extra)
        marker = re.compile(r"(?m)^([ \t]*output[ \t]+p2f_rst0_n,\n)")
        source, count = marker.subn(lambda match: decls + match.group(1), source)
        if count != 1:
            raise RuntimeError("{} port marker occurs {} times".format(path, count))
        if path == CORE:
            newly_exposed = []
            for _, _, name in ps_extra:
                if name == "f2p_irq":
                    source = once(source, "assign f2p_irq_TB[15:0] = 16'h0;",
                                  "assign f2p_irq_TB[15:0] = f2p_irq;", "IRQ tie-off")
                    continue
                pattern = re.compile(r"(\.{}\()([^)]*)(\))".format(re.escape(name)))
                source, count = pattern.subn(r"\g<1>" + name + r"\g<3>", source)
                if count == 0:
                    newly_exposed.append(name)
                elif count != 1:
                    raise RuntimeError("{} primitive pin occurs {} times".format(name, count))
            additions = "".join("\t\t.{}({}),\n".format(n, n) for n in newly_exposed)
            source = once(source, "\t\t.f2p_irq(f2p_irq_TB),",
                          additions + "\t\t.f2p_irq(f2p_irq_TB),",
                          "new primitive outputs")
        else:
            maps = "".join("      .{}({}),\n".format(n, n) for _, _, n in ps_extra)
            source = once(source, "      .p2f_rst0_n(p2f_rst0_n),",
                          maps + "      .p2f_rst0_n(p2f_rst0_n),", "wrapper map")
        replacement[path] = source

    source = SYSTEM.read_text(encoding="utf-8")
    wires = "\n    // Isolated NPU sidecar; original GP0/HP0 motor and camera paths are unchanged.\n"
    for _, width, name in data_ports:
        wires += "    wire {}npu_{};\n".format(width + " " if width else "", name)
    source = once(source, "); \n    wire", "); \n" + wires + "    wire", "system wire marker")
    maps = ""
    for _, _, name in ps_extra:
        signal = "w_port__ARM_Processor_System_0__p2f_clk0" if name in excluded_clocks else "npu_" + name
        maps += "                                                                      , .{}({})\n".format(name, signal)
    source = once(source,
                  "                                                                      , .p2f_rst0_n(w_port__ARM_Processor_System_0__p2f_rst0_n)",
                  maps + "                                                                      , .p2f_rst0_n(w_port__ARM_Processor_System_0__p2f_rst0_n)",
                  "system PS map")
    sidecar_map = "\n    npu_sidecar u_npu_sidecar (\n        .clk(motor_clk),\n        .resetn(motor_resetn),\n"
    sidecar_map += ",\n".join("        .{}(npu_{})".format(n, n) for _, _, n in data_ports)
    sidecar_map += "\n    );\n\n"
    source = once(source, "    system_Processor_System_Reset_0 system_Processor_System_Reset_0_Inst (",
                  sidecar_map + "    system_Processor_System_Reset_0 system_Processor_System_Reset_0_Inst (",
                  "sidecar instance")
    replacement[SYSTEM] = source

    # The sidecar uses the vendor's own AXI4-to-AXI-Lite converter and NPU IP.
    sidecar_ports = [("output" if d == "input" else "input", w, n)
                     for d, w, n in data_ports]
    lines = ["`timescale 1ns/1ps", "// 100 MHz PS clock; no motor-control register writes originate here.",
             "module npu_sidecar (", "    input wire clk,", "    input wire resetn,"]
    lines += ["    {} wire {}{},".format(d, w + " " if w else "", n)
              for d, w, n in sidecar_ports]
    lines[-1] = lines[-1].rstrip(",")
    lines += [");", ""]
    lines += ["    wire npu_soft_intr;",
              "    assign f2p_irq = {npu_soft_intr, 15'b0};",
              "    assign slave_hp1_axi_awqos = 4'b0;",
              "    assign slave_hp1_axi_arqos = 4'b0;",
              "    wire [12:0] conv_bid, conv_rid;",
              "    assign master_gp1_axi_bid = conv_bid[11:0];",
              "    assign master_gp1_axi_rid = conv_rid[11:0];"]
    conv_ports = ports(CONVERTER)
    lite_ports = [(d, w, n) for d, w, n in conv_ports if n.startswith("ds_axi_")]
    lines += ["    wire {}lite_{};".format(w + " " if w else "", n[7:])
              for _, w, n in lite_ports]
    lines += ["", "    design_0_AXI_Protocol_Converter_1 u_npu_axilite (" ]
    conv_maps = []
    for direction, _, name in conv_ports:
        if name.startswith("us_axi_"):
            suffix = name[7:]
            if suffix in ("awuser", "wuser", "aruser", "awqos", "arqos"):
                expr = "1'b0" if suffix.endswith("user") else "4'b0"
            elif suffix in ("buser", "ruser"):
                expr = ""
            elif suffix in ("bid", "rid"):
                expr = "conv_" + suffix
            elif suffix in ("awid", "arid"):
                expr = "{1'b0, master_gp1_axi_" + suffix + "}"
            elif suffix in ("awlen", "arlen"):
                expr = "{4'b0, master_gp1_axi_" + suffix + "}"
            elif suffix in ("awsize", "arsize"):
                expr = "{1'b0, master_gp1_axi_" + suffix + "}"
            else:
                expr = "master_gp1_axi_" + suffix
                assert any(n == expr for _, _, n in sidecar_ports), expr
        elif name.startswith("ds_axi_"):
            expr = "lite_" + name[7:]
        elif name == "aclk":
            expr = "clk"
        elif name == "aresetn":
            expr = "resetn"
        else:
            raise RuntimeError("unmapped converter port " + name)
        conv_maps.append("        .{}({})".format(name, expr))
    lines += [",\n".join(conv_maps), "    );", "", "    design_0_Video_NPU_0 u_video_npu ("]
    npu_maps = []
    for _, _, name in ports(NPU):
        if name.endswith("ACLK"):
            expr = "clk"
        elif name.endswith("AResetn"):
            expr = "resetn"
        elif name == "npu_soft_intr":
            expr = name
        elif name.startswith("s_axilite_"):
            expr = "lite_" + name[len("s_axilite_"):-2]
            assert any("lite_" + n[7:] == expr for _, _, n in lite_ports), name
        elif name.startswith("m_axi_"):
            match = re.fullmatch(r"m_axi_(.*)_soft_[io]", name)
            if match is None:
                raise RuntimeError("unexpected NPU master port " + name)
            expr = "slave_hp1_axi_" + match.group(1)
            assert any(n == expr for _, _, n in sidecar_ports), name
        else:
            raise RuntimeError("unmapped NPU port " + name)
        npu_maps.append("        .{}({})".format(name, expr))
    lines += [",\n".join(npu_maps), "    );", "endmodule", ""]
    if SIDECAR.exists():
        raise RuntimeError("sidecar already exists; refusing to overwrite")
    replacement[SIDECAR] = "\n".join(lines)

    for path, content in replacement.items():
        if not str(path.resolve()).startswith(str(ROOT.resolve())):
            raise RuntimeError("output escapes candidate: " + str(path))
        path.write_text(content, encoding="utf-8", newline="\n")
    print("PASS: generated isolated RTL GP1/HP1/IRQ sidecar; no bitstream or SD write")


if __name__ == "__main__":
    main()
