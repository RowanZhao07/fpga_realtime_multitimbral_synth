`timescale 1ns/1ps
// Retain peaks from BOTH adjacent FFT bins when drawing at half width.
module spectrum_pair_peak(
    input wire clk,rst,write_enable,
    input wire [8:0] address,
    input wire [7:0] value,
    output wire valid,
    output wire [7:0] pair_address,pair_value
);
    reg [7:0] even_value=0;
    always @(posedge clk) begin
        if(rst) even_value<=0;
        else if(write_enable && !address[0]) even_value<=value;
    end
    assign valid=write_enable && address[0];
    assign pair_address=address[8:1];
    assign pair_value=value>even_value ? value : even_value;
endmodule
