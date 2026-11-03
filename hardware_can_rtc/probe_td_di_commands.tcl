# Read-only TD command probe in this isolated project copy.
set root [file normalize [file dirname [info script]]]
cd $root
import_device dr1_90.db -package DR1M90GEG400 -speed 2
open_project qian_sai_motor_open_loop.al -single_run
puts "DI_COMMANDS [lsort [info commands si_*]]"
puts "IP_COMMANDS [lsort [info commands *ip*]]"
puts "GEN_COMMANDS [lsort [info commands *generat*]]"
puts "PACKAGES [lsort [package names]]"
foreach name {xmlipgen ipgen_synip create_syn_ip generate_wrapper_file} {
    if {[catch {$name -help} message]} {
        puts "HELP_${name}_ERROR $message"
    } else {
        puts "HELP_${name} $message"
    }
    if {[catch {$name} message]} {puts "USAGE_${name}_ERROR $message"} else {puts "USAGE_${name} $message"}
}
exit 0
