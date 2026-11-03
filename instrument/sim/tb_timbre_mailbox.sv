`timescale 1ns/1ps
// Real UART command -> core -> asynchronous status mailbox -> raster label.
module tb_timbre_mailbox;
 GSR GSR(.GSRI(1'b1));
 reg ref_clk=0;always #10 ref_clk=~ref_clk;
 reg rx=1;reg [17:0] local_touch=0;
 tri1 scl,sda,scl_b,sda_b,pressure_scl,pressure_sda;
 instrument_top #(.ENABLE_EXPRESSION(1),.ENABLE_JOYSTICK(1),.ENABLE_EC11(1)) dut(
 .ref_clk(ref_clk),.encoder_a(1'b1),.encoder_b(1'b1),.encoder_sw_n(1'b1),.joystick_sw_n(1'b1),
 .mpr_scl(scl),.mpr_sda(sda),.mpr_b_scl(scl_b),.mpr_b_sda(sda_b),
 .pressure_scl(pressure_scl),.pressure_sda(pressure_sda),.control_rx(rx));
 defparam dut.core.remote_control.CLOCKS_PER_BIT=8;
 defparam dut.core.metronome.controls.HOLD_SAMPLES=4;
 defparam dut.core.metronome.controls.REPEAT_SAMPLES=3;
 reg [9:0] blank_count=0;reg blank=0;
 always @(posedge dut.pixel_clk)begin blank_count<=blank_count+1'b1;blank<=blank_count==1023;end
 task byte_in(input [7:0] b);
 integer k;
 begin
 @(negedge dut.clk);rx=0;repeat(8)@(negedge dut.clk);
 for(k=0;k<8;k=k+1)begin rx=b[k];repeat(8)@(negedge dut.clk);end
 rx=1;repeat(8)@(negedge dut.clk);
 end endtask
 integer tone;reg [7:0] first_letter;
 initial begin
 force dut.blank=blank;
 wait(!dut.analyser_rst && !dut.video_rst);
 force dut.online=1'b1;force dut.chip_online=2'b11;force dut.touched=local_touch;
 force dut.x=11'd476;force dut.y=10'd24;
 for(tone=0;tone<8;tone=tone+1)begin
   byte_in("T");byte_in(8'd48+tone);byte_in(10);
   repeat(4000)@(negedge dut.pixel_clk);
   case(tone)
   0:first_letter="S";1:first_letter="E";2:first_letter="S";3:first_letter="M";
   4:first_letter="F";5:first_letter="O";6:first_letter="P";7:first_letter="B";
   endcase
   if(dut.core.timbre!==tone || dut.screen.timbre!==tone)
     $fatal(1,"Preset %0d truncated across core/mailbox/screen",tone);
   if(dut.screen.character!==first_letter)$fatal(1,"Wrong live preset label %0d",tone);
   if(dut.pixel_performance[31:26]!==0 || dut.screen.online!==1)
     $fatal(1,"New bank bit corrupted existing status fields");
 end
 byte_in("T");byte_in("8");byte_in(10);repeat(1000)@(negedge dut.clk);
 if(dut.core.timbre!=7 || dut.core.rejected!=1)$fatal(1,"Invalid preset changed state");
 local_touch=18'h20800;repeat(12)@(negedge dut.dac_lrck);local_touch=0;
 repeat(4000)@(negedge dut.pixel_clk);
 if(!dut.screen.metro_enabled || dut.pixel_metronome[17:10]!=120)$fatal(1,"Enabled/BPM CDC");
 local_touch=18'h20100;repeat(12)@(negedge dut.dac_lrck);local_touch=0;
 repeat(4000)@(negedge dut.pixel_clk);
 if(dut.screen.metro_meter!=4 || dut.screen.metro_beats!=6)$fatal(1,"Meter CDC");
 force dut.x=11'd208;force dut.y=10'd444;repeat(8)@(negedge dut.pixel_clk);
 if(dut.screen.character!="6")$fatal(1,"Live 6/8 label");
 local_touch=18'h20400;repeat(12)@(negedge dut.dac_lrck);local_touch=0;
 repeat(4000)@(negedge dut.pixel_clk);
 if(dut.pixel_metronome[17:10]<=120 || dut.screen.display_metronome[17:10]!=dut.core.metro_bpm)$fatal(1,"Adjusted BPM CDC");
 if(dut.core.timbre!=7 || dut.core.volume!=2048)$fatal(1,"Meter/BPM chord leaked");
 $display("PASS: local metronome enable/meter/BPM propagate through actual CDC and raster");
 $display("PASS: all 8 UART presets cross the full 707-bit mailbox into actual raster labels; T8 rejected");
 $display("ALL TESTS PASSED");$finish;
 end
 initial begin #20000000;$fatal(1,"Preset mailbox watchdog");end
endmodule
