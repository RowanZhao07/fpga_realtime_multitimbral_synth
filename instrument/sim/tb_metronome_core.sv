`timescale 1ns/1ps
// Real 50 MHz / I2S integration: clicks and instrument share both DAC channels.
module tb_metronome_core;
 reg clk=0;always #10 clk=~clk;
 reg rst=1,rx=1;reg [17:0] touched=0;
 wire bck,lrck,din,ce;wire signed [15:0] pcm;wire [17:0] info;
 instrument_core #(.ENABLE_EXPRESSION(1),.ENABLE_JOYSTICK(1),.DEFAULT_TIMBRE(1),.UART_CLOCKS_PER_BIT(8)) dut(
 .clk(clk),.rst(rst),.online(1'b1),.chip_online(2'b11),.touched(touched),
 .joystick_online(1'b0),.joystick_sample_valid(1'b0),.joystick_mv(12'd0),.joystick_sw_n(1'b1),
 .y_online(1'b0),.y_sample_valid(1'b0),.y_mv(12'd0),
 .pressure_online(1'b1),.pressure_sample_valid(1'b1),.pressure_mv(12'd0),
 .encoder_a(1'b1),.encoder_b(1'b1),.encoder_sw_n(1'b1),.sustain_request(1'b0),.control_rx(rx),
 .dac_bck(bck),.dac_lrck(lrck),.dac_din(din),.monitor_sample(pcm),.monitor_ce(ce),.metronome_info(info));
 defparam dut.metronome.controls.HOLD_SAMPLES=4;
 defparam dut.metronome.controls.REPEAT_SAMPLES=3;
 integer k,checked=0,peak=0;reg [15:0] expected;reg [31:0] lword,rword;
 always @(posedge clk) if(!rst && ce) begin
   if(dut.engine_overrun || (^pcm)===1'bx)$fatal(1,"Audio overrun/unknown");
   if(!dut.metro_enabled && dut.click_sample==0 && pcm!==dut.tone_sample)$fatal(1,"OFF must be bit-exact bypass");
   if(dut.click_sample>peak)peak=dut.click_sample;
 end
 initial forever begin
   @(negedge lrck);
   if(!rst)begin
     expected=pcm;@(posedge bck);lword=0;rword=0;
     for(k=0;k<32;k=k+1)begin @(posedge bck);lword={lword[30:0],din};end
     for(k=0;k<31;k=k+1)begin @(posedge bck);rword={rword[30:0],din};end
     rword={rword[30:0],1'b0};
     if(lword!=={expected,16'd0} || rword!=={expected,16'd0})$fatal(1,"Metronome stereo I2S mismatch");
     checked=checked+1;
   end
 end
 task frames(input integer n);begin repeat(n)@(negedge lrck);@(negedge clk);end endtask
 task byte_in(input [7:0] b);integer i;begin
   rx=0;repeat(8)@(negedge clk);for(i=0;i<8;i=i+1)begin rx=b[i];repeat(8)@(negedge clk);end
   rx=1;repeat(8)@(negedge clk);
 end endtask
 task command(input string s);integer i;begin for(i=0;i<s.len();i=i+1)byte_in(s[i]);byte_in(10);repeat(100)@(negedge clk);end endtask
 initial begin
 repeat(5)@(negedge clk);rst=0;frames(2200);
 if(info[17:7]!={8'd120,3'd3} || info[3] || pcm!=0)$fatal(1,"Default status/silence");
 touched=18'h20800;frames(12);if(!info[3] || dut.vibrato || dut.y_enabled)$fatal(1,"Local enable");
 touched=0;frames(800);if(peak<3600 || peak>7500)$fatal(1,"Zero pressure incorrectly muted metronome %0d",peak);
 touched=18'h20100;frames(12);touched=0;frames(4);
 if(info[9:7]!=4 || dut.timbre!=1 || dut.effect_mode!=0)$fatal(1,"Meter conflicts with tone/effects");
 touched=18'h20401;frames(12);touched=1;frames(4);
 if(info[17:10]<=120 || dut.volume!=2048 || dut.voice_count==0)$fatal(1,"Live BPM/note/gain conflict");
 command("F2");frames(800);
 if(dut.effect_mode!=2 || dut.voice_count==0)$fatal(1,"Concurrent instrument/reverb");
 command("V0");frames(2400);if(pcm!=0)$fatal(1,"Master mute must mute metronome too");
 touched=18'h20801;frames(12);touched=0;frames(300);
 if(info[3] || dut.click_sample!=0)$fatal(1,"Local disable tail");
 command("V2048");touched=1;frames(2200);if(pcm===16'd0)$fatal(1,"Instrument remains playable");
 // Explicit full-scale sum boundaries: no signed wrap when click and note add.
 force dut.tone_sample=16'sd30000;force dut.click_sample=16'sd10000;frames(3);
 if(pcm!==16'sh7fff || !dut.click_clipped)$fatal(1,"Positive mixed saturation");
 force dut.tone_sample=-16'sd30000;force dut.click_sample=-16'sd10000;frames(3);
 if(pcm!==16'sh8000 || !dut.click_clipped)$fatal(1,"Negative mixed saturation");
 force dut.tone_sample=16'sd30000;force dut.click_sample=-16'sd10000;frames(3);
 if(pcm!==16'sd20000 || dut.click_clipped)$fatal(1,"Unclipped opposite signs");
 release dut.tone_sample;release dut.click_sample;frames(3);
 if(checked<8000)$fatal(1,"Insufficient serialized coverage");
 $display("ALL TESTS PASSED: %0d stereo I2S frames, independent pressure/effects, master mute, local controls, OFF exact bypass",checked);$finish;
 end
 initial begin #300000000;$fatal(1,"Metronome integration watchdog");end
endmodule
