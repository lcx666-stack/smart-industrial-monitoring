set candidate_root [file normalize [file dirname [info script]]]
cd $candidate_root
import_device dr1_90.db -package DR1M90GEG400 -speed 2
open_project qian_sai_motor_open_loop.al -single_run
elaborate -top motor_camera_dsi_frame_top
read_adc -file qian_sai_motor_open_loop.adc
read_adc -file display_ip/dsi_panel_pins.adc
read_sdc -ip system_ARM_Processor_System_0 system/ip/system_ARM_Processor_System_0/system_ARM_Processor_System_0.sdc
read_sdc motor_camera_timing.sdc
foreach reg_pattern {
    {u_core/camera_sensor_sync[0]}
    {u_core/camera_error_sync[0]}
    {u_core/camera_pll_sync[0]}
    {u_core/u_camera_frontend/u_sensor_config/wr_data[24]}
    {u_core/u_camera_frontend/u_sensor_config/uii2c_inst/sda_r[0]}
    {u_core/u_camera_frontend/u_sensor_config/wr_data*}
    {u_core/u_camera_frontend/u_sensor_config/uii2c_inst/sda_r*}
    {u_core/u_camera_frontend/u_sensor_config/wr_data[0] u_core/u_camera_frontend/u_sensor_config/wr_data[1]}
} {
    puts "CDC_REG_MATCH $reg_pattern : [get_regs $reg_pattern]"
}
exit 0
