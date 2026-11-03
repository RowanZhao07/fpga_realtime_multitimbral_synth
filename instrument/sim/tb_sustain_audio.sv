`timescale 1ns/1ps
// Accelerated fabric cycles preserve the complete synthesis/output pipeline.
// WAV time is the real 50 MHz / 1024 sample cadence, not testbench wall time.
module tb_sustain_audio;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,ce=0,pedal=0;reg [12:0] gates=0;
 wire signed [18:0] mixed[0:1];wire [1:0] valid,clipped;
 wire signed [15:0] pcm[0:1];
 genvar v;
 generate for(v=0;v<2;v=v+1) begin: bank
  polyphonic_engine engine(.sustain_strength(5'd3),.clk(clk),.rst(rst),.sample_ce(ce),.gates(gates),
   .sustain_down(v==1 ? pedal : 1'b0),.timbre(3'd1),.octave_select(2'd1),.vibrato(1'b0),
   .mixed(mixed[v]),.valid(valid[v]),.active(),.voice_levels());
  audio_output output_stage(.clk(clk),.rst(rst),.valid(valid[v]),.mixed(mixed[v]),
   .volume(13'd4096),.calibration(1'b0),.echo_enable(1'b0),.sample(pcm[v]),.clipped(clipped[v]));
 end endgenerate
 integer f,n;
 initial begin
  f=$fopen("output/sustain.csv","w");if(!f)$fatal(1,"Cannot create sustain.csv");
  $fdisplay(f,"sample,dry,pedal_audio,pedal,gates");
  repeat(5) @(negedge clk);rst=0;
  for(n=0;n<195312;n=n+1) begin
   pedal=(n>=3906 && n<107422) || (n>=146484 && n<156250);
   gates=0;
   if(n>=4883 && n<9766) gates=13'h015;
   if(n>=29297 && n<34180) gates=13'h029;
   if(n>=53711 && n<58594) gates=13'h052;
   if(n>=78125 && n<83008) gates=13'h025;
   ce=1;@(negedge clk);ce=0;wait(&valid);repeat(8) @(negedge clk);
   if(clipped) $fatal(1,"Sustain example clipped");
   $fdisplay(f,"%0d,%0d,%0d,%0d,%0d",n,pcm[0],pcm[1],pedal,gates);
  end
  $fclose(f);$display("ALL TESTS PASSED");$finish;
 end
 initial begin #2000000000;$fatal(1,"Sustain audio watchdog");end
endmodule
