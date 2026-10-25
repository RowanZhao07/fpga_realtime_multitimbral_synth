`timescale 1ns/1ps
// Real 50MHz core and audio sample period, with normal touch controls.
module tb_full_scale_audio;
 reg clk=0;always #10 clk=~clk;
 reg rst=1;reg [17:0] touched=0;
 wire ce;wire signed [15:0] pcm;
 instrument_core #(.ENABLE_EC11(1)) dut(.clk(clk),.rst(rst),.online(1'b1),
 .encoder_a(1'b1),.encoder_b(1'b1),.encoder_sw_n(1'b1),.sustain_request(1'b0),
 .touched(touched),.chip_online(2'b11),.pressure_online(1'b1),.pressure_mv(12'd3235),
 .control_rx(1'b1),.monitor_ce(ce),.monitor_sample(pcm));
 defparam dut.controls.HOLD_SAMPLES=8;
 defparam dut.controls.REPEAT_SAMPLES=1;
 task frame;@(posedge ce);repeat(900)@(negedge clk);endtask
 integer peak,n,tone,f;
 initial begin
 f=$fopen("output/full_scale_audio.csv","w");$fdisplay(f,"tone,frame,pcm");
 repeat(5)@(negedge clk);rst=0;
 touched=18'h400;repeat(40)frame;touched=0;repeat(4200)frame;
 if(dut.volume!=4096 || dut.expressive_volume!=4096 || dut.output_stage.smooth_gain!=4096)
 $fatal(1,"Max master/pressure not unity");
 for(tone=0;tone<4;tone=tone+1)begin
  peak=0;touched=1;
  for(n=0;n<5000;n=n+1)begin
   frame;$fdisplay(f,"%0d,%0d,%0d",tone,n,pcm);
   if(pcm>peak)peak=pcm;if(-pcm>peak)peak=-pcm;
   if(dut.clipped || dut.engine_overrun)$fatal(1,"Clip or missed audio deadline");
  end
  if(peak<27000 || peak>31000)$fatal(1,"Full-scale solo tone %0d peak %0d",tone,peak);
  $display("PASS: timbre %0d, maximum volume + pressure, solo attack peak %0d / 32767",tone,peak);
  touched=0;repeat(13000)frame;
  if(pcm!=0)$fatal(1,"Tail no longer reaches silence");
  touched=18'h100;repeat(2)frame;touched=0;repeat(4)frame;
 end
 $fclose(f);$display("ALL TESTS PASSED");$finish;
 end
 initial begin #(64'd2000000000);$fatal(1,"Full-scale audio watchdog");end
endmodule
