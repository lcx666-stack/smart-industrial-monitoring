# Offline resource check only. No P&R, BOOT image, or SD write.
set candidate_root [file normalize [file dirname [info script]]]
set report_root [file normalize [file join $candidate_root .. logs_motor_camera_synth_6]]
cd $candidate_root
file mkdir $report_root
if {[catch {
    import_device dr1_90.db -package DR1M90GEG400 -speed 2
    open_project qian_sai_motor_open_loop.al -single_run
    elaborate -top motor_open_loop_top
    read_adc -file qian_sai_motor_open_loop.adc
    read_sdc -ip system_ARM_Processor_System_0 system/ip/system_ARM_Processor_System_0/system_ARM_Processor_System_0.sdc
    read_sdc motor_camera_timing.sdc
    optimize_rtl
    optimize_gate -packarea [file join $report_root gate.area]
    puts "CLOCKS_AFTER_GATE: [get_clocks *]"
    check_timing -verbose -file [file join $report_root gate.check_timing]
} candidate_error]} {
    puts stderr "FAIL: concurrent motor/CS500 synthesis: $candidate_error"
    exit 1
}
puts "PASS: concurrent motor/CS500 candidate synthesized offline; SD unchanged"
exit 0
