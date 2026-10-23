set root [file dirname [file normalize [info script]]]
set build_base instrument
set config_file process_config.json
if {[info exists ::env(INSTRUMENT_BUILD_PROFILE)] && $::env(INSTRUMENT_BUILD_PROFILE) eq "touch_debug"} {
    set build_base instrument_touch_debug
    set config_file touch_debug_process_config.json
}
if {[info exists ::env(INSTRUMENT_BUILD_PROFILE)] && $::env(INSTRUMENT_BUILD_PROFILE) eq "ec11"} {
    set build_base instrument_ec11
    set config_file ec11_process_config.json
}
file mkdir [file join $root impl]
file copy -force [file join $root config $config_file] [file join $root impl ${build_base}_process_config.json]
open_project [file join $root ${build_base}.gprj]
set_option -include_path [file join $root src]
set_option -top_module instrument_top
set_option -output_base_name $build_base
set_option -vccx 1.8
set_option -use_cpu_as_gpio 1
# Plain-text timing reports are enabled by Generate_Plain_Text_Timing_Report
# in process_config.json; 1.9.12.04 does not accept -gen_text_timing_rpt.
run all
