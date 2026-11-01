`timescale 1ns/1ps
// Global, continuous pitch wheel. No phase resets or discrete note changes.
// Q16 frequency deviation: -2 semitones = -7150, +2 semitones = +8026.
// Neutral is learned only inside a plausible supply-dependent center window.
module pitch_expression #(
    parameter integer CENTER_SAMPLES=8, DEAD_MV=60, SLEW=16
)(
    input wire clk,rst,sample_ce,enabled,online,sample_valid,
    input wire [11:0] millivolts,
    output reg armed=0,
    output reg signed [15:0] bend=0
);
    reg [11:0] center=1650;
    reg [3:0] centers=0;
    reg [15:0] center_sum=0;
    reg signed [15:0] target=0;
    reg [11:0] distance=0;
    reg negative=0,scaled_negative=0;
    reg [26:0] scaled=0;
    reg [2:0] pipeline=0;
    wire neutral=millivolts>=1300 && millivolts<=1900;
    // A full throw of 1.30 V beyond the dead zone reaches the calibrated limit.
    // Mapping is linear in frequency; endpoint musical intervals are exact to Q16.
    always @(posedge clk) begin
        if(rst || !enabled || !online) begin
            armed<=0;centers<=0;center_sum<=0;target<=0;pipeline<=0;
            if(rst) begin center<=1650;bend<=0;end
            else if(sample_ce) begin
                if(bend>SLEW) bend<=bend-SLEW;
                else if(bend< -SLEW) bend<=bend+SLEW;
                else bend<=0;
            end
        end else begin
            pipeline<={pipeline[1:0],sample_valid && armed};
            if(sample_valid) begin
                if(!armed) begin
                    if(!neutral) begin centers<=0;center_sum<=0;end
                    else if(centers==CENTER_SAMPLES-1) begin
                        center<=(center_sum+{4'b0,millivolts})/CENTER_SAMPLES;
                        armed<=1;centers<=0;center_sum<=0;
                    end else begin centers<=centers+1'b1;center_sum<=center_sum+millivolts;end
                end else begin
                    negative<=millivolts<center;
                    if(millivolts>center+DEAD_MV) distance<=millivolts-center-DEAD_MV;
                    else if(millivolts+DEAD_MV<center) distance<=center-millivolts-DEAD_MV;
                    else distance<=0;
                end
            end
            if(pipeline[0]) begin
                scaled<=distance*(negative ? 15'd22528 : 15'd25288);
                scaled_negative<=negative;
            end
            if(pipeline[1]) begin
                if(scaled_negative) target<=scaled>=27'd29286400 ? -16'sd7150 : -$signed({1'b0,scaled[26:12]});
                else target<=scaled>=27'd32874496 ? 16'sd8026 : $signed({1'b0,scaled[26:12]});
            end
            if(sample_ce) begin
                if($signed(target)-$signed(bend)>SLEW) bend<=bend+SLEW;
                else if($signed(bend)-$signed(target)>SLEW) bend<=bend-SLEW;
                else bend<=target;
            end
        end
    end
endmodule
