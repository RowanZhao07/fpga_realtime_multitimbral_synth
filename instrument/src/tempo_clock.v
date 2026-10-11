`timescale 1ns/1ps
// Fractional beat accumulator avoids a variable divider in the 50MHz path.
module tempo_clock #(
    parameter integer CLOCK_HZ=50000000,
    parameter integer FLASH_CLOCKS=3125000
)(input wire clk,rst,input wire [7:0] bpm,output wire flash,output reg beat=0);
    localparam [32:0] PERIOD=33'd60*CLOCK_HZ;
    reg [31:0] phase=0,flash_left=0;
    reg [7:0] previous_bpm=120;
    wire [32:0] next_phase={1'b0,phase}+bpm;
    assign flash=(flash_left!=0);
    always @(posedge clk) begin
        if(rst || bpm!=previous_bpm) begin
            phase<=0;flash_left<=FLASH_CLOCKS;previous_bpm<=bpm;beat<=0;
        end else begin
            beat<=0;
            if(flash_left!=0) flash_left<=flash_left-1'b1;
            if(next_phase>=PERIOD) begin
                phase<=next_phase-PERIOD;beat<=1;flash_left<=FLASH_CLOCKS;
            end else phase<=next_phase[31:0];
        end
    end
endmodule
