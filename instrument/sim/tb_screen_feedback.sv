`timescale 1ns/1ps
module tb_screen_feedback;
 reg clk=0;always #12.5 clk=~clk;
 reg rst=1,blank=0,de=1;reg [10:0] x=0;reg [9:0] y=0;
 reg [39:0] status=0;reg [63:0] levels=0;
 reg [7:0] scope=0,scope_source=0;
 always @(posedge clk) scope<=scope_source;wire [23:0] rgb;
 instrument_screen dut(.clk(clk),.rst(rst),.x(x),.y(y),.de(de),.hs(1'b0),.vs(1'b0),
 .vertical_blank(blank),.status(status),.voice_levels(levels),.scope_ready(1'b1),.scope_data(scope),
 .scope_address(),.visual_ready(1'b0),.visual_data(8'd0),.visual_address(),
 .rgb(rgb),.out_de(),.out_hs(),.out_vs());
 task latch;
 begin @(negedge clk);blank=1;@(negedge clk);blank=0; end endtask
 task pixel(input integer xx,yy,input [23:0] expected);
 begin @(negedge clk);x=xx;y=yy;repeat(3) @(negedge clk);
 if(rgb!==expected) $fatal(1,"Pixel %d,%d got %h expected %h",xx,yy,rgb,expected);end endtask
 initial begin
 repeat(3) @(negedge clk);rst=0;
 status[7:0]=1;status[15:8]=3;levels[15:8]=200;levels[7:0]=255;latch;
 pixel(40,94,24'h20A890); // held
 pixel(104,94,24'h20489B); // release tail
 pixel(168,94,24'h25374B); // idle
 pixel(64,94,24'h20A890); // no spurious divider at key center
 pixel(95,94,24'h0B1220);pixel(96,94,24'h0B1220);
 pixel(40,116,24'h48E0C0); // actual envelope meter
 levels[15:8]=20;pixel(104,94,24'h20489B); // changes only at frame boundary
 latch;pixel(104,94,24'h204841);
 status[15:8]=1;latch;pixel(104,94,24'h25374B);
 status[27]=1;status[30:28]=2;latch;pixel(168,90,24'hF2BE55);
 scope_source=90;pixel(40,180,24'h48E0C0);scope_source=-8'sd90;pixel(40,360,24'h48E0C0);
 // Check the bridge between two steep neighbouring samples after pipeline fill.
 @(negedge clk);x=40;y=250;scope_source=90;repeat(3) @(negedge clk);
 x=41;scope_source=-8'sd90;@(negedge clk);@(negedge clk);
 if(rgb!==24'h48E0C0) $fatal(1,"Steep trace disconnected");
 $display("PASS: held/tail/idle keys, relative borders, ADSR meter, frame latch, guide overlay, signed connected trace");
 $display("ALL TESTS PASSED");$finish;
 end
 initial begin #1000000;$fatal(1,"Screen watchdog");end
endmodule
