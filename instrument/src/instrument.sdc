create_clock -name board_ref -period 20.000 [get_ports {ref_clk}]
create_generated_clock -name system_clk -source [get_ports {ref_clk}] -master_clock board_ref -divide_by 1 [get_nets {clk}]
create_generated_clock -name pixel_clk -source [get_ports {ref_clk}] -master_clock board_ref -multiply_by 4 -divide_by 5 [get_nets {pixel_clk}]
create_generated_clock -name serial_clk -source [get_ports {ref_clk}] -master_clock board_ref -multiply_by 4 [get_nets {serial_clk}]
# Audio/video transfers use acknowledged mailboxes and bank ownership. The two
# video outputs remain related (5:1); do not cut pixel-to-serializer timing.
set_clock_groups -asynchronous -group [get_clocks {system_clk}] -group [get_clocks {pixel_clk serial_clk}]
