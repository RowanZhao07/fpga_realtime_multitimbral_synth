`timescale 1ns/1ps
module tb_output_level;
 reg clk=0;always #10 clk=~clk;
 reg rst=1,valid=0,echo=0;reg signed [18:0] mixed=0;reg [12:0] volume=4096;
 wire signed [15:0] sample;wire clipped,limited;
 audio_output #(.DELAY_BITS(3)) dut(.clk(clk),.rst(rst),.valid(valid),.mixed(mixed),
 .volume(volume),.calibration(1'b0),.echo_enable(echo),.sample(sample),.clipped(clipped),.limited(limited));
 task frame(input integer x);
 @(negedge clk);mixed=x;valid=1;@(negedge clk);valid=0;repeat(6)@(negedge clk);
 if($isunknown(sample) || clipped || sample>32760 || sample< -32760)
 $fatal(1,"Output overflow, unknown or rail clipping: %0d -> %0d",x,sample);
 endtask
 integer previous,x,positive,full;
 initial begin
 repeat(3)@(negedge clk);rst=0;repeat(4100)frame(0);
 frame(500);if(sample!=4000 || limited)$fatal(1,"Calibrated linear gain");
 frame(4095);if(sample<30000 || sample>31000 || !limited)$fatal(1,"Solo attack not near full scale");
 previous=-32760;
 // Cover every mixer code, including values outside the normal 32-voice range.
 for(x=-262144;x<262144;x=x+1)begin
  frame(x);if(sample<previous)$fatal(1,"Wrap or nonmonotonic transfer at %0d",x);
  previous=sample;
 end
 for(x=0;x<262144;x=x+997)begin
  frame(x);positive=sample;frame(-x);
  if(sample!= -positive)$fatal(1,"Asymmetric soft knee at %0d",x);
 end
 frame(18000);full=sample;volume=1024;repeat(3100)frame(18000);
 if(sample!=full/4)$fatal(1,"Master volume no longer scales the limited mix linearly");
 volume=0;repeat(1100)frame(262143);if(sample!=0 || limited)$fatal(1,"Zero-volume mute");
 volume=4096;echo=1;repeat(4100)frame(262143);
 if(sample<32000 || !limited)$fatal(1,"Loud echo wrapped negative");
 repeat(10)frame(-262144);if(sample> -32000)$fatal(1,"Negative loud echo wrapped positive");
 repeat(12)frame(0);if(sample!=0)$fatal(1,"Echo retained residual DC");
 $display("PASS: full mixer range monotonic/symmetric, near-full solo, linear master, wide echo, mute");
 $display("ALL TESTS PASSED");$finish;
 end
 initial begin #100000000;$fatal(1,"Output-level watchdog");end
endmodule
