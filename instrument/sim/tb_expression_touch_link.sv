`timescale 1ns/1ps
// Full playing top with real bus transactions: no forced touch/online flags.
// Startup/backoff and display blank are accelerated; ADC/audio clocks are real.
module tb_expression_touch_link;
 GSR GSR(.GSRI(1'b1));
 reg ref_clk=0;always #10 ref_clk=~ref_clk;
 tri1 ascl,asda,bscl,bsda,cscl,csda;
 reg present_b=1,hold_b=0;
 assign bscl=hold_b ? 1'b0 : 1'bz;
 instrument_top #(.ENABLE_EXPRESSION(1),.ENABLE_JOYSTICK(1),.ENABLE_EC11(1)) dut(
 .ref_clk(ref_clk),.joystick_sw_n(1'b1),.encoder_a(1'b1),.encoder_b(1'b1),.encoder_sw_n(1'b1),
 .mpr_scl(ascl),.mpr_sda(asda),.mpr_b_scl(bscl),.mpr_b_sda(bsda),
 .pressure_scl(cscl),.pressure_sda(csda),.control_rx(1'b1));
 defparam dut.touch.POWER_WAIT=100,dut.touch.RESET_WAIT=100,dut.touch.RETRY_WAIT=5000,
          dut.touch.TIMEOUT=50000,dut.touch.QUARTER=8;
 defparam dut.shared_adc.adc.POWER_WAIT=100;
 mpr121_test_device a(.scl(ascl),.sda(asda),.present(1'b1));
 mpr121_test_device b(.scl(bscl),.sda(bsda),.present(present_b));
 shared_ads1115_test_device adc(.scl(cscl),.sda(csda),.present(1'b1),.bad_config(1'b0),
 .conversion0(16'd25880),.conversion1(16'd13200),.conversion2(16'd13200),.hang_conversion(1'b0));
 reg [7:0] blank_count=0;wire fast_blank=blank_count==255;
 always @(posedge dut.pixel_clk)blank_count<=blank_count+1'b1;
 initial force dut.blank=fast_blank;
 integer samples=0,a_reads_before,adc_reads_before,nonzero=0;
 always @(posedge dut.clk)if(!dut.rst && dut.monitor_ce)begin
   samples=samples+1;if(dut.monitor_sample!=0)nonzero=nonzero+1;
   if(dut.core.rst || dut.core.engine_overrun)$fatal(1,"Full expression engine is reset/overrunning");
 end
 task ticks(input integer n);repeat(n)@(negedge dut.clk);endtask
 initial begin
 wait(!dut.rst && !dut.video_rst);
 wait(dut.online && dut.y_online);
 wait(dut.screen.online && dut.screen.adc_online);
 if(dut.chip_online!=3 || dut.screen.display_status[51:50]!=3 ||
    dut.screen.display_wiring[11:0]!=0 || dut.screen.display_wiring[27:16]!=0)
   $fatal(1,"Healthy bus state not delivered to playing screen");
 a.registers[0]=1;wait(dut.core.gates[0]);wait(nonzero>5);
 if(samples<10)$fatal(1,"Audio workload inactive");
 $display("PASS: physical-bus model -> full expression engine -> nonzero PCM and ONLINE HDMI state");
 a_reads_before=a.reads;adc_reads_before=adc.conversion_reads;present_b=0;
 wait(!dut.online);wait(dut.screen.touch_fault_visible);
 wait(dut.screen.display_wiring[19:16]==1);
 ticks(200000);
 if(!dut.chip_online[0] || !dut.pressure_online || dut.core.gates!=0 ||
    dut.screen.display_status[51:50]!=1 || dut.screen.display_wiring[27:20]==0 ||
    a.reads<=a_reads_before || adc.conversion_reads<=adc_reads_before)
   $fatal(1,"B NACK not isolated/reported while other buses and DSP run");
 present_b=1;wait(dut.online);wait(!dut.screen.touch_fault_visible);
 if(dut.screen.display_wiring[19:16]!=1)$fatal(1,"Recovery lost sticky fault history");
 $display("PASS: B NACK reaches live fault card, releases gates, A/ADC keep polling, automatic recovery");
 wait(!b.transaction && !dut.touch.bank_b.busy);@(negedge dut.clk);hold_b=1;
 wait(!dut.online);wait(dut.screen.display_wiring[19:16]==2);
 wait(dut.screen.display_wiring[30:28]==5);
 if(!dut.screen.touch_fault_visible || !dut.pressure_online || !dut.chip_online[0])
   $fatal(1,"SCL fault lost in expression profile");
 hold_b=0;wait(dut.online);wait(!dut.screen.touch_fault_visible);
 a.registers[1]=8'h80;wait(!dut.online);
 wait(dut.screen.display_wiring[3:0]==6);
 wait(dut.online);wait(!dut.screen.touch_fault_visible);
 $display("PASS: SCL-low and MPR overcurrent evidence/retry through full playing top; no forced status");
 $display("ALL TESTS PASSED");$finish;
 end
 initial begin #60000000;$fatal(1,"Playing touch link watchdog");end
endmodule
