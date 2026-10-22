`timescale 1ns/1ps
module tb_guide_timing;
 reg clk=0;always #10 clk=~clk;
 reg rst=1,enabled=1,valid=0,error=0;reg [7:0] command=0;reg [15:0] value=0;
 reg [12:0] gates=0;wire [12:0] mask;wire [8:0] pos;wire [1:0] octave;
 wire [9:0] length;wire playing,ok,rest;
 practice_guide #(.TICK_DENOM(32'd4915200)) dut(.clk(clk),.rst(rst),.sample_ce(1'b1),.bpm(8'd120),
 .enabled(enabled),.gates(gates),.command_valid(valid),.command(command),.value(value),.input_error(error),
 .command_ok(ok),.target_mask(mask),.length(length),.position(pos),.octave(octave),.rest(rest),.playing(playing));
 task send(input [7:0] c,input [15:0] v);
 @(negedge clk);command=c;value=v;valid=1;#1;if(!ok)$fatal(1,"Rejected setup");
 @(negedge clk);valid=0;endtask
 initial begin
 repeat(4)@(negedge clk);rst=0;
 send("N",0);send("O",3);send("U",2);send("A",1);
 send("O",6);send("U",1);send("A",256);send("A",0);send("Z",0);
 repeat(3)@(negedge clk);
 if(pos!=0 || octave!=0 || mask!=1)$fatal(1,"Initial absolute octave");
 repeat(50)@(negedge clk);if(pos!=0)$fatal(1,"Score generated autonomous note progress");
 gates=1;repeat(3)@(negedge clk);gates=0;repeat(5)@(negedge clk);
 if(pos!=0)$fatal(1,"Duration ignored");
 repeat(20)@(negedge clk);
 if(pos!=1 || octave!=3 || mask!=256)$fatal(1,"Automatic cross-octave handoff");
 gates=256;repeat(30)@(negedge clk);
 if(pos!=1)$fatal(1,"Held note advanced and remapped prematurely");
 gates=0;repeat(3)@(negedge clk);
 if(pos!=2 || !rest)$fatal(1,"Missing rest");
 repeat(15)@(negedge clk);if(pos!=0 || octave!=0)$fatal(1,"Rest duration/loop");
 enabled=0;repeat(3)@(negedge clk);if(playing || pos!=0)$fatal(1,"Disable reset");
 $display("PASS: absolute octave, note wait, duration, release interlock, timed rest, loop");
 $display("ALL TESTS PASSED");$finish;
 end
 initial begin #100000;$fatal(1,"Guide watchdog");end
endmodule
