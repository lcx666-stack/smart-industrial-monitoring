# Independent PWM 10 percent BOOT candidate. Camera/NPU/HP routing unchanged.
# Never writes the baseline bitstream, BOOT, or removable media.
set candidate_root [file normalize [file dirname [info script]]]
set report_root [file normalize [file join $candidate_root reports_rtc_bit]]
set build_started [clock seconds]
cd $candidate_root
foreach relative_path {system/Design.xml system/ip/system_ARM_Processor_System_0/Design.xml} {
    set path [file join $candidate_root $relative_path]
    set channel [open $path r]
    set xml [read $channel]
    close $channel
    foreach parameter {F2P_IRQ_Available Master_AXI_GP1_Interface Slave_AXI_HP0_Interface Slave_AXI_HP1_Interface} {
        set required "<ipxact:configurableElementValue referenceId=\"$parameter\">1</ipxact:configurableElementValue>"
        if {[string first $required $xml] < 0} {
            puts stderr "FAIL: $relative_path does not enable $parameter"
            exit 1
        }
    }
    foreach port {0 1} {
        set required "<ipxact:configurableElementValue referenceId=\"Slave_AXI_HP${port}_DATA_WIDTH\">64</ipxact:configurableElementValue>"
        if {[string first $required $xml] < 0} {
            puts stderr "FAIL: $relative_path does not set HP${port} width 64"
            exit 1
        }
    }
}
foreach relative_path {npu_sidecar.v npu_ip/design_0_Video_NPU_0/design_0_Video_NPU_0.xml npu_ip/design_0_PLL_0/design_0_PLL_0.v npu_ip/design_0_Processor_System_Reset_2/design_0_Processor_System_Reset_2.v} {
    if {![file exists [file join $candidate_root $relative_path]]} {
        puts stderr "FAIL: missing NPU sidecar component $relative_path"
        exit 1
    }
}
file mkdir $report_root
set bit_relative reports_rtc_bit/motor_camera_rtc_4143.bit
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
    set npu_clocks [get_clocks *u_npu_pll*]
    if {[llength $npu_clocks] == 0} {
        error "NPU PLL clock not present after gate optimization"
    }
    puts "NPU_CLOCK_OBJECTS $npu_clocks"
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
    # TD writes its routed timing summary beside the project even when -file
    # is supplied. A successful bitgen alone is not a timing pass.
    set routed_timing [file join $candidate_root motor_camera_npu_eth_top_route.timingsummary]
    if {![file exists $routed_timing]} {error "routed timing summary missing"}
    if {[file mtime $routed_timing] < $build_started} {error "stale routed timing summary"}
    set timing_channel [open $routed_timing r]
    set timing_text [read $timing_channel]
    close $timing_channel
    foreach metric {SWNS STNS HWNS HTNS} {
        set pattern [format {%s: *(-?[0-9]+(?:\.[0-9]+)?)ns} $metric]
        if {![regexp $pattern $timing_text matched value]} {
            error "missing $metric in routed timing summary"
        }
        if {$value < 0} {error "negative routed $metric: $value ns"}
    }
    bitgen -bit $bit_relative
} candidate_error]} {
    puts stderr "FAIL: RTC candidate bitstream: $candidate_error"
    exit 1
}
puts "PASS: RTC bitstream generated with routed timing pass; baseline BOOT and SD unchanged"
exit 0
