`timescale 1ns/1ps
module tb_touch_isolation_control;
 reg clk=0;always #10 clk=~clk;
 reg rst=1;reg [1:0] online=3,event_bits=0;reg [3:0] ea=1,eb=2;
 wire cr,ir,vr,lr;wire [255:0] report;
 touch_isolation_control #(.SECOND_CLOCKS(100)) dut(.clk(clk),.rst(rst),.chip_online(online),
 .failure_event(event_bits),.error_a(ea),.error_b(eb),.core_run(cr),.i2s_run(ir),.visual_run(vr),.led_run(lr),.report(report));
 integer stage,count;reg [255:0] saved;
 task ticks(input integer n);repeat(n)@(negedge clk);endtask
 task flags(input [3:0] expected);if({cr,ir,vr,lr}!==expected)$fatal(1,"Stage flags %0d %b",dut.stage,{cr,ir,vr,lr});endtask
 initial begin
 ticks(3);rst=0;
 for(stage=0;stage<7;stage++)begin
 wait(dut.stage==stage);@(negedge clk);
 case(stage) 0,6:flags(4'b0001);1:flags(4'b1001);2:flags(4'b1101);3:flags(4'b1011);4:flags(4'b1110);5:flags(4'b1111);endcase
 // Warmup faults must be excluded from the scored window.
 event_bits=3;online=0;ticks(15);event_bits=0;online=3;
 wait(dut.seconds==2);ticks(3);
 if(dut.fail_a[stage]!=0 || dut.fail_b[stage]!=0 || dut.seen_down_a[stage])$fatal(1,"Settling leaked into result");
 event_bits=1;online=2;ticks(stage==1 ? 300 : stage+1);event_bits=0;online=3;ticks(2);
 event_bits=2;eb=stage;ticks(1);event_bits=0;ticks(2);
 if(dut.fail_a[stage]!=(stage==1 ? 255 : stage+1) || dut.fail_b[stage]!=1 || dut.last_b[stage]!=stage ||
 !dut.seen_up_a[stage] || !dut.seen_down_a[stage] || dut.seen_down_b[stage])$fatal(1,"Per-window records wrong");
 if(stage<6)wait(dut.stage!=stage);
 end
 wait(dut.finished);ticks(2);saved=report;
 event_bits=3;online=0;ticks(100);if(report!==saved)$fatal(1,"Final evidence not frozen");
 if(report[247:240]!=1)$fatal(1,"Boot counter");
 rst=1;ticks(3);rst=0;ticks(3);
 if(report[247:240]!=2 || dut.stage!=0 || dut.fail_a[1]!=0)$fatal(1,"Runtime reset evidence");
 $display("PASS: seven runtime modes, settle exclusion, bank isolation, saturation, frozen evidence and reset counter");
 $display("ALL TESTS PASSED");$finish;
 end
 initial begin #1000000;$fatal(1,"Control watchdog");end
endmodule

module tb_touch_isolation_top;
 GSR GSR(.GSRI(1'b1));
 reg ref_clk=0;always #10 ref_clk=~ref_clk;
 tri1 ascl,asda,bscl,bsda,cscl,csda;reg present_b=1;
 wire bck,lrck,din,oe;wire [7:0] leds;
 instrument_top #(.TOUCH_ISOLATION(1),.ENABLE_EXPRESSION(1),.ENABLE_JOYSTICK(1),.ENABLE_EC11(1)) dut(
 .ref_clk(ref_clk),.joystick_sw_n(1'b1),.encoder_a(1'b1),.encoder_b(1'b1),.encoder_sw_n(1'b1),
 .mpr_scl(ascl),.mpr_sda(asda),.mpr_b_scl(bscl),.mpr_b_sda(bsda),.pressure_scl(cscl),.pressure_sda(csda),
 .control_rx(1'b1),.dac_bck(bck),.dac_lrck(lrck),.dac_din(din),.led_oe_n(oe),.led(leds));
 defparam dut.isolation.control.SECOND_CLOCKS=50000,dut.isolation.control.SETTLE_SECONDS=1,dut.isolation.control.MEASURE_SECONDS=4;
 defparam dut.touch.POWER_WAIT=100,dut.touch.RESET_WAIT=100,dut.touch.RETRY_WAIT=5000,
          dut.touch.TIMEOUT=50000,dut.touch.QUARTER=8;
 defparam dut.shared_adc.adc.POWER_WAIT=100;
 mpr121_test_device a(.scl(ascl),.sda(asda),.present(1'b1));
 mpr121_test_device b(.scl(bscl),.sda(bsda),.present(present_b));
 shared_ads1115_test_device adc(.scl(cscl),.sda(csda),.present(1'b1),.bad_config(1'b0),
 .conversion0(16'd25880),.conversion1(16'd13200),.conversion2(16'd13200),.hang_conversion(1'b0));
 integer pcm=0,nonzero=0,pin_edges=0,fft_writes=0,scope_writes=0;
 always @(posedge dut.clk)begin
 if(dut.monitor_ce)begin pcm++;if(dut.monitor_sample!=0)nonzero++;end
 if(dut.visual_write && !dut.workload_visual_rst)fft_writes++;
 if(dut.scope_write && !dut.workload_visual_rst)scope_writes++;
 end
 always @(posedge bck)pin_edges++;
 task ticks(input integer n);repeat(n)@(negedge dut.clk);endtask
 integer before_pcm,before_edges;
 initial begin
 wait(!dut.rst && dut.online);a.registers[0]=1;wait(dut.key_lights[0]);ticks(100);
 if(dut.monitor_ce || dut.monitor_sample!=0 || !dut.core.rst || bck || oe)$fatal(1,"BASE must be silent with live key LED path");
 $display("PASS: diagnostic core reset still permits combinational touch-to-key-LED response");
 wait(dut.isolation.control.stage==1);ticks(5000);before_pcm=pcm;before_edges=pin_edges;ticks(10000);
 if(pcm<=before_pcm || nonzero==0 || pin_edges!=before_edges || bck || lrck!=1 || din)$fatal(1,"CORE mode did not isolate external I2S");
 wait(dut.isolation.control.stage==2 && dut.isolation.control.seconds>=1);ticks(5000);
 before_edges=pin_edges;ticks(10000);if(pin_edges<=before_edges)$fatal(1,"I2S mode no output clock");
 // Even a saturated original sticky F must not suppress new window events.
 force dut.touch.bank_b.failures=8'hff;
 present_b=0;wait(!dut.online);wait(dut.isolation.control.fail_b[2]>=2);
 present_b=1;wait(dut.online);release dut.touch.bank_b.failures;
 if(!dut.chip_online[0] || !dut.pressure_online)$fatal(1,"Fault crossed buses");
 wait(dut.isolation.control.stage==3);
 // Unit test above checks autonomous timing. Hold only this testbench's stage
 // timer long enough to capture/process a real 4096-sample audio frame; no
 // touch flags, ADC responses, PCM or FFT data are forced.
 force dut.isolation.control.timer=0;
 ticks(100);if(bck || !dut.isolate_visual_run)$fatal(1,"FFT mode pins/reset");
 wait(dut.observe_workload.fft_frames!=0);
 release dut.isolation.control.timer;
 wait(dut.isolation.control.stage==4);ticks(1000);
 if(!oe || dut.led_srclk || dut.led_rclk || dut.led_ser)$fatal(1,"NO LED did not release PCB LED outputs");
 wait(dut.isolation.control.stage==5);ticks(20000);
 if(oe || !dut.isolate_i2s_run || dut.workload_visual_rst)$fatal(1,"FULL mode incomplete");
 wait(dut.isolation.control.stage==6);ticks(1000);
 if(!dut.core.rst || bck || !dut.workload_visual_rst || oe || !dut.key_lights[0])$fatal(1,"Return-to-BASE did not preserve live touch/LED");
 wait(dut.isolation.control.finished);wait(dut.screen.display_isolation[232]);
 if(fft_writes<512 || scope_writes<512 || dut.observe_workload.fft_frames==0)$fatal(1,"Actual FFT/scope workload not exercised %d %d",fft_writes,scope_writes);
 if(dut.isolation.control.fail_a[2]!=0 || dut.isolation.control.fail_b[2]<2 || dut.isolation.control.last_b[2]!=1 ||
    dut.isolation.control.fail_b[6]!=0 || !dut.online || !dut.pressure_online)$fatal(1,"Window fault/recovery records");
 if(dut.screen.display_isolation[2*32+8 +: 8]<2)$fatal(1,"Snapshot lost fault evidence");
 $display("PASS: real I2C fault -> independent window counters -> HDMI; internal PCM, I2S gating, FFT/scope, LED isolation and BASE recovery");
 $display("FFT writes=%0d scope writes=%0d",fft_writes,scope_writes);
 $display("ALL TESTS PASSED");$finish;
 end
 initial begin #250000000;$fatal(1,"Isolation top watchdog");end
endmodule
