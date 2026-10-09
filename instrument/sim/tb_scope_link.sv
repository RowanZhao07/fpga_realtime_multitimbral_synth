`timescale 1ns/1ps
// Real board sample/raster clocks: check frame integrity and sustained publication.
module tb_scope_link;
 reg clk=0,pclk=0;always #10 clk=~clk;always #12.5 pclk=~pclk;
 reg rst=1;reg [9:0] divider=0;reg [31:0] sample_number=0;
 wire ce=divider==1023 && !rst;
 wire signed [15:0] pcm=$signed({1'b0,sample_number[6:0],8'b0})-16'sd16384;
 always @(posedge clk) if(rst) begin divider<=0;sample_number<=0;end
 else begin divider<=divider+1'b1;if(ce) sample_number<=sample_number+1'b1;end
 wire we,done,ack,ready;wire [8:0] wa;wire [7:0] wd,rd;reg [8:0] ra=0;
 wire [10:0] x;wire [9:0] y;wire de,hs,vs,blank;
 video_timing timing(.clk(pclk),.rst(rst),.x(x),.y(y),.de(de),.hs(hs),.vs(vs),.vertical_blank(blank));
 waveform_capture capture(.clk(clk),.rst(rst),.sample_ce(ce),.sample(pcm),.write_enable(we),
 .write_address(wa),.write_value(wd),.frame_done(done),.frame_ack(ack));
 visual_buffer #(.ADDRESS_BITS(9)) memory(.audio_clk(clk),.audio_rst(rst),.write_enable(we),
 .write_address(wa),.write_value(wd),.frame_done(done),.frame_ack(ack),.pixel_clk(pclk),.pixel_rst(rst),
 .vertical_blank(blank),.read_address(ra),.read_value(rd),.ready(ready));
 reg [7:0] expected[0:511],published[0:511];integer written=0,frames=0,i;time last_ack=0,delta;
 always @(posedge clk) if(we) begin
 if(wa!==written[8:0]) $fatal(1,"Scope link write address");
 expected[wa]=wd;written=written+1;
 end
 initial begin
 repeat(4) @(negedge clk);rst=0;
 repeat(4) begin
 wait(ack);if(written!=512 || !ready) $fatal(1,"Incomplete published scope");
 if(last_ack!=0) begin delta=$time-last_ack;
 if(delta<16579000 || delta>16580000) $fatal(1,"Missed 60 Hz scope publication: %d ns",delta);
 $display("PASS: independent scope publication interval %0d ns",delta);end
 last_ack=$time;frames=frames+1;
 for(i=0;i<512;i=i+1) published[i]=expected[i];written=0;
 // Read a complete bank while the other bank is already collecting next frame.
 for(i=0;i<512;i=i+1) begin
 @(negedge pclk);ra=i;@(negedge pclk);
 if(rd!==published[i]) $fatal(1,"Torn/signed frame at %d",i);
 end
 wait(!done);
 end
 $display("PASS: four coherent independent waveform frames at real 48828.125 Hz PCM / 800x600 raster clocks");
 $display("ALL TESTS PASSED");$finish;
 end
 initial begin #100000000;$fatal(1,"Scope link watchdog");end
endmodule
