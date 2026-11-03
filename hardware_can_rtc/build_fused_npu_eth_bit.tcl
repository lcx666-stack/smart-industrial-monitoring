# Offline bitstream build for the protected 0x4143 motor + CS500 + NPU top.
# This never writes BOOT.bin or removable media.
set candidate_root [file normalize [file dirname [info script]]]
set report_root [file normalize [file join $candidate_root reports_fused_npu_eth_bit]]
cd $candidate_root
file mkdir $report_root
set bit_relative reports_fused_npu_eth_bit/motor_camera_npu_eth_4143.bit
if {[file exists [file join $candidate_root $bit_relative]]} {
    puts stderr "FAIL: refusing to overwrite existing bitstream"
    exit 1
}
if {[catch {
    import_device dr1_90.db -package DR1M90GEG400 -speed 2
    open_project qian_sai_motor_open_loop.al -single_run
    elaborate -top motor_camera_npu_eth_top
    read_adc -file qian_sai_motor_open_loop.adc
    read_sdc -ip system_ARM_Processor_System_0 system/ip/system_ARM_Processor_System_0/system_ARM_Processor_System_0.sdc
    read_sdc motor_camera_timing.sdc
    optimize_rtl
    optimize_gate -packarea [file join $report_root gate.area]
    set mipi_clocks [concat [get_clocks cs500_mipi_input] [get_clocks *u_rx_clk_gen*]]
    set system_clocks [concat [get_clocks *p2f_clk0] [get_clocks *u_camera_pll*]]
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
    bitgen -bit $bit_relative
} candidate_error]} {
    puts stderr "FAIL: fused protected motor/CS500/NPU bitstream: $candidate_error"
    exit 1
}
puts "PASS: offline fused protected motor/CS500/NPU bitstream generated; SD unchanged"
exit 0
