`timescale 1ns/1ps
// Run the real allocator workload with finite EC11 tails enabled.
module tb_ec11_allocator;
 tb_voice_allocator #(.VARIABLE_SUSTAIN(1)) suite();
endmodule
