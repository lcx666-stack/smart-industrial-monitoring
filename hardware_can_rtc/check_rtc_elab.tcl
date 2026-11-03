set root [file normalize [file dirname [info script]]]
cd $root
import_device dr1_90.db -package DR1M90GEG400 -speed 2
open_project qian_sai_motor_open_loop.al -single_run
elaborate -top motor_camera_npu_eth_top
puts "RTC candidate elaborated"
exit 0
