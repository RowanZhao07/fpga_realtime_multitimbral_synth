`timescale 1ns/1ps
module tb_dynamic_timbre;
 reg clk=0;always #10 clk=~clk;
 reg rst=1,ce=0;reg [12:0] gates=0;reg [2:0] tone=0;
 wire signed [18:0] mixed;wire valid;wire [5:0] count;wire overrun;
 polyphonic_engine dut(.sustain_strength(5'd3),.clk(clk),.rst(rst),.sample_ce(ce),.gates(gates),.sustain_down(1'b0),
 .timbre(tone),.octave_select(2'd1),.vibrato(1'b0),.mixed(mixed),.valid(valid),.voice_count(count),.overrun(overrun));
 integer f,t,n;
 task frame;
 @(negedge clk);ce=1;@(negedge clk);ce=0;wait(valid);repeat(8)@(negedge clk);
 if(overrun || (^mixed)===1'bx)$fatal(1,"Invalid timed audio frame");
 endtask
 initial begin
 f=$fopen("output/dynamic_timbre.csv","w");$fdisplay(f,"tone,sample,mixed");
 for(t=0;t<4;t++)begin
 rst=1;gates=0;repeat(3)@(negedge clk);rst=0;tone=t;gates=1;
 for(n=0;n<16384;n++)begin frame;$fdisplay(f,"%0d,%0d,%0d",t,n,mixed);end
 if(count!=1)$fatal(1,"Lost active timbre voice");
 if(t!=0 && dut.brightness[0]>=60000)$fatal(1,"Spectrum never evolved");
 gates=0;repeat(13000)frame;if(count!=0 || mixed!=0)$fatal(1,"Timbre release stuck");
 end
 $fclose(f);$display("ALL TESTS PASSED");$finish;
 end
 initial begin #2000000000;$fatal(1,"Dynamic timbre watchdog");end
endmodule
