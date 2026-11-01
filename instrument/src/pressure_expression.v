`timescale 1ns/1ps
// Q4 mV IIR updates only on fresh ADC conversions; Q9 gain slews on audio ticks.
// Exact integer calibration uses a short-path, 21-cycle restoring divider.
module pressure_expression #(
    parameter integer ZERO_MV=0,FULL_MV=3072,DEADBAND_MV=16,
    parameter integer ATTACK_SHIFT=2,RELEASE_SHIFT=3
)(
    input wire clk,rst,online,sample_valid,sample_ce,
    input wire [11:0] millivolts,
    output reg [9:0] gain=512,
    output wire [11:0] filtered_mv
);
    reg [15:0] filtered_q4=0;
    reg have_sample=0;
    wire signed [17:0] delta=$signed({2'b0,millivolts,4'b0})-$signed({2'b0,filtered_q4});
    // Explicit signed intermediates prevent unsigned accumulator context from
    // turning a negative arithmetic right shift into a logical right shift.
    wire signed [17:0] attack_step=(delta+((1<<ATTACK_SHIFT)-1))>>>ATTACK_SHIFT;
    wire signed [17:0] release_step=delta>>>RELEASE_SHIFT;
    wire signed [17:0] next_q4=$signed({2'b0,filtered_q4})+(delta>0 ? attack_step : release_step);
    wire [11:0] mv=filtered_q4[15:4];
    // One 13-bit compare/subtract per clock replaces the long constant-division
    // network. A fresh conversion finishes every 22 clocks (0.44 us), much
    // faster than either the audio frame or ADC. Clamp flags share its snapshot.
    localparam [12:0] DIVISOR=FULL_MV-ZERO_MV;
    reg [20:0] dividend=0,quotient=0;
    reg [12:0] remainder=0;
    reg [4:0] bits_left=0;
    reg mapped_low=0,mapped_high=0;
    wire [12:0] trial={remainder[11:0],dividend[20]};
    wire take_bit=trial>=DIVISOR;
    wire [20:0] next_quotient={quotient[19:0],take_bit};
    reg [9:0] mapped_target=512;
    wire [9:0] target=(!online || !have_sample) ? 10'd512 : mapped_target;
    assign filtered_mv=mv;
    always @(posedge clk) begin
        if(rst) begin
            filtered_q4<=0;have_sample<=0;gain<=512;
            dividend<=0;quotient<=0;remainder<=0;bits_left<=0;
            mapped_low<=0;mapped_high<=0;mapped_target<=512;
        end
        else begin
            if(bits_left==0) begin
                dividend<=(mv>ZERO_MV ? mv-ZERO_MV : 0)*384;
                remainder<=0;quotient<=0;bits_left<=21;
                mapped_low<=mv<=ZERO_MV+DEADBAND_MV;mapped_high<=mv>=FULL_MV;
            end else begin
                dividend<={dividend[19:0],1'b0};
                remainder<=take_bit ? trial-DIVISOR : trial;
                quotient<=next_quotient;bits_left<=bits_left-1'b1;
                if(bits_left==1) mapped_target<=mapped_low ? 10'd128 : mapped_high ? 10'd512 : 10'd128+next_quotient[9:0];
            end
            if(!online) have_sample<=0;
            else if(sample_valid) begin
                have_sample<=1;
                if(!have_sample) filtered_q4<={millivolts,4'b0};
                else filtered_q4<=next_q4[15:0];
            end
            // One Q9 LSB per frame, including ADC disconnect/reconnect: <=0.2% gain step.
            if(sample_ce) begin
                if(gain<target) gain<=gain+1'b1;
                else if(gain>target) gain<=gain-1'b1;
            end
        end
    end
endmodule
