`timescale 1ns/1ps
// Feed-forward echo uses block RAM. Unwritten locations are explicitly masked.
module audio_output #(
    parameter integer DELAY_BITS=14
)(
    input wire clk, rst, valid,
    input wire signed [18:0] mixed,
    input wire [12:0] volume,
    input wire echo_enable,
    input wire calibration,
    output reg signed [15:0] sample=0,
    output reg clipped=0,
    output reg limited=0
);
    // Keep mixer headroom through the echo tap; never slice a loud mix to 16 bits.
    reg signed [18:0] delay_memory[0:(1<<DELAY_BITS)-1];
    reg [DELAY_BITS-1:0] write_pointer=0;
    reg [DELAY_BITS:0] filled=0;
    reg signed [18:0] dry=0, delayed=0;
    reg delayed_valid=0, echo_latched=0;
    reg calibration_latched=0;
    reg [3:0] pipeline=0;
    reg [12:0] smooth_gain=0;
    reg signed [19:0] sum=0;
    reg signed [15:0] normalized=0;
    reg limited_stage=0,limited_product=0;
    reg signed [29:0] product=0;
    wire signed [29:0] scaled=product>>>12;
    // LUT peak 8191 -> mixer /2 -> x8 output calibration: a solo attack
    // approaches full-scale at master=4096 and pressure=100%. This is 32x
    // the old mixed/4 path. A static, symmetric soft knee bounds polyphony;
    // no voice-count AGC or gain envelope can pump a previous note.
    // Master/pressure follow the knee, retaining their exact linear ratios.
    function signed [15:0] normalize;
        input signed [19:0] value;
        reg signed [22:0] boosted;
        reg [22:0] magnitude,result,excess;
        begin
            boosted=$signed({{3{value[19]}},value})<<<3;
            magnitude=boosted[22] ? -boosted : boosted;
            excess=magnitude-23'd24576;
            if(magnitude<=24576) result=magnitude;
            else if(magnitude<32768) result=24576+(excess>>1)+(excess>>2);
            else if(magnitude<65536) result=30720+((magnitude-32768)>>5);
            else if(magnitude<131072) result=31744+((magnitude-65536)>>7);
            else if(magnitude<262144) result=32256+((magnitude-131072)>>9);
            else if(magnitude<524288) result=32512+((magnitude-262144)>>11);
            else begin
                result=32640+((magnitude-524288)>>14);
                if(result>32760) result=32760;
            end
            normalize=boosted[22] ? -$signed(result[15:0]) : $signed(result[15:0]);
        end
    endfunction
    // Separate RAM process permits synchronous block-memory inference.
    always @(posedge clk) if(!rst) begin
        if(valid) delayed<=delay_memory[write_pointer];
        else if(pipeline[0]) delay_memory[write_pointer]<=dry;
    end
    always @(posedge clk) begin
        if(rst) begin
            write_pointer<=0; filled<=0; delayed_valid<=0; echo_latched<=0;
            pipeline<=0; dry<=0; sum<=0; normalized<=0; product<=0; sample<=0;
            clipped<=0; limited<=0; limited_stage<=0; limited_product<=0; smooth_gain<=0;calibration_latched<=0;
        end else begin
            pipeline<={pipeline[2:0],valid};
            if(valid) begin
                dry<=mixed; echo_latched<=echo_enable;calibration_latched<=calibration;
                delayed_valid<=(filled==(1<<DELAY_BITS));
                if(filled!=(1<<DELAY_BITS)) filled<=filled+1'b1;
                if(smooth_gain<volume) smooth_gain<=smooth_gain+1'b1;
                else if(smooth_gain>volume) smooth_gain<=smooth_gain-1'b1;
            end
            if(pipeline[0]) begin
                write_pointer<=write_pointer+1'b1;
                sum<=$signed({dry[18],dry})+((delayed_valid && echo_latched) ? ($signed({delayed[18],delayed})>>>2) : 20'sd0);
            end
            if(pipeline[1]) begin
                // Keep the eight-sine diagnostic linear at its original level.
                normalized<=calibration_latched ? (sum>>>2) : normalize(sum);
                limited_stage<=!calibration_latched && (sum>3072 || sum< -3072);
            end
            if(pipeline[2]) begin
                product<=normalized*$signed({1'b0,smooth_gain});
                limited_product<=limited_stage && smooth_gain!=0;
            end
            if(pipeline[3]) begin
                limited<=limited_product;
                if(scaled>32767) begin sample<=16'sh7FFF; clipped<=1; end
                else if(scaled< -32768) begin sample<=16'sh8000; clipped<=1; end
                else begin sample<=scaled[15:0]; clipped<=0; end
            end
        end
    end
endmodule
