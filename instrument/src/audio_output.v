`timescale 1ns/1ps
// Feed-forward echo uses block RAM. Unwritten locations are explicitly masked.
module audio_output #(
    parameter integer DELAY_BITS=14
)(
    input wire clk, rst, valid,
    input wire signed [18:0] mixed,
    input wire [12:0] volume,
    input wire echo_enable,
    output reg signed [15:0] sample=0,
    output reg clipped=0
);
    reg signed [15:0] delay_memory[0:(1<<DELAY_BITS)-1];
    reg [DELAY_BITS-1:0] write_pointer=0;
    reg [DELAY_BITS:0] filled=0;
    reg signed [15:0] dry=0, delayed=0;
    reg delayed_valid=0, echo_latched=0;
    reg [2:0] pipeline=0;
    reg [12:0] smooth_gain=0;
    reg signed [18:0] sum=0;
    reg signed [32:0] product=0;
    wire signed [32:0] scaled=product>>>12;
    // Separate RAM process permits synchronous block-memory inference.
    always @(posedge clk) if(!rst) begin
        if(valid) delayed<=delay_memory[write_pointer];
        else if(pipeline[0]) delay_memory[write_pointer]<=dry;
    end
    always @(posedge clk) begin
        if(rst) begin
            write_pointer<=0; filled<=0; delayed_valid<=0; echo_latched<=0;
            pipeline<=0; dry<=0; sum<=0; product<=0; sample<=0; clipped<=0; smooth_gain<=0;
        end else begin
            pipeline<={pipeline[1:0],valid};
            if(valid) begin
                dry<=mixed[17:2]; echo_latched<=echo_enable;
                delayed_valid<=(filled==(1<<DELAY_BITS));
                if(filled!=(1<<DELAY_BITS)) filled<=filled+1'b1;
                if(smooth_gain<volume) smooth_gain<=smooth_gain+1'b1;
                else if(smooth_gain>volume) smooth_gain<=smooth_gain-1'b1;
            end
            if(pipeline[0]) begin
                write_pointer<=write_pointer+1'b1;
                sum<=$signed(dry)+((delayed_valid && echo_latched) ? ($signed(delayed)>>>2) : 19'sd0);
            end
            if(pipeline[1]) product<=sum*$signed({1'b0,smooth_gain});
            if(pipeline[2]) begin
                if(scaled>32767) begin sample<=16'sh7FFF; clipped<=1; end
                else if(scaled< -32768) begin sample<=16'sh8000; clipped<=1; end
                else begin sample<=scaled[15:0]; clipped<=0; end
            end
        end
    end
endmodule
