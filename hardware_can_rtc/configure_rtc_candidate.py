"""Connect the board RTC to PS I2C1 without changing the original project."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def edit(name, changes):
    path = ROOT / name
    data = path.read_text(encoding="utf-8")
    for old, new in changes:
        count = data.count(old)
        if count != 1:
            raise RuntimeError(f"{name}: expected one match, got {count}: {old[:80]!r}")
        data = data.replace(old, new, 1)
    path.write_text(data, encoding="utf-8", newline="\n")


i2c_ports = "    input wire rtc_scl_in,\n    input wire rtc_sda_in,\n    output wire rtc_scl_oe,\n    output wire rtc_sda_oe,\n"

edit("motor_camera_npu_eth_top.v", [
    ("    inout wire cam_sda,\n", "    inout wire cam_sda,\n    inout wire rtc_scl, rtc_sda,\n"),
    ("    motor_soc_top #(\n", "    wire rtc_scl_oe, rtc_sda_oe;\n"
     "    wire rtc_scl_in = rtc_scl;\n    wire rtc_sda_in = rtc_sda;\n"
     "    assign rtc_scl = rtc_scl_oe ? 1'b0 : 1'bz;\n"
     "    assign rtc_sda = rtc_sda_oe ? 1'b0 : 1'bz;\n\n"
     "    motor_soc_top #(\n"),
    ("        .cam_scl(cam_scl), .cam_sda(cam_sda),\n",
     "        .cam_scl(cam_scl), .cam_sda(cam_sda),\n"
     "        .rtc_scl_in(rtc_scl_in), .rtc_sda_in(rtc_sda_in),\n"
     "        .rtc_scl_oe(rtc_scl_oe), .rtc_sda_oe(rtc_sda_oe),\n"),
])

edit("motor_soc_top.v", [
    ("    inout  wire        cam_sda,\n", "    inout  wire        cam_sda,\n" + i2c_ports),
    ("    system u_system (\n", "    system u_system (\n"
     "        .i2c1_scl_in(rtc_scl_in), .i2c1_sda_in(rtc_sda_in),\n"
     "        .i2c1_scl_oe(rtc_scl_oe), .i2c1_sda_oe(rtc_sda_oe),\n"),
])

edit("system/hdl/system.v", [
    ("module system (\n", "module system (\n"
     "    input wire i2c1_scl_in, i2c1_sda_in,\n"
     "    output wire i2c1_scl_oe, i2c1_sda_oe,\n"),
    ("    system_ARM_Processor_System_0 system_ARM_Processor_System_0_Inst ( \n",
     "    system_ARM_Processor_System_0 system_ARM_Processor_System_0_Inst ( \n"
     "        .i2c1_scl_in(i2c1_scl_in), .i2c1_sda_in(i2c1_sda_in),\n"
     "        .i2c1_scl_oe(i2c1_scl_oe), .i2c1_sda_oe(i2c1_sda_oe),\n"),
])

ps = "system/ip/system_ARM_Processor_System_0/"
edit(ps + "system_ARM_Processor_System_0.v", [
    ("module system_ARM_Processor_System_0\n(\n",
     "module system_ARM_Processor_System_0\n(\n"
     "  input i2c1_scl_in, i2c1_sda_in,\n"
     "  output i2c1_scl_oe, i2c1_sda_oe,\n"),
    ("  )ARM_Processor_System_Inst\n  (\n",
     "  )ARM_Processor_System_Inst\n  (\n"
     "      .i2c1_scl_in(i2c1_scl_in), .i2c1_sda_in(i2c1_sda_in),\n"
     "      .i2c1_scl_oe(i2c1_scl_oe), .i2c1_sda_oe(i2c1_sda_oe),\n"),
])

edit(ps + "RTL/ARM_Processor_System_system_ARM_Processor_System_0.v", [
    ("\tparameter Slave_AXI_HP0_DATA_WIDTH = 64,",
     "\tparameter Slave_AXI_HP0_DATA_WIDTH = 64,"),
    (")\n(\n\n\n\n\n", ")\n(\n\tinput i2c1_scl_in, i2c1_sda_in,\n"
     "\toutput i2c1_scl_oe, i2c1_sda_oe,\n\n\n\n\n"),
    ("\t\t.i2c1_scl_in(1'b0),\n\t\t.i2c1_sda_in(1'b0),",
     "\t\t.i2c1_scl_in(i2c1_scl_in),\n"
     "\t\t.i2c1_scl_oe(i2c1_scl_oe),\n"
     "\t\t.i2c1_sda_in(i2c1_sda_in),\n"
     "\t\t.i2c1_sda_oe(i2c1_sda_oe),"),
])

for name in ("system/Design.xml", ps + "Design.xml"):
    edit(name, [
        ('referenceId="I2C1_Available">0<', 'referenceId="I2C1_Available">1<'),
        ('referenceId="I2C1_Dot_Enable">0<',
         'referenceId="I2C1_Dot_Enable">1<'),
    ])

edit("qian_sai_motor_open_loop.adc", [
    ("set_pin_assignment { cam_mclk", "# PT7C4337 RTC: PS I2C1 via PL; open-drain in top-level RTL.\n"
     "set_pin_assignment { rtc_scl } { LOCATION = L15; IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }\n"
     "set_pin_assignment { rtc_sda } { LOCATION = L14; IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }\n"
     "set_pin_assignment { cam_mclk"),
])

old_project = "D:/qian_ru_shi_competition/vision_motor_merge_20261011/motor_camera_pwm10_candidate_20261016"
edit("qian_sai_motor_open_loop.al", [
    (old_project, ROOT.as_posix()),
])

print("RTC I2C1 candidate wiring configured")
