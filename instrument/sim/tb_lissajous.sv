`timescale 1ns/1ps
module tb_lissajous;
 reg aclk=0,pclk=0;always #10 aclk=~aclk;always #12.5 pclk=~pclk;
 reg rst=1,ce=0,blank=0;reg signed [15:0] pcm=0;
 reg [13:0] address=0;wire value,ready;
 lissajous_capture dut(.audio_clk(aclk),.audio_rst(rst),.sample_ce(ce),.sample(pcm),
 .pixel_clk(pclk),.pixel_rst(rst),.vertical_blank(blank),.read_address(address),.read_value(value),.ready(ready));
 integer n,on_pixels,tx,ty,check_count=0;reg bank;
 task tick(input integer v);
 begin
   @(negedge aclk);pcm=v;ce=1;@(negedge aclk);ce=0;
   repeat(1023)@(negedge aclk);
 end endtask
 task swap;
 begin repeat(5)@(negedge pclk);blank=1;@(negedge pclk);blank=0;repeat(5)@(negedge pclk);end endtask
 always @(posedge aclk) if(!rst && dut.state==2) begin
   if(dut.write_bank==dut.read_bank && ready)$fatal(1,"Writer modified visible XY bank");
 end
 initial begin
 repeat(5)@(negedge aclk);rst=0;
 // Full-scale jumps exercise the maximum 128-clock line, below the 1024-clock sample budget.
 for(n=0;n<560;n=n+1) tick(n[0] ? 32767 : -32768);
 if(dut.state!=3 || ready)$fatal(1,"XY publish must wait for vertical blank");
 swap;if(!ready)$fatal(1,"XY frame was not published");bank=dut.read_bank;
 for(n=0;n<40;n=n+1) tick(0);
 if(dut.read_bank!=bank)$fatal(1,"XY bank changed during active frame");
 // Reset both domains and feed a quarter-cycle delay: sine must form a circle.
 rst=1;repeat(5)@(negedge aclk);rst=0;
 for(n=0;n<560;n=n+1) tick($rtoi(28000.0*$sin(6.28318530718*n/128.0)));
 if(dut.state!=3)$fatal(1,"XY rasterizer missed its sample budget");swap;
 on_pixels=0;
 for(n=0;n<16384;n=n+1) begin
   @(negedge pclk);address=n;@(negedge pclk);
   if(value)on_pixels=on_pixels+1;
 end
 if(on_pixels<250 || on_pixels>600)$fatal(1,"Unexpected connected-circle population %0d",on_pixels);
 // Probe independently computed sine/delayed-sine coordinates.
 for(n=0;n<128;n=n+1) begin
   tx=($rtoi(28000.0*$sin(6.28318530718*n/128.0))>>>9)+64;
   ty=127-(($rtoi(28000.0*$sin(6.28318530718*(n-32)/128.0))>>>9)+64);
   @(negedge pclk);address=ty*128+tx;@(negedge pclk);
   if(!value)$fatal(1,"XY omitted actual PCM point %0d,%0d",tx,ty);
 end
 // Next silent bank must clear the old circle completely.
 // One transitional frame legitimately contains the last 32 delayed samples.
 for(n=0;n<560;n=n+1)tick(0);swap;
 for(n=0;n<560;n=n+1)tick(0);swap;on_pixels=0;
 for(n=0;n<16384;n=n+1)begin
   @(negedge pclk);address=n;@(negedge pclk);if(value)on_pixels=on_pixels+1;
 end
 if(on_pixels!=1)$fatal(1,"Silence retained stale XY trail: %0d pixels",on_pixels);
 $display("PASS: PCM delay, connected circle, full-scale jumps, blank-only ownership, reset and silence clear");
 $display("ALL TESTS PASSED");$finish;
 end
 initial begin #60000000;$fatal(1,"XY watchdog");end
endmodule
