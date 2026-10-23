`timescale 1ns/1ps
module tb_ec11_sustain;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,a=1,b=1,sw=1,set_valid=0,set_enabled=0;
 wire enabled;wire [4:0] strength;
 ec11_sustain #(.FILTER_CLOCKS(4),.BUTTON_CLOCKS(12)) dut(
  .clk(clk),.rst(rst),.a(a),.b(b),.sw_n(sw),.set_valid(set_valid),
  .set_enabled(set_enabled),.enabled(enabled),.strength(strength));
 wire [4:0] full_strength,reverse_strength;
 ec11_sustain #(.FILTER_CLOCKS(4),.BUTTON_CLOCKS(12),.TRANSITIONS_PER_STEP(4)) full_cycle(
  .clk(clk),.rst(rst),.a(a),.b(b),.sw_n(sw),.set_valid(1'b0),.set_enabled(1'b0),.enabled(),.strength(full_strength));
 ec11_sustain #(.FILTER_CLOCKS(4),.BUTTON_CLOCKS(12),.REVERSE(1)) reversed(
  .clk(clk),.rst(rst),.a(a),.b(b),.sw_n(sw),.set_valid(1'b0),.set_enabled(1'b0),.enabled(),.strength(reverse_strength));
 task tick(input integer n);repeat(n) @(negedge clk);endtask
 task phase(input [1:0] p);{a,b}=p;tick(15);endtask
 task cw;phase(2'b01);phase(0);phase(2'b10);phase(3);endtask
 task ccw;phase(2'b10);phase(0);phase(2'b01);phase(3);endtask
 task check(input integer n);if(strength!==n)$fatal(1,"Strength got %d expected %d",strength,n);endtask
 initial begin
  tick(4);rst=0;tick(30);check(3);if(enabled)$fatal(1,"Default must be off");
  cw();check(5);
  if(full_strength!==4 || reverse_strength!==1)$fatal(1,"Full-cycle/reverse configuration");
  ccw();check(3);if(full_strength!==3 || reverse_strength!==3)$fatal(1,"Reverse return");
  // A short glitch and a stable edge followed by its reversal produce no step.
  {a,b}=2'b01;tick(1);{a,b}=3;tick(20);check(3);
  phase(1);phase(3);check(3);
  // Illegal two-bit jumps discard partial history and safely resynchronize.
  phase(0);phase(3);check(3);cw();check(5);
  repeat(20)cw();check(16);repeat(20)ccw();check(1);
  // Independent button debounce: spikes do not toggle, holding never repeats.
  sw=0;tick(2);sw=1;tick(25);if(enabled)$fatal(1,"Button glitch");
  sw=0;tick(25);if(!enabled)$fatal(1,"Press ignored");
  tick(100);if(!enabled)$fatal(1,"Hold repeated");
  sw=1;tick(25);sw=0;tick(25);if(enabled)$fatal(1,"Second press ignored");
  set_enabled=1;set_valid=1;tick(1);set_valid=0;tick(2);
  if(!enabled)$fatal(1,"UART override ignored");
  // A button held through reset must first be released before it can toggle.
  rst=1;tick(4);rst=0;tick(30);check(3);
  if(enabled)$fatal(1,"Held startup button enabled sustain");
  sw=1;tick(25);sw=0;tick(25);if(!enabled)$fatal(1,"Rearmed press ignored");
  // Non-11 startup phase is a baseline, not movement.
  rst=1;{a,b}=1;sw=1;tick(4);rst=0;tick(30);check(3);
  $display("ALL TESTS PASSED");$finish;
 end
 initial begin #1000000;$fatal(1,"EC11 watchdog");end
endmodule
