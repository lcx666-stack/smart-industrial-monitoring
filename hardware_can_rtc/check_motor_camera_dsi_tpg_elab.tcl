# Offline only: DSI vendor test pattern with the motor+CS500 candidate.
set candidate_root [file normalize [file dirname [info script]]]
cd $candidate_root
if {[catch {
    import_device dr1_90.db -package DR1M90GEG400 -speed 2
    open_project qian_sai_motor_open_loop.al -single_run
    elaborate -top motor_camera_dsi_tpg_top
} candidate_error]} {
    puts stderr "FAIL: motor/CS500/DSI TPG elaboration: $candidate_error"
    exit 1
}
puts "PASS: motor/CS500/DSI test-pattern top elaborated offline; SD unchanged"
exit 0
