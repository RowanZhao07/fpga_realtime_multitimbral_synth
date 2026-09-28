set root [file dirname [file normalize [info script]]]
file mkdir [file join $root impl]
file copy -force [file join $root config process_config.json] [file join $root impl instrument_process_config.json]
open_project [file join $root instrument.gprj]
set_option -top_module instrument_top
set_option -output_base_name instrument
set_option -vccx 1.8
set_option -use_cpu_as_gpio 1
set_option -gen_text_timing_rpt 1
run all
