`timescale 1ns/1ps
// Every correct note-on advances in one sample, then stops after the excerpt.
module tb_builtin_score;
 reg clk=0;always #10 clk=~clk;
 reg rst=1,enabled=1;reg [12:0] gates=0;
 wire [12:0] target;wire [9:0] length;wire [8:0] position;wire [1:0] octave;
 wire rest,playing,finished;
 practice_guide #(.TICK_DENOM(32'd380928)) dut(.clk(clk),.rst(rst),.sample_ce(1'b1),
 .enabled(enabled),.bpm(8'd40),.gates(gates),.command_valid(1'b0),.input_error(1'b0),
 .command(8'd0),.value(16'd0),.target_mask(target),.length(length),.position(position),
 .octave(octave),.rest(rest),.playing(playing),.finished(finished));
 integer i,switches=0;reg [1:0] prior;reg [12:0] old_mask;
 initial begin
 repeat(4)@(negedge clk);rst=0;repeat(5)@(negedge clk);
 if(length!=76 || target!=2 || octave!=2)$fatal(1,"Vocal pickup is D5");
 prior=octave;
 for(i=0;i<76;i=i+1)begin
  if(position!=i)$fatal(1,"Wrong guide event %0d got %0d",i,position);
  if(octave!=prior)switches=switches+1;prior=octave;
  if(rest || playing || finished || dut.event_word[23])$fatal(1,"Built-in excerpt must be note-on driven");
  old_mask=target;
  gates=target ^ 13'h1fff;repeat(3)@(negedge clk);
  if(position!=i)$fatal(1,"Wrong key advanced the song");
  gates=0;repeat(2)@(negedge clk);gates=old_mask;
  @(negedge clk);
  if(i<75 && position!=i+1)$fatal(1,"Correct press did not advance immediately at %0d",i);
  if(i==75 && !finished)$fatal(1,"Last note must finish immediately");
  repeat(20)@(negedge clk);
  if(position!=(i<75 ? i+1 : 75))$fatal(1,"A held note skipped another event");
  gates=0;repeat(4)@(negedge clk);
 end
 if(!finished || target!=0 || rest || switches<2)$fatal(1,"Excerpt end / octave handoff missing");
 gates=13'h1fff;repeat(100)@(negedge clk);
 if(!finished || position!=75 || target!=0)$fatal(1,"Finished excerpt repeated");
 gates=0;enabled=0;repeat(5)@(negedge clk);enabled=1;repeat(5)@(negedge clk);
 if(finished || position!=0 || target!=2)$fatal(1,"Guide off/on did not restart");
 $display("PASS: 76 immediate note-ons, no hold/release wait, no repeat, explicit restart, %0d octave changes",switches);
 $display("ALL TESTS PASSED");$finish;
 end
 initial begin #1000000;$fatal(1,"Built-in score watchdog");end
endmodule
