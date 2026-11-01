`timescale 1ns/1ps
module tb_expression_core;
 reg clk=0;always #10 clk=~clk;
 reg rst=1,rx=1,sv=0,online=1,ponline=0,pvalid=0;reg [11:0] ymv=1650;reg [17:0] touched=0;
 wire ce;wire signed [15:0] pcm;wire [31:0] info;
 instrument_core #(.ENABLE_EXPRESSION(1),.ENABLE_JOYSTICK(1),.ENABLE_EC11(1),.DEFAULT_TIMBRE(1),.UART_CLOCKS_PER_BIT(8)) dut(
 .clk(clk),.rst(rst),.online(online),.chip_online(2'b11),.touched(touched),
 .joystick_online(1'b1),.joystick_sample_valid(1'b0),.joystick_mv(12'd1650),.joystick_sw_n(1'b1),
 .y_online(1'b1),.y_sample_valid(sv),.y_mv(ymv),
 .pressure_online(ponline),.pressure_sample_valid(pvalid),.pressure_mv(12'd0),
 .encoder_a(1'b1),.encoder_b(1'b1),.encoder_sw_n(1'b1),.sustain_request(1'b0),.control_rx(rx),
 .monitor_ce(ce),.monitor_sample(pcm),.performance_info(info));
 defparam dut.controls.HOLD_SAMPLES=8;
 task ticks(input integer n);repeat(n)@(negedge clk);endtask
 task frame;begin @(posedge ce);wait(dut.effects_valid);ticks(6);if(dut.engine_overrun || (^pcm)===1'bx)$fatal(1,"Real-rate output failure");end endtask
 task frames(input integer n);repeat(n)frame;endtask
 task adc(input integer v);begin ymv=v;sv=1;ticks(1);sv=0;ticks(6);end endtask
 task byte_tx(input [7:0] b);integer i;begin rx=0;ticks(8);for(i=0;i<8;i++)begin rx=b[i];ticks(8);end rx=1;ticks(8);end endtask
 task command(input [7:0] c,input [7:0] v);begin byte_tx(c);byte_tx(v);byte_tx(10);ticks(100);end endtask
 reg [31:0] old_phase,delta;integer f;
 initial begin
 f=$fopen("expression_pitch.csv","w");$fdisplay(f,"bend_q16,phase_increment,frequency_hz");
 ticks(5);rst=0;frames(10);repeat(8)adc(3000);frames(2);
 if(dut.y_enabled || dut.pitch_bend!=0 || info[1:0]!=0)$fatal(1,"Y default must be disabled");
 command("Y","2");if(dut.y_enabled || dut.rejected!=1)$fatal(1,"Invalid Y accepted");
 command("F","4");if(dut.effect_mode!=0 || dut.rejected!=2)$fatal(1,"Invalid F accepted");
 command("Y","1");repeat(8)adc(1650);frames(2);if(info[1:0]!=3)$fatal(1,"UART Y and armed status");
 touched=1;frames(150);
 adc(3300);frames(600);old_phase=dut.engine.phase[0];frame;delta=dut.engine.phase[0]-old_phase;
 if(delta<25830000 || delta>25832000 || dut.engine.steps[0]!=23012828)$fatal(1,"Held note did not bend upward without retuning base: %d",delta);
 $fdisplay(f,"%0d,%0d,%0.8f",dut.pitch_bend,delta,delta*48828.125/4294967296.0);
 // Exercise all three independent expression dimensions and reverb together.
 touched=18'h801;ponline=1;pvalid=1;ticks(1);pvalid=0;
 command("F","2");frames(500);
 if(!dut.vibrato || dut.pitch_bend!=8026 || dut.pressure_gain!=128 || dut.effect_mode!=2)
 $fatal(1,"Concurrent pressure/bend/vibrato/reverb interfered");
 touched=1;ponline=0;frames(500);if(dut.pressure_gain!=512 || dut.vibrato)$fatal(1,"Independent expression release");
 adc(0);frames(1000);old_phase=dut.engine.phase[0];frame;delta=dut.engine.phase[0]-old_phase;
 if(delta<20501000 || delta>20503000)$fatal(1,"Downward phase increment %d",delta);
 $fdisplay(f,"%0d,%0d,%0.8f",dut.pitch_bend,delta,delta*48828.125/4294967296.0);
 adc(1650);frames(600);old_phase=dut.engine.phase[0];frame;delta=dut.engine.phase[0]-old_phase;
 if(delta!=23012828)$fatal(1,"Neutral tuning changed");
 $fdisplay(f,"%0d,%0d,%0.8f",dut.pitch_bend,delta,delta*48828.125/4294967296.0);
 touched=18'h801;frames(2);if(!dut.vibrato)$fatal(1,"VIB key");
 touched=18'h20801;frames(2);if(dut.vibrato || dut.y_enabled)$fatal(1,"Y local toggle conflicts with VIB");
 frames(10);if(dut.y_enabled)$fatal(1,"Held combo retoggled");touched=1;frames(2);
 command("F","2");frames(150);if(info[3:2]!=2 || dut.echo_enabled)$fatal(1,"Reverb selection/status");
 command("F","3");frames(150);if(info[3:2]!=3)$fatal(1,"Chorus selection/status");
 command("E","1");frames(2);if(info[3:2]!=1 || !dut.echo_enabled)$fatal(1,"Legacy E selects delay");
 touched=18'h101;frames(10);if(info[3:2]!=2)$fatal(1,"C0 long-press effect cycle");
 touched=1;frames(2);if(dut.timbre!=1)$fatal(1,"Effect long press also changed tone");
 command("T","2");touched=5;frames(4);
 if(dut.engine.preset[0]!=1 || dut.engine.preset[1]!=2)$fatal(1,"Held timbre changed / new timbre not applied");
 online=0;frames(2);if(dut.vibrato || dut.y_armed)$fatal(1,"Offline expression");
 $fclose(f);$display("PASS: actual UART F/Y/E, local VIB/Y/FX controls, real-rate held-note bend, timbre latch, status and fail-safe");
 $display("ALL TESTS PASSED");$finish;
 end
 initial begin #150000000;$fatal(1,"Expression core watchdog");end
endmodule
