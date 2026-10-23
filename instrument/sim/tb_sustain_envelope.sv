`timescale 1ns/1ps
module tb_sustain_envelope;
 reg clk=0; always #5 clk=~clk;
 reg rst=1,gate=0,pedal=0;
 wire [15:0] level[0:3]; wire [3:0] active;
 genvar t;
 generate for(t=0;t<4;t=t+1) begin: bank
  envelope_adsr dut(.sustain_strength(5'd3),.clk(clk),.rst(rst),.sample_ce(1'b1),.gate(gate),
   .sustain_down(pedal),.timbre(t[1:0]),.level(level[t]),.active(active[t]));
 end endgenerate
 task tick(input integer n); repeat(n) @(negedge clk); endtask
 task clear; rst=1;tick(2);rst=0;gate=0;pedal=0;tick(2);endtask
 integer before_level;
 initial begin
  clear();pedal=1;tick(100);if(active!==0) $fatal(1,"Pedal must not start notes");
  gate=1;tick(3000);gate=0;tick(3000);
  if(bank[0].dut.state==4 || bank[1].dut.state==4 || bank[2].dut.state==4 || bank[3].dut.state==4)
   $fatal(1,"Pedal did not retain released notes");
  before_level=level[1];tick(4000);
  if(level[1]>=before_level || level[1]==0) $fatal(1,"Piano tail must decay naturally");
  gate=1;tick(2);if(bank[1].dut.state!=1) $fatal(1,"Repeated note must attack");
  tick(100);pedal=0;tick(2);
  if(bank[1].dut.state==4) $fatal(1,"Pedal up must not release a held key");
  gate=0;tick(1);before_level=level[1];pedal=1;tick(100);
  if(bank[1].dut.state!=4 || level[1]>=before_level) $fatal(1,"Pedal must not revive releasing notes");
  clear();gate=1;pedal=1;tick(3000);gate=0;tick(3000);
  before_level=level[0];pedal=0;tick(1);
  if(level[0]!=before_level || bank[0].dut.state!=4) $fatal(1,"Pedal release must start a tail, not hard mute");
  tick(12000);if(active!==0) $fatal(1,"Released tails must end");
  clear();gate=1;pedal=1;tick(100);gate=0;tick(200000);
  if(level[1]!=0 || active[1]) $fatal(1,"Fractional piano decay must reach silence");
  rst=1;tick(2);if(active!==0) $fatal(1,"Reset must silence sustained notes");
  $display("ALL TESTS PASSED");$finish;
 end
 initial begin #10000000;$fatal(1,"Sustain watchdog");end
endmodule
