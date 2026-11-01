`timescale 1ns/1ps
module tb_limit_activity;
 reg clk=0;always #10 clk=~clk;
 reg rst=1,valid=0;reg signed [18:0] mixed=0;reg [12:0] volume=0;
 wire signed [15:0] pcm;wire clipped,limited;
 audio_output #(.DELAY_BITS(4)) dut(.clk(clk),.rst(rst),.valid(valid),.mixed(mixed),
 .volume(volume),.echo_enable(1'b0),.calibration(1'b0),.sample(pcm),.clipped(clipped),.limited(limited));
 integer gain,n,count,peak,f,first_count=-1;
 task step(input integer v);begin
   @(negedge clk);mixed=v;valid=1;@(negedge clk);valid=0;repeat(7)@(negedge clk);
 end endtask
 initial begin
 f=$fopen("output/limit_activity.csv","w");$fdisplay(f,"gain,limited_samples,total_samples,output_peak");
 repeat(5)@(negedge clk);rst=0;
 for(gain=1024;gain<=4096;gain=gain*2)begin
   volume=gain;repeat(4097)step(0);count=0;peak=0;
   for(n=0;n<512;n=n+1)begin
     step($rtoi(4095.0*$sin(6.28318530718*n/512.0)));
     if(limited)count=count+1;
     if(clipped)$fatal(1,"Hard clipping in normal solo signal");
     if(pcm>peak)peak=pcm;if(-pcm>peak)peak=-pcm;
   end
   if(count<220 || count>250)$fatal(1,"Unexpected soft-knee duty %0d",count);
   if(first_count<0)first_count=count;else if(count!=first_count)$fatal(1,"LIMIT activity should be pre-master");
   $fdisplay(f,"%0d,%0d,512,%0d",gain,count,peak);
   $display("GAIN %0d: soft-knee samples %0d/512, PCM peak %0d, hard clips 0",gain,count,peak);
 end
 $fclose(f);$display("ALL TESTS PASSED");$finish;
 end
endmodule
