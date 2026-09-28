`timescale 1ns/1ps
// 16 significant bits, 32 BCK per channel, one-bit I2S delay, dual mono.
module i2s_transmitter (
    input wire clk, rst,
    input wire signed [15:0] sample,
    output wire sample_ce,
    output reg bck=0, lrck=1, din=0
);
    reg [2:0] divider=0;
    reg [5:0] position=0;
    reg [15:0] frame_sample=0;
    assign sample_ce=(divider==7 && bck && position==0 && !rst);
    always @(posedge clk) begin
        if(rst) begin divider<=0; position<=0; bck<=0; lrck<=1; din<=0; frame_sample<=0; end
        else if(divider==7) begin
            divider<=0; bck<=!bck;
            if(bck) begin
                lrck<=position[5];
                if(position[4:0]>=1 && position[4:0]<=16) din<=frame_sample[16-position[4:0]];
                else din<=0;
                if(position==0) frame_sample<=sample;
                position<=position+1'b1;
            end
        end else divider<=divider+1'b1;
    end
endmodule
