# Offline resource-only synthesis: static CMA frame -> DSI panel, no NPU.
set candidate_root [file normalize [file dirname [info script]]]
set report_root [file normalize [file join $candidate_root .. logs_motor_camera_dsi_frame_synth_1]]
cd $candidate_root
file mkdir $report_root
if {[catch {
    import_device dr1_90.db -package DR1M90GEG400 -speed 2
    open_project qian_sai_motor_open_loop.al -single_run
    elaborate -top motor_camera_dsi_frame_top
    read_adc -file qian_sai_motor_open_loop.adc
    read_adc -file display_ip/dsi_panel_pins.adc
    read_sdc -ip system_ARM_Processor_System_0 system/ip/system_ARM_Processor_System_0/system_ARM_Processor_System_0.sdc
    read_sdc motor_camera_timing.sdc
    optimize_rtl
    optimize_gate -packarea [file join $report_root gate.area]
} candidate_error]} {
    puts stderr "FAIL: motor/CS500/DSI frame synthesis: $candidate_error"
    exit 1
}
puts "PASS: motor/CS500/DSI static-frame top synthesized offline; board display untested"
exit 0
