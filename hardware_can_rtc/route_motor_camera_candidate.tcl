# Offline place/route and timing reports only. No bitstream or SD write.
set candidate_root [file normalize [file dirname [info script]]]
set report_root [file normalize [file join $candidate_root .. logs_motor_camera_route_5]]
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
    # CS500 MIPI receive clock comes from the external sensor, unrelated to
    # the PS/PLL clocks. Its CDCs use vendor dual-clock FIFO or explicit sync.
    set mipi_clocks [concat [get_clocks cs500_mipi_input] [get_clocks *u_rx_clk_gen*]]
    set system_clocks [concat [get_clocks *p2f_clk0] [get_clocks *u_camera_pll*]]
    puts "MIPI_CDC_CLOCKS: $mipi_clocks"
    puts "SYSTEM_CDC_CLOCKS: $system_clocks"
    if {[llength $mipi_clocks] < 2 || [llength $system_clocks] < 3} {
        error "Missing clock objects for asynchronous CSI CDC constraint"
    }
    set_clock_groups -asynchronous -group $mipi_clocks -group $system_clocks
    legalize_phy_inst
    place
    route
    update_timing -mode final
    report_timing_status -file [file join $report_root final.ts]
    report_timing_summary -file [file join $report_root final.timing]
    check_timing -verbose -file [file join $report_root check.timing]
} candidate_error]} {
    puts stderr "FAIL: concurrent motor/CS500 route: $candidate_error"
    exit 1
}
puts "PASS: concurrent motor/CS500 candidate routed offline; timing requires report inspection; SD unchanged"
exit 0
