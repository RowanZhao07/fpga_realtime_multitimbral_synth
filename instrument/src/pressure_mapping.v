`timescale 1ns/1ps
// User-measured full playing pressure: 3235mV (2026-10-25).
// Q9 expression 128..512 (25..100%); reciprocal error < 1/512 gain.
module pressure_mapping(input wire [11:0] millivolts,
 output wire [9:0] gain,output wire [7:0] bar_width);
 wire [24:0] scaled=millivolts*13'd7779; // floor(384*65536/3235)
 wire [8:0] travel=millivolts>=12'd3235 ? 9'd384 : scaled[24:16];
 assign gain=10'd128+{1'b0,travel};
 assign bar_width=travel[8:1];
endmodule
