`timescale 1ns/1ps
// Full top wiring and Gowin primitive models; accelerated analysis sample/blank
// enables only. Real publication timing is separately covered by tb_scope_link.
module tb_top_integration;
 GSR GSR(.GSRI(1'b1));
 reg ref_clk=0;always #10 ref_clk=~ref_clk;
 tri1 scl,sda,scl_b,sda_b,pressure_scl,pressure_sda;
 wire bck,lrck,din;wire [7:0] led;wire [2:0] p,n;wire cp,cn,hpd;
 instrument_top dut(.encoder_a(1'b1),.encoder_b(1'b1),.encoder_sw_n(1'b1),.ref_clk(ref_clk),.mpr_scl(scl),.mpr_sda(sda),.dac_bck(bck),.dac_lrck(lrck),
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
 wait(dut.scope_ready && dut.visual_ready);repeat(4) @(negedge ref_clk);
 if(scope_frames<4 || fft_writes!=512) $fatal(1,"Independent top publications %d %d",scope_frames,fft_writes);
 if(dut.monitor_sample!==0 || hpd!==1) $fatal(1,"Idle audio / display enable");
 if(dut.pixel_levels!==104'd0) $fatal(1,"Idle voice levels not delivered through mailbox");
 for(i=0;i<512;i=i+1) begin
 if(dut.scope_memory.memory[{dut.scope_memory.read_bank,i[8:0]}]!==0) $fatal(1,"Top scope bank mapping");
 if(dut.visual_memory.memory[{dut.visual_memory.read_bank,i[8:0]}]!==0) $fatal(1,"Top spectrum bank mapping");
 end
 // Exercise the core -> 348-bit mailbox -> renderer path with all 13 notes.
 // Only touch status is injected; the core envelope/audio clocks remain real.
 force dut.online=1'b1;force dut.chip_online=2'b11;
 force dut.touched={1'b0,5'h1f,4'b0,8'hff}; // X0, sharps, controls, white notes
 wait(dut.pixel_levels[7:0]>=32);repeat(50) @(negedge ref_clk);
 for(i=0;i<13;i=i+1)
 if(dut.pixel_levels[i*8+:8]<32) $fatal(1,"Top missing voice level %0d",i);
 wait(dut.screen.display_levels[103:96]>=32);
 if(dut.screen.gates!==13'h1fff) $fatal(1,"Main 13-key status lost in widened mailbox");
 force dut.touched={1'b1,5'h1f,4'b1000,8'hff}; // X0+C3 selects octave 6.
 wait(dut.octave_select===2'd3);wait(dut.screen.display_octave===2'd3);
 if(dut.pixel_octave!==2'd3 || dut.core.vibrato) $fatal(1,"Octave mailbox/modifier wiring");
 if(dut.core.engine.steps[0]!==32'd23012828) $fatal(1,"Held note retuned by UI bank switch");
 if(dut.key_lights!==13'h1fff) $fatal(1,"X0 lamp check lost");
 release dut.online;release dut.chip_online;release dut.touched;
 $display("PASS: full primitive-backed top, %0d scope frames before first FFT, compact banks, idle PCM and 13 voice levels",scope_frames);
 $display("ALL TESTS PASSED");$finish;
 end
 initial begin #200000000;$fatal(1,"Top watchdog");end
endmodule
