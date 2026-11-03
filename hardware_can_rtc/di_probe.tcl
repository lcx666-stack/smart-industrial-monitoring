puts "RTC_PROBE_BEGIN"
foreach name {si_open_design si_design_add_connection si_design_make_external si_design_add_port si_generate_design} {
    set code [catch {$name} result]
    puts "RTC_PROBE $name code=$code result=$result"
}
puts "RTC_PROBE_END"
exit 0
