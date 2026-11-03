set candidate_root [file normalize [file dirname [info script]]]
cd $candidate_root
if {[catch {
    import_device dr1_90.db -package DR1M90GEG400 -speed 2
    open_project qian_sai_motor_open_loop.al -single_run
    elaborate -top motor_camera_npu_eth_top
    read_adc -file qian_sai_motor_open_loop.adc
    read_sdc -ip system_ARM_Processor_System_0 system/ip/system_ARM_Processor_System_0/system_ARM_Processor_System_0.sdc
    read_sdc motor_camera_timing.sdc
    # TD populates clock objects after optimization, not at elaboration.
} error_text]} {
    puts stderr "FAIL_VENDORCLOCK_ELABORATE $error_text"
    exit 1
}
puts "PASS_VENDORCLOCK_ELABORATE"
exit 0
