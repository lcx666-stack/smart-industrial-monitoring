# Offline elaboration of the concurrent motor/CS500 candidate. No bitstream.
set candidate_root [file normalize [file dirname [info script]]]
cd $candidate_root
if {[catch {
    import_device dr1_90.db -package DR1M90GEG400 -speed 2
    open_project qian_sai_motor_open_loop.al -single_run
    elaborate -top motor_open_loop_top
} candidate_error]} {
    puts stderr "FAIL: concurrent motor/CS500 elaboration: $candidate_error"
    exit 1
}
puts "PASS: concurrent motor/CS500 candidate elaborated offline; SD unchanged"
exit 0
