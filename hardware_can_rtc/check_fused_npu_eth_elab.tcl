set candidate_root [file normalize [file dirname [info script]]]
cd $candidate_root
if {[catch {
    import_device dr1_90.db -package DR1M90GEG400 -speed 2
    open_project qian_sai_motor_open_loop.al -single_run
    elaborate -top motor_camera_npu_eth_top
} candidate_error]} {
    puts stderr "FAIL: protected 0x4143 NPU Ethernet top: $candidate_error"
    exit 1
}
puts "PASS: protected 0x4143 NPU Ethernet top elaborated offline; no BOOT or SD write"
exit 0
