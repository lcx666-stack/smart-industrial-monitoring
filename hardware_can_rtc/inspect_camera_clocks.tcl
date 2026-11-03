set candidate_root [file normalize [file dirname [info script]]]
cd $candidate_root
if {[catch {
    import_device dr1_90.db -package DR1M90GEG400 -speed 2
    open_project qian_sai_motor_open_loop.al -single_run
    elaborate -top motor_open_loop_top
    read_sdc -ip system_ARM_Processor_System_0 system/ip/system_ARM_Processor_System_0/system_ARM_Processor_System_0.sdc
    read_sdc motor_camera_timing.sdc
    puts "CLOCKS: [get_clocks *]"
    puts "SCL_NETS: [get_nets *scl_clk*]"
    puts "SCL_PINS: [get_pins *scl_clk*]"
    puts "SCL_EXACT_NET: [get_nets {u_core/u_camera_frontend/u_sensor_config/uii2c_inst/scl_clk}]"
    puts "SCL_EXACT_PIN: [get_pins {u_core/u_camera_frontend/u_sensor_config/uii2c_inst/scl_clk}]"
    puts "SCL_SOURCE_PIN: [get_pins {u_core/u_camera_frontend/u_sensor_config/uii2c_inst/I_clk}]"
    puts "SCL_SOURCE_NET: [get_nets {u_core/u_camera_frontend/clk_24m}]"
    puts "PLL_CLK3_PIN: [get_pins {u_core/u_camera_frontend/u_camera_pll/dr1_phy_pll_8c99844ac61f_Inst/u_DR1_PHY_PLL.clkc[3]}]"
    puts "RESET_SYNC_REGS: [get_regs {u_core/u_camera_frontend/reset_sync_24*}]"
    puts "PS_RESET_NET: [get_nets {u_core/u_system/w_net__Processor_System_Reset_0__peripheral_aresetn}]"
    puts "MOTOR_RESET_NET: [get_nets {u_core/motor_resetn}]"
    puts "RESET_SYNC_24_BIT0: [get_regs {u_core/u_camera_frontend/reset_sync_24[0]}]"
    puts "PIXEL_SYNC_BIT0: [get_regs {u_core/u_camera_frontend/sensor_config_pixel_sync[0]}]"
    puts "SENSOR_CONFIG_NET: [get_nets {u_core/u_camera_frontend/sensor_configured}]"
    puts "IIC_BUSY_NET: [get_nets {u_core/u_camera_frontend/u_sensor_config/iic_busy}]"
    puts "IIC_ERROR_NET: [get_nets {u_core/u_camera_frontend/u_sensor_config/iic_bus_error}]"
    puts "IIC_REQ_NET: [get_nets {u_core/u_camera_frontend/u_sensor_config/iic_req}]"
    puts "IIC_RST_NET: [get_nets {u_core/u_camera_frontend/u_sensor_config/rst_cnt[7]}]"
    puts "IIC_BUSY_SYNC0: [get_regs {u_core/u_camera_frontend/u_sensor_config/iic_busy_sync[0]}]"
    puts "IIC_ERROR_SYNC0: [get_regs {u_core/u_camera_frontend/u_sensor_config/iic_error_sync[0]}]"
    puts "IIC_REQ_SYNC0: [get_regs {u_core/u_camera_frontend/u_sensor_config/uii2c_inst/req_sync_scl[0]}]"
    puts "IIC_RST_SYNC0: [get_regs {u_core/u_camera_frontend/u_sensor_config/uii2c_inst/rst_sync_scl[0]}]"
    puts "MIPI_PORT: [get_ports mipi_clk_hs_p]"
} clock_error]} {
    puts stderr "FAIL: camera clock inspection: $clock_error"
    exit 1
}
exit 0
