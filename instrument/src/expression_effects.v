`timescale 1ns/1ps
// Sample-domain effects, independent of the display FFT. All memories infer
// synchronous RAM; fill counters mask unread locations after reset.
// Four damped feedback combs + two Schroeder allpasses form a small-room reverb.
// Chorus uses a continuously moving fractional delay with linear interpolation.
module expression_effects #(
    parameter integer C0=1493,C1=1601,C2=1747,C3=1867,A0=211,A1=73
)(
    input wire clk,rst,valid,calibration,
    input wire [1:0] mode, // 0=dry, 1=external echo, 2=reverb, 3=chorus
    input wire signed [18:0] mixed,
    output reg valid_out=0,
    output reg signed [18:0] result=0
);
    reg signed [18:0] comb0[0:C0-1],comb1[0:C1-1],comb2[0:C2-1],comb3[0:C3-1];
    reg signed [18:0] ap0[0:A0-1],ap1[0:A1-1],chorus[0:2047];
    reg [10:0] p0=0,p1=0,p2=0,p3=0,cp=0;
    reg [7:0] a0p=0,a1p=0;
    reg [11:0] filled=0;
    reg [7:0] pipe=0;
    reg signed [18:0] r0=0,r1=0,r2=0,r3=0,ar0=0,ar1=0,cr0=0,cr1=0;
    reg signed [18:0] d0=0,d1=0,d2=0,d3=0,ad0=0,ad1=0,cd0=0,cd1=0;
    reg signed [18:0] lp0=0,lp1=0,lp2=0,lp3=0,dry=0,input_scaled=0;
    reg signed [18:0] av0=0,ay0=0,av1=0,ay1=0;
    reg signed [18:0] reverb_input=0,chorus_value=0;
    reg signed [28:0] interpolation=0;
    reg [23:0] lfo=0;
    wire [22:0] triangle=lfo[23] ? ~lfo[22:0] : lfo[22:0];
    wire [15:0] delay_fraction=triangle[22:7];
    wire [10:0] delay_samples=11'd512+{3'b0,delay_fraction[15:8]};
    reg [7:0] fraction=0,rv_gain=0,ch_gain=0;
    reg bypass=0;
    reg signed [27:0] rv_product=0,ch_product=0;
    wire signed [21:0] wet_sum=$signed(dry)+($signed(rv_product)>>>9)+($signed(ch_product)>>>9);
    function signed [18:0] sat;
        input signed [21:0] x;
        begin sat=x>262143 ? 19'sd262143 : x< -262144 ? -19'sd262144 : x[18:0];end
    endfunction
    // Round toward zero inside recursive filters to avoid negative DC limit cycles.
    function signed [18:0] half;
        input signed [20:0] x;
        begin half=x<0 ? -((-x)>>>1) : x>>>1;end
    endfunction
    function signed [18:0] feedback;
        input signed [18:0] x;
        reg signed [20:0] t;
        begin t=$signed(x)*3;feedback=t<0 ? -((-t)>>>2) : t>>>2;end
    endfunction
    // Reads and writes occupy different cycles, with pointers held until complete.
    always @(posedge clk) if(!rst) begin
        if(valid) begin
            r0<=comb0[p0];r1<=comb1[p1];r2<=comb2[p2];r3<=comb3[p3];
            ar0<=ap0[a0p];ar1<=ap1[a1p];
            cr0<=chorus[(cp-delay_samples)&11'h7ff];
            cr1<=chorus[(cp-delay_samples-11'd1)&11'h7ff];
        end
        if(pipe[2]) begin
            comb0[p0]<=sat($signed(input_scaled)+$signed(feedback(lp0)));
            comb1[p1]<=sat($signed(input_scaled)+$signed(feedback(lp1)));
            comb2[p2]<=sat($signed(input_scaled)+$signed(feedback(lp2)));
            comb3[p3]<=sat($signed(input_scaled)+$signed(feedback(lp3)));
            chorus[cp]<=dry;
        end
        if(pipe[4]) ap0[a0p]<=av0;
        if(pipe[6]) ap1[a1p]<=av1;
    end
    always @(posedge clk) begin
        valid_out<=0;
        if(rst) begin
            p0<=0;p1<=0;p2<=0;p3<=0;cp<=0;a0p<=0;a1p<=0;filled<=0;pipe<=0;
            lp0<=0;lp1<=0;lp2<=0;lp3<=0;lfo<=0;rv_gain<=0;ch_gain<=0;
            result<=0;rv_product<=0;ch_product<=0;bypass<=0;
        end else begin
            pipe<={pipe[6:0],valid};
            if(valid) begin
                dry<=mixed;input_scaled<=mixed>>>3;bypass<=calibration;
                fraction<=delay_fraction[7:0];lfo<=lfo+24'd241;
                if(filled<2048) filled<=filled+1'b1;
                if(!calibration && mode==2) begin if(rv_gain<128) rv_gain<=rv_gain+1'b1;end
                else if(rv_gain!=0) rv_gain<=rv_gain-1'b1;
                if(!calibration && mode==3) begin if(ch_gain<128) ch_gain<=ch_gain+1'b1;end
                else if(ch_gain!=0) ch_gain<=ch_gain-1'b1;
            end
            if(pipe[0]) begin
                // filled includes this sample, hence strictly greater than length.
                d0<=filled>C0 ? r0 : 19'sd0;d1<=filled>C1 ? r1 : 19'sd0;
                d2<=filled>C2 ? r2 : 19'sd0;d3<=filled>C3 ? r3 : 19'sd0;
                ad0<=filled>A0 ? ar0 : 19'sd0;ad1<=filled>A1 ? ar1 : 19'sd0;
                cd0<=filled>768 ? cr0 : 19'sd0;cd1<=filled>768 ? cr1 : 19'sd0;
            end
            if(pipe[1]) begin
                lp0<=half($signed(d0)+$signed(lp0));lp1<=half($signed(d1)+$signed(lp1));
                lp2<=half($signed(d2)+$signed(lp2));lp3<=half($signed(d3)+$signed(lp3));
                reverb_input<=($signed({{2{d0[18]}},d0})+$signed(d1)+$signed(d2)+$signed(d3))>>>2;
                interpolation<=($signed({cd1[18],cd1})-$signed({cd0[18],cd0}))*$signed({1'b0,fraction});
            end
            if(pipe[2]) begin
                av0<=sat($signed(reverb_input)+$signed(half(ad0)));
                chorus_value<=sat($signed(cd0)+($signed(interpolation)>>>8));
            end
            if(pipe[3]) ay0<=sat($signed(ad0)-$signed(half(av0)));
            if(pipe[4]) av1<=sat($signed(ay0)+$signed(half(ad1)));
            if(pipe[5]) ay1<=sat($signed(ad1)-$signed(half(av1)));
            if(pipe[6]) begin
                rv_product<=ay1*$signed({1'b0,rv_gain});
                ch_product<=chorus_value*$signed({1'b0,ch_gain});
            end
            if(pipe[7]) begin
                result<=bypass ? dry : sat(wet_sum);valid_out<=1;
                p0<=p0==C0-1 ? 0 : p0+1'b1;p1<=p1==C1-1 ? 0 : p1+1'b1;
                p2<=p2==C2-1 ? 0 : p2+1'b1;p3<=p3==C3-1 ? 0 : p3+1'b1;
                a0p<=a0p==A0-1 ? 0 : a0p+1'b1;a1p<=a1p==A1-1 ? 0 : a1p+1'b1;
                cp<=cp+1'b1;
            end
        end
    end
endmodule
