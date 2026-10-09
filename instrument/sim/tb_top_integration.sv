`timescale 1ns/1ps
// Full top wiring and Gowin primitive models; accelerated analysis sample/blank
// enables only. Real publication timing is separately covered by tb_scope_link.
module tb_top_integration;
 GSR GSR(.GSRI(1'b1));
 reg ref_clk=0;always #10 ref_clk=~ref_clk;
 tri1 scl,sda;wire bck,lrck,din;wire [7:0] led;wire [2:0] p,n;wire cp,cn,hpd;
 instrument_top dut(.ref_clk(ref_clk),.mpr_scl(scl),.mpr_sda(sda),.dac_bck(bck),.dac_lrck(lrck),
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
 if(dut.latest_valid!==0) $fatal(1,"Unimplemented algorithm produced a result");
 for(i=0;i<512;i=i+1) begin
 if(dut.scope_memory.memory[{dut.scope_memory.read_bank,i[8:0]}]!==0) $fatal(1,"Top scope bank mapping");
 if(dut.visual_memory.memory[{dut.visual_memory.read_bank,i[8:0]}]!==0) $fatal(1,"Top spectrum bank mapping");
 end
 $display("PASS: full primitive-backed top, %0d scope frames before first FFT, compact banks, idle PCM, inactive result port",scope_frames);
 $display("ALL TESTS PASSED");$finish;
 end
 initial begin #200000000;$fatal(1,"Top watchdog");end
endmodule
