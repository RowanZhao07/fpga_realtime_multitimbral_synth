`timescale 1ns/1ps
// Audible articulation requirements: struck/decaying electric keys versus
// bowed/sustained strings. Exercise the same envelope modules used per voice.
module tb_timbre_profiles;
    reg clk=0;always #10 clk=~clk;
    reg rst=1,ce=0,gate=0;
    wire [15:0] levels[0:3];wire [3:0] active;
    genvar tone;
    generate for(tone=0;tone<4;tone=tone+1) begin: bank
        envelope_adsr envelope(.sustain_strength(5'd3),.sustain_down(1'b0),.clk(clk),.rst(rst),.sample_ce(ce),.gate(gate),
            .timbre(tone[1:0]),.level(levels[tone]),.active(active[tone]));
    end endgenerate
    task frames(input integer count);
        repeat(count) begin @(negedge clk);ce=1;@(negedge clk);ce=0;end
    endtask
    integer failures=0;
    initial begin
        repeat(5) @(negedge clk);rst=0;gate=1;frames(200);
        if(levels[1]<50000 || levels[2]>15000 || levels[2]==0) begin
            $display("FAIL: electric keys must strike promptly, strings must swell: %d %d",levels[1],levels[2]);
            failures=failures+1;
        end
        frames(24800);
        if(levels[1]>10000 || levels[2]<45000) begin
            $display("FAIL: held electric keys must decay while strings sustain: %d %d",levels[1],levels[2]);
            failures=failures+1;
        end
        frames(10000);
        if(active[1] || levels[1]!=0) $fatal(1,"Held electric keys did not decay to exact silence");
        gate=0;frames(1);gate=1;frames(200);
        if(!active[1] || levels[1]<50000) $fatal(1,"Silent held electric keys could not retrigger");
        gate=0;frames(3000);
        if(!active[2] || levels[2]<15000) begin
            $display("FAIL: string release must retain a smooth tail");failures=failures+1;
        end
        frames(12000);
        if(active!=0) $fatal(1,"Preset release did not reach exact silence");
        if(failures) $fatal(1,"Timbre articulation failures: %0d",failures);
        $display("PASS: fast decaying electric keys, slow sustained strings and bounded release");
        $display("ALL TESTS PASSED");$finish;
    end
    initial begin #10000000;$fatal(1,"Timbre profile watchdog");end
endmodule
