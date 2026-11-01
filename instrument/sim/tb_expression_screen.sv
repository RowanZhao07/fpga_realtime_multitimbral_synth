`timescale 1ns/1ps
// A deterministic display fixture, not a photograph or a live measurement.
module tb_expression_screen;
 GSR GSR(.GSRI(1'b1));
 reg clk=0;always #12.5 clk=~clk;
 reg audio_clk=0;always #10 audio_clk=~audio_clk;
 reg [9:0] audio_div=0;reg [6:0] phase=0;
 wire audio_ce=audio_div==0;
 reg signed [15:0] audio_sample=0;
 always @(posedge audio_clk) begin
   audio_div<=audio_div+1'b1;
   if(audio_ce) begin phase<=phase+1'b1;audio_sample<=$rtoi(10000.0*$sin(6.28318530718*phase/128.0));end
 end
 reg rst=1,blank=0;reg [10:0] x=0;reg [9:0] y=0;
 reg [203:0] status=0;reg [31:0] perf=0;reg [59:0] wiring=0;
 wire [23:0] rgb;
 wire liss_ready,liss_data;wire [13:0] liss_address;wire [8:0] scope_address;
 wire [9:0] visual_address;reg [7:0] spectrum_data=0;
 reg [7:0] scope_data=0;
 reg signed [15:0] scope_sample=0;
 wire signed [15:0] scope_scaled,xy_scaled;
 always @* scope_sample=$rtoi(10000.0*$sin(6.28318530718*scope_address/128.0));
 display_gain scope_zoom(.sample(scope_sample),.scaled(scope_scaled));
 display_gain xy_zoom(.sample(audio_sample),.scaled(xy_scaled));
 always @(posedge clk) scope_data<=scope_scaled>>>8;
 // A matching bin-32 Hann-window display fixture, not a measured FFT export.
 always @(posedge clk) case(visual_address[8:0])
   31,33:spectrum_data<=132;32:spectrum_data<=150;default:spectrum_data<=0;
 endcase
 lissajous_capture xy(.audio_clk(audio_clk),.audio_rst(rst),.sample_ce(audio_ce),.sample(xy_scaled),
 .pixel_clk(clk),.pixel_rst(rst),.vertical_blank(blank),.read_address(liss_address),
 .read_value(liss_data),.ready(liss_ready));
 instrument_screen #(.ENABLE_EXPRESSION(1),.ENABLE_JOYSTICK(1),.ENABLE_EC11(1)) dut(
 .clk(clk),.rst(rst),.x(x),.y(y),.de(1'b1),.hs(1'b0),.vs(1'b0),.vertical_blank(blank),
 .status(status),.performance_info(perf),.voice_levels({13{8'd160}}),.octave_select(2'd1),
 .sustain_info({1'b1,5'd3}),.wiring_status(wiring),.scope_ready(1'b1),.scope_data(scope_data),.scope_address(scope_address),
 .liss_ready(liss_ready),.liss_data(liss_data),.liss_address(liss_address),
 .visual_ready(1'b1),.visual_data(spectrum_data),.visual_address(visual_address),.rgb(rgb));
 task latch;begin blank=1;@(negedge clk);blank=0;repeat(4)@(negedge clk);end endtask
 task character_at(input integer xx,yy,input [7:0] expected);
 begin x=xx;y=yy;repeat(5)@(negedge clk);if(dut.character!==expected)$fatal(1,"Expression label %d,%d got %h expected %h",xx,yy,dut.character,expected);end endtask
 integer f,n,wallpaper;
 initial begin
 repeat(4)@(negedge clk);rst=0;
 // Fill a real XY bank from PCM; the displayed circle is not a painted mockup.
 wait(xy.state==3);repeat(5)@(negedge clk);
 status[23]=1;status[51:50]=3;status[65]=1;status[64:53]=2100;
 status[22:18]=8;status[17:16]=0;status[7:0]=1;status[15:8]=1;status[24]=1;
 status[86:79]=93;perf={6'd1,10'd76,9'd0,7'd0};latch;
 character_at(612,296,"O");character_at(684,356,"F");
 perf[3:2]=1;latch;character_at(612,296,"D");
 perf[3:2]=2;latch;character_at(612,296,"R");
 perf[3:2]=3;latch;character_at(612,296,"C");
 perf[0]=1;latch;character_at(600,356,"C");
 perf[1]=1;latch;character_at(672,356,"N");
 character_at(436,568,"C");character_at(580,568,"X");character_at(736,568,"F");
 perf[3:2]=2;latch;
 character_at(256,204,"3");character_at(508,204,"3");character_at(736,24,"3");
 status[37]=1;latch;character_at(708,320,8'd32); // No LIMIT badge at any soft-knee duty.
 f=$fopen("screen_expression.ppm","w");$fdisplay(f,"P3\n800 600\n255");
 // Three registered pixel stages. Drain the same number after the last pixel.
 for(n=0;n<480003;n++)begin
 if(n>=3)begin
   if((^rgb)===1'bx)$fatal(1,"Unknown pixel in expression raster");
   if(dut.text_pixel && !dut.panel_inner)$fatal(1,"Expression text outside panel");
   $fdisplay(f,"%0d %0d %0d",rgb[23:16],rgb[15:8],rgb[7:0]);
 end
 x=n%800;y=n/800;@(negedge clk);
 end
 $fclose(f);
 // A remains online while B NACKs. Show evidence without a touch command.
 status[23]=0;status[51:50]=1;
 wiring[15:0]={1'b0,3'b111,8'd0,4'd0};
 wiring[31:16]={1'b0,3'b111,8'd23,4'd1};latch;
 character_at(640,24,"E");character_at(712,24,"2");
 character_at(576,408,"T");character_at(576,432,"A");character_at(588,432,"1");
 character_at(576,480,"B");character_at(588,480,"0");character_at(624,480,"1");
 character_at(660,480,"0");character_at(672,480,"2");character_at(684,480,"3");
 character_at(576,500,"N");character_at(696,500,"1");character_at(732,500,"1");
 status[195]=1;latch;character_at(576,408,"T"); // Fault view overrides UART page.
 f=$fopen("screen_expression_offline.ppm","w");$fdisplay(f,"P3\n800 600\n255");
 for(n=0;n<480003;n++)begin
 if(n>=3)begin
   if((^rgb)===1'bx)$fatal(1,"Unknown pixel in offline raster");
   if(dut.text_pixel && !dut.panel_inner)$fatal(1,"Offline evidence outside panel");
   $fdisplay(f,"%0d %0d %0d",rgb[23:16],rgb[15:8],rgb[7:0]);
 end
 x=n%800;y=n/800;@(negedge clk);
 end
 $fclose(f);
 status[23]=1;status[51:50]=3;latch;character_at(576,408,"U");
 status[195]=0;latch;character_at(576,408,"G");
 // Review the same real raster against every restored wallpaper.
 for(wallpaper=2;wallpaper<=8;wallpaper=wallpaper+1) begin
   repeat(600)latch;
   f=$fopen($sformatf("screen_expression_wallpaper_%0d.ppm",wallpaper),"w");
   $fdisplay(f,"P3\n800 600\n255");
   for(n=0;n<480003;n=n+1)begin
     if(n>=3)begin
       if((^rgb)===1'bx)$fatal(1,"Unknown pixel after wallpaper rotation");
       if(dut.text_pixel && !dut.panel_inner)$fatal(1,"Rotated wallpaper text outside panel");
       $fdisplay(f,"%0d %0d %0d",rgb[23:16],rgb[15:8],rgb[7:0]);
     end
     x=n%800;y=n/800;@(negedge clk);
   end
   $fclose(f);
 end
 $display("PASS: FX/Y controls, full online/offline raster, live fault/count/idle text and page recovery");
 $display("ALL TESTS PASSED");$finish;
 end
endmodule
