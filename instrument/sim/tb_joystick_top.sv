`timescale 1ns/1ps
// Full top wiring and Gowin primitive models; accelerated analysis sample/blank
// enables only. Real publication timing is separately covered by tb_scope_link.
module tb_joystick_top;
 reg sw=1,joysw=1,jvalid=0;reg [11:0] jmv=1650;
 GSR GSR(.GSRI(1'b1));
 reg ref_clk=0;always #10 ref_clk=~ref_clk;
 tri1 scl,sda,scl_b,sda_b,pressure_scl,pressure_sda;
 wire bck,lrck,din;wire [7:0] led;wire [2:0] p,n;wire cp,cn,hpd;
 instrument_top #(.ENABLE_JOYSTICK(1),.JOYSTICK_BUTTON_CLOCKS(12),.ENABLE_EC11(1),.EC11_FILTER_CLOCKS(4),.EC11_BUTTON_CLOCKS(12)) dut(.joystick_sw_n(joysw),.encoder_a(1'b1),.encoder_b(1'b1),.encoder_sw_n(sw),.ref_clk(ref_clk),.mpr_scl(scl),.mpr_sda(sda),.dac_bck(bck),.dac_lrck(lrck),
 .mpr_b_scl(scl_b),.mpr_b_sda(sda_b),.pressure_scl(pressure_scl),.pressure_sda(pressure_sda),
 .control_rx(1'b1),.control_tx(),.led_ser(),.led_srclk(),.led_rclk(),.led_oe_n(),
 .dac_din(din),.led(led),.tmds_p(p),.tmds_n(n),.tmds_clock_p(cp),.tmds_clock_n(cn),.hpd_en(hpd));
 integer scope_frames=0,fft_writes=0,i;
 reg [2:0] fast_divider=0;reg fast_sample_ce=0;
 reg [9:0] blank_divider=0;reg fast_blank=0;
 always @(posedge dut.clk) begin
 fast_divider<=fast_divider+1'b1;fast_sample_ce<=fast_divider==7;
 end
 always @(posedge dut.pixel_clk) begin
 blank_divider<=blank_divider+1'b1;fast_blank<=blank_divider==1023;
 end
 initial begin force dut.monitor_ce=fast_sample_ce;force dut.blank=fast_blank;end
 always @(posedge dut.clk) if(!dut.analyser_rst) begin
 if(dut.scope_ack) scope_frames=scope_frames+1;
 if(dut.visual_write) begin
 if(!dut.visual_write_address[9]) $fatal(1,"Legacy waveform leaked into compact spectrum bank");
 fft_writes=fft_writes+1;
 end
 end
 initial begin
 wait(!dut.analyser_rst && !dut.video_rst);
 $display("TOP: clocks ready at %t",$time);
 wait(dut.scope_ready && dut.visual_ready);repeat(4) @(negedge ref_clk);
 if(scope_frames<4 || fft_writes!=512) $fatal(1,"Independent top publications %d %d",scope_frames,fft_writes);
 if(dut.monitor_sample!==0 || hpd!==1) $fatal(1,"Idle audio / display enable");
 if(dut.pixel_levels!==104'd0) $fatal(1,"Idle voice levels not delivered through mailbox");
 for(i=0;i<512;i=i+1) begin
 if(dut.scope_memory.memory[{dut.scope_memory.read_bank,i[8:0]}]!==0) $fatal(1,"Top scope bank mapping");
 if(dut.visual_memory.memory[{dut.visual_memory.read_bank,i[8:0]}]!==0) $fatal(1,"Top spectrum bank mapping");
 end
 $display("TOP: spectrum/scope ready at %t",$time);
 // Exercise the core -> 348-bit mailbox -> renderer path with all 13 notes.
 // Only touch status is injected; the core envelope/audio clocks remain real.
 force dut.online=1'b1;force dut.chip_online=2'b11;
 force dut.touched={1'b0,5'h1f,4'b0,8'hff}; // X0, sharps, controls, white notes
 wait(dut.pixel_levels[7:0]>=32);repeat(50) @(negedge ref_clk);
 for(i=0;i<13;i=i+1)
 if(dut.pixel_levels[i*8+:8]<32) $fatal(1,"Top missing voice level %0d",i);
 wait(dut.screen.display_levels[103:96]>=32);
 if(dut.screen.gates!==13'h1fff) $fatal(1,"Main 13-key status lost in widened mailbox");
 $display("TOP: notes displayed at %t",$time);
 force dut.joystick_online=1'b1;force dut.joystick_sample_valid=jvalid;force dut.joystick_mv=jmv;
 // Align fresh ADC pulses to the actual core clock, not the pixel-domain wait.
 @(negedge dut.clk);
 repeat(8)begin jvalid=1;@(negedge dut.clk);jvalid=0;repeat(3)@(negedge dut.clk);end
 if(!dut.core.joystick_input.stick.armed)$fatal(1,"Neutral samples did not arm joystick");
 jmv=3000;jvalid=1;@(negedge dut.clk);jvalid=0;
 repeat(4)@(negedge dut.clk);
 if(dut.octave_select!==2)$fatal(1,"Joystick octave event lost");
 wait(dut.octave_select===2'd2);wait(dut.screen.display_octave===2'd2);
 if(dut.pixel_octave!==2'd2 || dut.core.vibrato) $fatal(1,"Joystick octave mailbox");
 if(dut.core.engine.steps[0]!==32'd23012828) $fatal(1,"Held note retuned");
 joysw=0;repeat(40)@(negedge ref_clk);
 if(!dut.core.vibrato)$fatal(1,"Joystick switch integration");
 joysw=1;repeat(40)@(negedge ref_clk);
 if(dut.core.vibrato)$fatal(1,"Joystick release integration");
 $display("TOP: joystick octave and vibrato passed at %t",$time);
 force dut.pressure_online=1'b1;force dut.pressure_mv=12'd0;force dut.pressure_sample_valid=1'b1;
 repeat(400000)@(negedge ref_clk);
 if(dut.core.pressure_gain!==128 || dut.core.expressive_volume!==512)$fatal(1,"Pressure expression integration");
 release dut.pressure_online;release dut.pressure_mv;release dut.pressure_sample_valid;
 $display("TOP: pressure ramp passed at %t",$time);
 // Verify the EC11 state crosses the coherent mailbox into real raster text.
 repeat(80) @(negedge ref_clk);sw=0;repeat(30) @(negedge ref_clk);
 sw=1;repeat(30) @(negedge ref_clk);
 wait(dut.pixel_sustain=={1'b1,5'd3});
 wait(dut.screen.display_sustain=={1'b1,5'd3});
 force dut.x=11'd28;force dut.y=10'd568;repeat(8)@(negedge ref_clk);
 if(dut.screen.character!=="E")$fatal(1,"EC11 footer missing");
 force dut.x=11'd736;repeat(8)@(negedge ref_clk);
 if(dut.screen.character!=="M")$fatal(1,"Joystick footer final character missing");
 release dut.x;release dut.y;
 release dut.online;release dut.chip_online;release dut.touched;
 $display("PASS: full primitive-backed top, %0d scope frames before first FFT, compact banks, idle PCM and 13 voice levels",scope_frames);
 $display("ALL TESTS PASSED");$finish;
 end
 initial begin #20000000;$fatal(1,"Top watchdog");end
endmodule
