set root [file dirname [file normalize [info script]]]
set build_base instrument_expression
file mkdir [file join $root impl]
file copy -force [file join $root config expression_process_config.json] [file join $root impl ${build_base}_process_config.json]
open_project [file join $root ${build_base}.gprj]
set_option -include_path [file join $root src]
set_option -top_module instrument_top
set_option -output_base_name $build_base
set_option -vccx 1.8
set_option -use_cpu_as_gpio 1
if {[info exists ::env(INSTRUMENT_SYNTHESIS_ONLY)] && $::env(INSTRUMENT_SYNTHESIS_ONLY) eq "1"} {
    run syn
} else {
    run all
}
