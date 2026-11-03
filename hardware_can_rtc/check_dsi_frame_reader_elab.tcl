set candidate_root [file normalize [file dirname [info script]]]
cd $candidate_root
if {[catch {
    import_device dr1_90.db -package DR1M90GEG400 -speed 2
    open_project qian_sai_motor_open_loop.al -single_run
    elaborate -top dsi_frame_reader
} candidate_error]} {
    puts stderr "FAIL: DSI frame reader elaboration: $candidate_error"
    exit 1
}
puts "PASS: DSI frame-reader RTL elaborated offline; not wired to panel or motor top"
exit 0
