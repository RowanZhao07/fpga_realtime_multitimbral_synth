`timescale 1ns/1ps
// Digital core integration: audio timing is real (1024 clocks per sample).
module tb_joystick_core;
 reg clk=0;always #10 clk=~clk;
 reg rst=1,sw=1,esw=1,jvalid=0,pvalid=0,ponline=1,jonline=1;
 reg [11:0] jmv=1650,pmv=0;reg [17:0] touched=0;
 wire [1:0] octave;wire ce;wire signed [15:0] pcm;
 instrument_core #(.ENABLE_JOYSTICK(1),.ENABLE_EC11(1),.DEFAULT_TIMBRE(1),
 .JOYSTICK_BUTTON_CLOCKS(8),.EC11_FILTER_CLOCKS(4),.EC11_BUTTON_CLOCKS(8)) dut(
 .clk(clk),.rst(rst),.online(1'b1),.chip_online(2'b11),.touched(touched),
 .joystick_online(jonline),.joystick_sample_valid(jvalid),.joystick_mv(jmv),.joystick_sw_n(sw),
 .pressure_online(ponline),.pressure_sample_valid(pvalid),.pressure_mv(pmv),
 .encoder_a(1'b1),.encoder_b(1'b1),.encoder_sw_n(esw),.sustain_request(1'b0),.control_rx(1'b1),
 .octave_select(octave),.monitor_ce(ce),.monitor_sample(pcm));
 task ticks(input integer n);repeat(n)@(negedge clk);endtask
 task frames(input integer n);repeat(n)begin @(posedge ce);@(negedge clk);end endtask
 task axis(input integer mv);jmv=mv;jvalid=1;ticks(1);jvalid=0;ticks(2);endtask
 task pressure(input integer mv);pmv=mv;pvalid=1;ticks(1);pvalid=0;ticks(2);endtask
 integer i,peak;
 initial begin
 ticks(5);rst=0;ticks(40);esw=0;ticks(20);esw=1;ticks(20);
 if(!dut.sustain_active)$fatal(1,"EC11 sustain integration");
 touched=1;frames(100);
 for(i=0;i<32;i=i+1)begin frames(1);if((^pcm)===1'bx)$fatal(1,"Unknown settled audio");end
 if(dut.engine.steps[0]!==23012828)$fatal(1,"Default C4 tuning");
 repeat(8)axis(1650);axis(3000);if(octave!==2)$fatal(1,"Manual octave integration");
 if(dut.engine.steps[0]!==23012828)$fatal(1,"Held note retuned");
 touched=0;frames(3);touched=1;frames(100);
 if(dut.engine.steps[1]!==46025656 || dut.voice_count<2)$fatal(1,"New C5 / old C4 tail");
 sw=0;ticks(24);if(!dut.vibrato)$fatal(1,"Pressed vibrato integration");
 sw=1;ticks(24);if(dut.vibrato)$fatal(1,"Released vibrato integration");
 touched=18'h801;frames(2);if(!dut.vibrato)$fatal(1,"C3 vibrato did not work alongside joystick");touched=1;
 repeat(48)pressure(0);frames(500);
 if(dut.pressure_gain!==128 || dut.expressive_volume!==512)$fatal(1,"Pressure zero integration");
 repeat(64)pressure(3235);frames(500);
 if(dut.pressure_gain!==512 || dut.expressive_volume!==2048)$fatal(1,"3235mV full-scale calibration lost");
 peak=0;repeat(64)begin frames(1);
 if((^pcm)===1'bx)$fatal(1,"Unknown pressure-scaled audio");
 if(pcm>peak)peak=pcm;if(-pcm>peak)peak=-pcm;end
 if(peak<50 || dut.engine.overrun)$fatal(1,"No audible PCM or render deadline missed");
 jonline=0;axis(200);if(octave!==2)$fatal(1,"Offline joystick changed octave");
 ponline=0;frames(400);if(dut.pressure_gain!==512)$fatal(1,"Shared ADC fail-safe gain");
 $display("PASS: real audio ticks, old/new octaves, EC11 tail, hold vibrato, calibrated pressure and bounded PCM");
 $display("ALL TESTS PASSED");$finish;
 end
 initial begin #100000000;$fatal(1,"Joystick core watchdog");end
endmodule
