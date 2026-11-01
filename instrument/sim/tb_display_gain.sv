`timescale 1ns/1ps
module tb_display_gain;
 reg signed [15:0] sample=0;wire signed [15:0] scaled,bypass;
 display_gain zoom(.sample(sample),.scaled(scaled));
 display_gain #(.ENABLE_3X(0)) unity(.sample(sample),.scaled(bypass));
 integer n,expected,previous=-32768;
 initial begin
   for(n=-32768;n<=32767;n=n+1)begin
     sample=n;#1;expected=n*3;
     if(expected>32767)expected=32767;
     if(expected< -32768)expected=-32768;
     if($signed(scaled)!=expected || $signed(bypass)!=n)$fatal(1,"Visual gain/sign/clamp error at %0d",n);
     if($signed(scaled)<previous)$fatal(1,"Display overflow/wrap at %0d",n);
     previous=$signed(scaled);
   end
   sample=9000;#1;
   if((scaled>>>8)!=105 || (scaled>>>9)!=52)$fatal(1,"Wave/XY coordinate zoom mismatch");
   sample=-9000;#1;
   if((scaled>>>8)!=-106 || (scaled>>>9)!=-53)$fatal(1,"Negative visual coordinate mismatch");
   sample=0;#1;if(scaled!=0)$fatal(1,"Silence moved from center");
   $display("PASS: all 65536 PCM inputs, exact 3x gain, monotonic signed saturation, bypass and waveform/XY quantization");
   $display("ALL TESTS PASSED");$finish;
 end
endmodule
