`timescale 1ns/1ps
// Synthetic display fixture; not measured hardware results.
module tb_touch_isolation_screen;
 reg clk=0;always #12.5 clk=~clk;
 reg rst=1,blank=0;reg [10:0] x=0;reg [9:0] y=0;
 reg [279:0] info=0;reg [203:0] status=0;wire [23:0] rgb;
 instrument_screen #(.TOUCH_ISOLATION(1),.ENABLE_EXPRESSION(1)) dut(
 .clk(clk),.rst(rst),.x(x),.y(y),.de(1'b1),.hs(1'b0),.vs(1'b0),.vertical_blank(blank),
 .isolation_status(info),.status(status),.performance_info(32'd0),.voice_levels(104'd0),.octave_select(2'd1),
 .sustain_info(6'd0),.wiring_status(60'd0),.scope_ready(1'b0),.scope_data(8'd0),.visual_ready(1'b0),.visual_data(8'd0),.rgb(rgb));
 task latch;begin blank=1;@(negedge clk);blank=0;repeat(5)@(negedge clk);end endtask
 task character_at(input integer xx,yy,input [7:0] expected);
 begin x=xx;y=yy;repeat(5)@(negedge clk);if(dut.character!==expected)$fatal(1,"Isolation label %d,%d got %h expected %h",xx,yy,dut.character,expected);end endtask
 integer n,f;
 initial begin
 repeat(4)@(negedge clk);rst=0;
 status[51:50]=3;status[65]=1;info[247:240]=1;info[226:224]=2;info[231:227]=20;
 info[0*32+28]=1;info[0*32+26]=1;info[0*32+27]=1;
 latch;character_at(28,24,"T");character_at(28,52,"A");character_at(280,52,"M");
 character_at(196,144,"F");character_at(196,188,"-");character_at(652,188,"D");
 for(n=0;n<7;n++)begin info[n*32+28]=1;info[n*32+26]=1;info[n*32+27]=1;end
 info[2*32+8 +: 8]=7;info[2*32+20 +: 4]=1;info[2*32+25]=1;
 info[5*32 +: 8]=12;info[5*32+16 +: 4]=2;info[5*32+24]=1;
 info[226:224]=6;info[231:227]=0;info[232]=1;info[271:264]=17;
 latch;character_at(520,24,"D");character_at(556,52,"F");
 character_at(420,232,"F");character_at(456,232,"7");character_at(492,232,"1");
 character_at(196,364,"F");character_at(220,364,"1");character_at(232,364,"2");
 character_at(28,552,"D");
 f=$fopen("screen_touch_isolation.ppm","w");$fdisplay(f,"P3\n800 600\n255");
 for(n=0;n<480003;n++)begin
 if(n>=3)$fdisplay(f,"%0d %0d %0d",rgb[23:16],rgb[15:8],rgb[7:0]);
 x=n%800;y=n/800;@(negedge clk);
 end
 $fclose(f);
 $display("PASS: waiting/finished windows, independent A/B failure/error text, reset count and full raster");
 $display("ALL TESTS PASSED");$finish;
 end
endmodule
