`timescale 1ns/1ps
// Q4 mV IIR updates only on fresh ADC conversions; Q9 gain slews on audio ticks.
// Constant calibration parameters synthesize without a runtime divider.
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
    wire [31:0] scaled=(mv>ZERO_MV ? mv-ZERO_MV : 0)*384;
    wire [9:0] target=(!online || !have_sample) ? 10'd512 :
        mv<=ZERO_MV+DEADBAND_MV ? 10'd128 :
        mv>=FULL_MV ? 10'd512 : 10'd128+scaled/(FULL_MV-ZERO_MV);
    assign filtered_mv=mv;
    always @(posedge clk) begin
        if(rst) begin filtered_q4<=0;have_sample<=0;gain<=512;end
        else begin
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
