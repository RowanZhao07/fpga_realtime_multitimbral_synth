`timescale 1ns/1ps
module tb_voice_allocator #(parameter VARIABLE_SUSTAIN=1'b0);
 reg clk=0;always #10 clk=~clk;
 reg rst=1,ce=0,pedal=1;reg [12:0] gates=0;reg [1:0] octave=0;
 wire [5:0] count;wire overrun,valid;wire signed [18:0] mixed;
 polyphonic_engine #(.VARIABLE_SUSTAIN(VARIABLE_SUSTAIN)) dut(.sustain_strength(5'd16),.clk(clk),.rst(rst),.sample_ce(ce),.sustain_down(pedal),
 .gates(gates),.octave_select(octave),.timbre(2'd0),.vibrato(1'b0),
 .mixed(mixed),.valid(valid),.voice_count(count),.overrun(overrun));
 integer frames=0,cycles,k,f,max_cycles=0;reg [31:0] c3_phase;
 task frame;
 begin
 @(negedge clk);ce=1;@(negedge clk);ce=0;cycles=0;
 while(!valid && cycles<1000)begin @(negedge clk);cycles++;end
 if(!valid || overrun || (^mixed)===1'bx)$fatal(1,"Frame missed deadline or invalid PCM");
 if(cycles>950)$fatal(1,"Sample workload exceeds budget");
 if(cycles>max_cycles)max_cycles=cycles;
 repeat(8)@(negedge clk);frames++;
 end endtask
 initial begin
 repeat(4)@(negedge clk);rst=0;
 gates=13'h1fff;repeat(3)frame;
 if(count!=13)$fatal(1,"Simultaneous thirteen-note allocation lost events");
 rst=1;gates=0;repeat(4)@(negedge clk);rst=0;
 gates=1;repeat(140)frame;gates=0;frame;c3_phase=dut.phase[0];
 octave=1;gates=1;repeat(140)frame;
 if(count!=2 || dut.steps[0]!=11506414 || dut.steps[1]!=23012828)
 $fatal(1,"Cross-octave retrigger destroyed the old sustained note");
 if(dut.phase[0]==c3_phase)$fatal(1,"Old phase stopped");
 gates=0;frame;
 for(k=0;k<30;k++)begin octave=k%4;gates=1<<(k%13);repeat(3)frame;gates=0;frame;end
 repeat(140)frame;
 if(count!=32)$fatal(1,"Expected 32 actual sounding voices, got %d",count);
 gates=2;repeat(4)frame;
 if(count!=32)$fatal(1,"Stealing did not keep the bounded pool full");
 if(dut.owner[0]!=1)$fatal(1,"Oldest pedal-held voice not selected");
 gates=0;pedal=0;repeat(5000)frame;
 if(count!=0 || mixed!=0 || dut.occupied!=0)$fatal(1,"Stuck notes after pedal release");
 $display("PASS: 32 voices, dense onsets, maximum %0d clocks / 1024 budget, cross-octave tails, oldest stealing, release",max_cycles);
 $display("ALL TESTS PASSED");$finish;
 end
 initial begin #100000000;$fatal(1,"Allocator watchdog");end
endmodule
