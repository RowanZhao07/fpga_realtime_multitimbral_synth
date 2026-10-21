`timescale 1ns/1ps
module tb_voice_feedback;
    reg clk=0;always #10 clk=~clk;
    reg rst=1;reg [3:0] divider=0;reg [12:0] gates=0;
    wire ce=divider==15;wire [12:0] active;wire [103:0] levels;
    wire signed [18:0] mixed;wire valid;
    always @(posedge clk) if(rst) divider<=0;else divider<=divider+1'b1;
    polyphonic_engine dut(.sustain_down(1'b0),.clk(clk),.rst(rst),.sample_ce(ce),.gates(gates),
        .timbre(2'd2),.vibrato(1'b0),.mixed(mixed),.valid(valid),.active(active),.voice_levels(levels));
    task samples(input integer n);
        repeat(n) begin @(negedge clk);while(!ce) @(negedge clk);@(negedge clk);end
    endtask
    integer k,nonzero=0;reg [7:0] old_white,old_sharp;
    always @(posedge clk) if(!rst && valid && mixed!=0) nonzero=nonzero+1;
    initial begin
        repeat(4) @(negedge clk);rst=0;
        if(levels!==0) $fatal(1,"Idle feedback");
        gates=13'h1fff;samples(4300);
        if(active!==13'h1fff || nonzero<100) $fatal(1,"No real 13-voice audio");
        for(k=0;k<13;k=k+1)
            if(levels[k*8+:8]<190) $fatal(1,"Missing envelope for voice %0d",k);
        old_white=levels[15:8];old_sharp=levels[103:96];
        gates[1]=0;gates[12]=0;samples(1000);
        if(!active[1] || !active[12] || levels[15:8]>=old_white || levels[103:96]>=old_sharp)
            $fatal(1,"Real release tails not reflected");
        for(k=0;k<13;k=k+1) if(k!=1 && k!=12 && levels[k*8+:8]<190)
            $fatal(1,"One key release affected another envelope");
        samples(8000);
        if(active[1] || active[12] || levels[15:8] || levels[103:96]) $fatal(1,"Tail never cleared");
        gates[12]=1;samples(2200);
        if(levels[103:96]<190 || levels[15:8]!=0) $fatal(1,"Last sharp feedback mapping/retrigger");
        rst=1;repeat(3) @(negedge clk);
        if(levels!==0 || active!==0) $fatal(1,"Feedback reset");
        $display("PASS: real 13-voice audio, ADSR feedback, independent white/sharp release, last-sharp retrigger, reset");
        $display("ALL TESTS PASSED");$finish;
    end
    initial begin #10000000;$fatal(1,"Voice-feedback watchdog");end
endmodule
