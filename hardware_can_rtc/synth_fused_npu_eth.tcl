# Offline resource gate for the Ethernet-preview fused candidate.
# Keep the proven motor/CS500 top, but prune the unused black-screen DSI path.
# This does not produce a BOOT image or write removable media.
set candidate_root [file normalize [file dirname [info script]]]
set report_root [file normalize [file join $candidate_root reports_fused_npu_eth]]
cd $candidate_root
file mkdir $report_root
if {[catch {
    import_device dr1_90.db -package DR1M90GEG400 -speed 2
    open_project qian_sai_motor_open_loop.al -single_run
    elaborate -top motor_camera_npu_eth_top
    read_adc -file qian_sai_motor_open_loop.adc
    read_sdc -ip system_ARM_Processor_System_0 system/ip/system_ARM_Processor_System_0/system_ARM_Processor_System_0.sdc
    read_sdc motor_camera_timing.sdc
    optimize_rtl
    optimize_gate -packarea [file join $report_root gate.area]
    check_timing -verbose -file [file join $report_root gate.check_timing]
} candidate_error]} {
    puts stderr "FAIL: fused motor/CS500/NPU synthesis: $candidate_error"
    exit 1
}
puts "PASS: fused motor/CS500/NPU synthesis completed; inspect resource and timing reports before board use"
exit 0
