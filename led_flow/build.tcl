set root [file dirname [file normalize [info script]]]
open_project [file join $root led_flow.gprj]
set_option -top_module led_flow
set_option -output_base_name led_flow
set_option -vccx 1.8
set_option -use_cpu_as_gpio 1
run all
