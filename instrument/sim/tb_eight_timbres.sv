`timescale 1ns/1ps
// Exercise local preset cycling and a genuinely mixed 32-voice pool.
module tb_eight_timbres;
 reg clk=0;always #10 clk=~clk;
 reg rst=1,ce=0,pedal=1,command_valid=0;
 reg [17:0] touched=0;reg [15:0] value=0;
 wire [2:0] timbre;
 performance_control #(.ENABLE_EXPRESSION(1),.HOLD_SAMPLES(8)) controls(
 .clk(clk),.rst(rst),.sample_ce(ce),.online(1'b1),.touched(touched),
 .joystick_up(1'b0),.joystick_down(1'b0),.joystick_vibrato(1'b0),
 .command_valid(command_valid),.command(8'h54),.value(value),.timbre(timbre));
 reg [12:0] gates=0;reg [1:0] octave=1;
 wire valid,overrun;wire signed [18:0] mixed;wire [5:0] count;
 polyphonic_engine #(.VARIABLE_SUSTAIN(1),.ENABLE_PITCH_BEND(1)) dut(
 .clk(clk),.rst(rst),.sample_ce(ce),.sustain_down(pedal),.sustain_strength(5'd16),
 .gates(gates),.timbre(timbre),.octave_select(octave),.vibrato(1'b0),
 .pitch_bend(16'sd0),.mixed(mixed),.valid(valid),.overrun(overrun),.voice_count(count));
 integer cycles,max_cycles=0,k,n;
 task frame;
 begin
   @(negedge clk);ce=1;@(negedge clk);ce=0;cycles=0;
   while(!valid && cycles<1000)begin @(negedge clk);cycles=cycles+1;end
   if(!valid || overrun || (^mixed)===1'bx)$fatal(1,"Invalid/missed eight-timbre audio frame");
   if(cycles>max_cycles)max_cycles=cycles;
   if(cycles>950)$fatal(1,"Renderer exhausted sample budget");
   repeat(1022-cycles)@(negedge clk);
 end endtask
 task select_tone(input integer tone);
 begin @(negedge clk);value=tone;command_valid=1;@(negedge clk);command_valid=0;end
 endtask
 initial begin
 repeat(5)@(negedge clk);rst=0;
 for(k=1;k<=8;k=k+1)begin
   touched=18'h100;frame;frame;touched=0;frame;frame;
   if(timbre!==(k%8))$fatal(1,"C0 cycle lost a preset/wrap: %0d",timbre);
 end
 // Every allocated voice keeps its own preset even as the next-note preset changes.
 for(k=0;k<32;k=k+1)begin
   select_tone(k%8);octave=(k/13)%4;gates=0;frame;
   // Let even short organ/flute attacks build a tail before releasing the key.
   gates=13'b1<<(k%13);repeat(8)frame;
 end
 repeat(32)frame;
 if(count!=32)$fatal(1,"Mixed eight-timbre pool has %0d voices",count);
 for(k=0;k<32;k=k+1)
   if(dut.preset[k]!=(k%8))$fatal(1,"Held/released preset changed in slot %0d",k);
 gates=0;frame;select_tone(7);gates=13'h1fff;frame;frame;frame;
 if(count!=32)$fatal(1,"Dense stealing failed in new timbre bank");
 gates=0;pedal=0;repeat(12000)frame;
 if(count!=0 || mixed!=0 || dut.occupied!=0)$fatal(1,"Stuck voice in eight-timbre release");
 $display("PASS: C0 cycles all 8, per-voice presets retained, 32 mixed voices, stealing, silence; max %0d / 1024 clocks",max_cycles);
 $display("ALL TESTS PASSED");$finish;
 end
 initial begin #(64'd400000000);$fatal(1,"Eight-timbre watchdog");end
endmodule
