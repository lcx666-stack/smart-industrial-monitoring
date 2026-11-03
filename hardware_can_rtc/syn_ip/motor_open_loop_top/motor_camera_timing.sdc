# PS p2f_clk0 is specified through system_ARM_Processor_System_0.sdc, exactly
# as in the board-tested motor build. Defining it as a primary clock on an
# internal net causes TD USR-6133 and is deliberately avoided here.
# Provisional 400 MHz bound for the incoming CSI clock (2.5 ns). The actual
# CS500 lane clock must still be measured/confirmed on the assembled board.
create_clock -name cs500_mipi_input -period 2.500 -waveform {0 1.250} [get_ports {mipi_clk_hs_p}]
derive_clocks

# Vendor uii2c builds its 100 kHz internal state-machine clock from the
# 24.123 MHz PLL output: CLK_DIV=239 -> SCL_DIV=119 -> toggle every 120 cycles.
create_generated_clock -name cs500_i2c_internal \
    -source [get_pins {u_core/u_camera_frontend/u_camera_pll/dr1_phy_pll_8c99844ac61f_Inst/u_DR1_PHY_PLL.clkc[3]}] \
    -divide_by 240 \
    [get_nets {u_core/u_camera_frontend/u_sensor_config/uii2c_inst/scl_clk}]

# Async assertion of PS/PLL reset is deliberately not a synchronous recovery
# path. Only the first three camera-domain release synchronizer registers are
# exempted; all downstream camera logic remains timed normally.
set_false_path -from [get_nets {u_core/motor_resetn}] -to [get_regs {u_core/u_camera_frontend/reset_sync_24[0]}]
set_false_path -from [get_nets {u_core/motor_resetn}] -to [get_regs {u_core/u_camera_frontend/reset_sync_24[1]}]
set_false_path -from [get_nets {u_core/motor_resetn}] -to [get_regs {u_core/u_camera_frontend/reset_sync_24[2]}]
set_false_path -from [get_nets {u_core/motor_resetn}] -to [get_regs {u_core/u_camera_frontend/reset_sync_68[0]}]
set_false_path -from [get_nets {u_core/motor_resetn}] -to [get_regs {u_core/u_camera_frontend/reset_sync_68[1]}]
set_false_path -from [get_nets {u_core/motor_resetn}] -to [get_regs {u_core/u_camera_frontend/reset_sync_68[2]}]
set_false_path -from [get_nets {u_core/motor_resetn}] -to [get_regs {u_core/u_camera_frontend/reset_sync_pixel[0]}]
set_false_path -from [get_nets {u_core/motor_resetn}] -to [get_regs {u_core/u_camera_frontend/reset_sync_pixel[1]}]
set_false_path -from [get_nets {u_core/motor_resetn}] -to [get_regs {u_core/u_camera_frontend/reset_sync_pixel[2]}]

# The first stage deliberately receives an asynchronous I2C-config status.
set_false_path -from [get_nets {u_core/u_camera_frontend/sensor_configured}] -to [get_regs {u_core/u_camera_frontend/sensor_config_pixel_sync[0]}]

# The vendor I2C controller uses a divided clock. Its handshake now crosses
# through explicit two-flop synchronizers; exempt only the first receiving
# stages and the asynchronously asserted reset synchronizer.
set_false_path -from [get_nets {u_core/u_camera_frontend/u_sensor_config/iic_busy}] -to [get_regs {u_core/u_camera_frontend/u_sensor_config/iic_busy_sync[0]}]
set_false_path -from [get_nets {u_core/u_camera_frontend/u_sensor_config/iic_bus_error}] -to [get_regs {u_core/u_camera_frontend/u_sensor_config/iic_error_sync[0]}]
set_false_path -from [get_nets {u_core/u_camera_frontend/u_sensor_config/iic_req}] -to [get_regs {u_core/u_camera_frontend/u_sensor_config/uii2c_inst/req_sync_scl[0]}]
set_false_path -from [get_nets {u_core/u_camera_frontend/u_sensor_config/rst_cnt[7]}] -to [get_regs {u_core/u_camera_frontend/u_sensor_config/uii2c_inst/rst_sync_scl[0]}]
set_false_path -from [get_nets {u_core/u_camera_frontend/u_sensor_config/rst_cnt[7]}] -to [get_regs {u_core/u_camera_frontend/u_sensor_config/uii2c_inst/rst_sync_scl[1]}]

# First PS-clocked stages for four independent camera status CDCs. The second
# stages remain normally timed; these exceptions must not include the motor
# guard, current trip, or waveform DMA paths.
set_false_path -to [get_regs {u_core/camera_pll_sync[0]}]
set_false_path -to [get_regs {u_core/camera_sensor_sync[0]}]
set_false_path -to [get_regs {u_core/camera_error_sync[0]}]
set_false_path -to [get_regs {u_core/camera_full_sync[0]}]
set_false_path -to [get_regs {u_core/camera_cfg_sync[0]}]
set_false_path -to [get_regs {u_core/camera_wait_sync[0]}]
set_false_path -to [get_regs {u_core/camera_link_sync1[0] u_core/camera_link_sync1[1] u_core/camera_link_sync1[2] u_core/camera_link_sync1[3] u_core/camera_link_sync1[4] u_core/camera_link_sync1[5] u_core/camera_link_sync1[6] u_core/camera_link_sync1[7] u_core/camera_link_sync1[8] u_core/camera_link_sync1[9] u_core/camera_link_sync1[10] u_core/camera_link_sync1[11] u_core/camera_link_sync1[12]}]
set_false_path -to [get_regs {u_core/camera_packet_sync1[0] u_core/camera_packet_sync1[1] u_core/camera_packet_sync1[2] u_core/camera_packet_sync1[3] u_core/camera_packet_sync1[4] u_core/camera_packet_sync1[5] u_core/camera_packet_sync1[6] u_core/camera_packet_sync1[7] u_core/camera_packet_sync1[8] u_core/camera_packet_sync1[9]}]
set_false_path -to [get_regs {u_core/camera_first_sync1[0] u_core/camera_first_sync1[1] u_core/camera_first_sync1[2] u_core/camera_first_sync1[3] u_core/camera_first_sync1[4] u_core/camera_first_sync1[5] u_core/camera_first_sync1[6] u_core/camera_first_sync1[7] u_core/camera_first_sync1[8]}]

# The vendor I2C bridge uses a bundled data handshake: wr_data is latched in
# the 24 MHz domain in the same cycle that iic_req is raised, then stays fixed
# until the slow I2C engine has asserted and deasserted busy. req_sync_scl is
# the two-stage control synchronizer. Cut only wr_data -> sda_r endpoints;
# retain timing for sda_r's own shifts and for all other slow-clock paths.
set_false_path -from [get_regs {u_core/u_camera_frontend/u_sensor_config/wr_data[0] u_core/u_camera_frontend/u_sensor_config/wr_data[1] u_core/u_camera_frontend/u_sensor_config/wr_data[2] u_core/u_camera_frontend/u_sensor_config/wr_data[3] u_core/u_camera_frontend/u_sensor_config/wr_data[4] u_core/u_camera_frontend/u_sensor_config/wr_data[5] u_core/u_camera_frontend/u_sensor_config/wr_data[6] u_core/u_camera_frontend/u_sensor_config/wr_data[7] u_core/u_camera_frontend/u_sensor_config/wr_data[8] u_core/u_camera_frontend/u_sensor_config/wr_data[9] u_core/u_camera_frontend/u_sensor_config/wr_data[10] u_core/u_camera_frontend/u_sensor_config/wr_data[11] u_core/u_camera_frontend/u_sensor_config/wr_data[12] u_core/u_camera_frontend/u_sensor_config/wr_data[13] u_core/u_camera_frontend/u_sensor_config/wr_data[14] u_core/u_camera_frontend/u_sensor_config/wr_data[15] u_core/u_camera_frontend/u_sensor_config/wr_data[16] u_core/u_camera_frontend/u_sensor_config/wr_data[17] u_core/u_camera_frontend/u_sensor_config/wr_data[18] u_core/u_camera_frontend/u_sensor_config/wr_data[19] u_core/u_camera_frontend/u_sensor_config/wr_data[20] u_core/u_camera_frontend/u_sensor_config/wr_data[21] u_core/u_camera_frontend/u_sensor_config/wr_data[22] u_core/u_camera_frontend/u_sensor_config/wr_data[23] u_core/u_camera_frontend/u_sensor_config/wr_data[24] u_core/u_camera_frontend/u_sensor_config/wr_data[25] u_core/u_camera_frontend/u_sensor_config/wr_data[26] u_core/u_camera_frontend/u_sensor_config/wr_data[27] u_core/u_camera_frontend/u_sensor_config/wr_data[28] u_core/u_camera_frontend/u_sensor_config/wr_data[29] u_core/u_camera_frontend/u_sensor_config/wr_data[30] u_core/u_camera_frontend/u_sensor_config/wr_data[31]}] -to [get_regs {u_core/u_camera_frontend/u_sensor_config/uii2c_inst/sda_r[0] u_core/u_camera_frontend/u_sensor_config/uii2c_inst/sda_r[1] u_core/u_camera_frontend/u_sensor_config/uii2c_inst/sda_r[2] u_core/u_camera_frontend/u_sensor_config/uii2c_inst/sda_r[3] u_core/u_camera_frontend/u_sensor_config/uii2c_inst/sda_r[4] u_core/u_camera_frontend/u_sensor_config/uii2c_inst/sda_r[5] u_core/u_camera_frontend/u_sensor_config/uii2c_inst/sda_r[6] u_core/u_camera_frontend/u_sensor_config/uii2c_inst/sda_r[7]}]
