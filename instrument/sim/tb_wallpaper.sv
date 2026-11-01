`timescale 1ns/1ps
module tb_wallpaper;
 GSR GSR(.GSRI(1'b1));
 reg clk=0;always #12.5 clk=~clk;
 reg rst=1,blank=0;reg [10:0] x=0;reg [9:0] y=0;
 wire [23:0] rgb;wire [2:0] image_index;
 reg [23:0] expected[0:153599];integer page,n;
 wallpaper_renderer #(.HOLD_FRAMES(2)) dut(.clk(clk),.rst(rst),.vertical_blank(blank),.x(x),.y(y),.rgb(rgb),.image_index(image_index));
 task pulse;begin @(negedge clk);blank=1;@(negedge clk);blank=0;end endtask
 initial begin
 $readmemh("../../outputs/ui-20261101/wallpapers/expected.hex",expected);
 repeat(5)@(negedge clk);rst=0;
 for(page=0;page<8;page=page+1) begin
   if(image_index!=page)$fatal(1,"Wallpaper rotation index mismatch");
   for(n=0;n<19200;n=n+1)begin
     // Last pixel in each 5x5 tile also proves the reciprocal address arithmetic.
     x=(n%160)*5+4;y=(n/160)*5+4;repeat(3)@(negedge clk);
     if(rgb!==expected[page*19200+n])begin
       $display("addr=%h sx=%d sy=%d data=%h index=%h init=%h memory=%h",dut.word_address,dut.sx,dut.sy,dut.rom.image_0_data,dut.rom.colour_index,dut.rom.image_0.INIT_RAM_00[17:0],dut.rom.image_0.ram_MEM[17:0]);
       $fatal(1,"ROM page=%0d tile=%0d got=%h expected=%h",page,n,rgb,expected[page*19200+n]);
     end
   end
   pulse;if(image_index!=page)$fatal(1,"Wallpaper changed before hold period");
   pulse;
 end
 if(image_index!=0)$fatal(1,"Wallpaper failed to wrap");
 rst=1;@(negedge clk);if(image_index!=0)$fatal(1,"Wallpaper reset");
 $display("PASS: all 153600 palette pixels, all eight images, 5x scaling edges, frame hold and wrap");
 $display("ALL TESTS PASSED");$finish;
 end
endmodule
