`timescale 1ns/1ps
// All ports synchronous to clk. External ADC/I2S must cross into this clock first.
// Sample bus has no ready: consumer must sustain the configured rate or buffer locally.
// Result payload is opaque 96-bit ABI; see docs/listening_interface.md.
module listening_analysis_port #(
    parameter integer RATE_NUMERATOR=50000000, RATE_DENOMINATOR=1024,
    parameter integer EXPIRE_CYCLES=50000000, parameter SOURCE_EXTERNAL=1'b0
)(
    input wire clk,rst,
    input wire playback_ce,input wire signed [15:0] playback_sample,
    input wire external_ce,input wire signed [15:0] external_sample,
    output wire analysis_ce,output wire signed [15:0] analysis_sample,
    output wire analysis_external,output reg [31:0] sample_index=0,
    output wire [31:0] analysis_rate_numerator,analysis_rate_denominator,
    input wire result_valid,input wire [95:0] result_payload,
    output wire result_ready,output reg [95:0] latest_result=0,
    output reg latest_valid=0,output reg result_update=0
);
    assign analysis_ce=!rst && (SOURCE_EXTERNAL ? external_ce : playback_ce);
    assign analysis_sample=SOURCE_EXTERNAL ? external_sample : playback_sample;
    assign analysis_external=SOURCE_EXTERNAL;
    assign analysis_rate_numerator=RATE_NUMERATOR;
    assign analysis_rate_denominator=RATE_DENOMINATOR;
    assign result_ready=!rst;
    // Wall-clock expiry also works when an external input stops supplying samples.
    // Default expiry is one second at the board 50 MHz system clock.
    reg [31:0] age=0;
    always @(posedge clk) begin
        result_update<=0;
        if(rst) begin sample_index<=0;latest_result<=0;latest_valid<=0;age<=0; end
        else begin
            if(analysis_ce) sample_index<=sample_index+1'b1;
            if(result_valid && result_ready) begin
                latest_result<=result_payload;latest_valid<=1;result_update<=1;age<=0;
            end else if(latest_valid) begin
                if(age==EXPIRE_CYCLES-1) begin latest_valid<=0;age<=0; end
                else age<=age+1'b1;
            end
        end
    end
endmodule
