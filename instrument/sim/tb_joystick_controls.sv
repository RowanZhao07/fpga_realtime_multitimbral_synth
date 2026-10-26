`timescale 1ns/1ps
module tb_joystick_controls;
 reg clk=0;always #10 clk=~clk;
 reg rst=1,online=1,valid=0,sw=1,ce=0,cmdvalid=0;
 reg [11:0] mv=1650;reg [17:0] touched=0;
 reg [7:0] command=0;reg [15:0] value=0;
 wire up,down,vib,armed,guide,testmode;
 wire reverse_up,reverse_down;
 joystick_control #(.BUTTON_CLOCKS(4),.CENTER_SAMPLES(3),.REVERSE(1),.BUTTON_ACTIVE_LOW(0)) reverse_stick(
 .clk(clk),.rst(rst),.online(online),.sample_valid(valid),.allow_octave(!guide && !testmode),
 .millivolts(mv),.sw_n(!sw),.octave_up(reverse_up),.octave_down(reverse_down),.vibrato(),.armed());
 always @(negedge clk) if(!rst && (reverse_up!==down || reverse_down!==up))
 $fatal(1,"Reverse direction / active-high switch mismatch");
 wire [1:0] octave;
 wire [12:0] gates;wire output_vib;
 joystick_control #(.BUTTON_CLOCKS(4),.CENTER_SAMPLES(3)) stick(
 .clk(clk),.rst(rst),.online(online),.sample_valid(valid),.allow_octave(!guide && !testmode),
 .millivolts(mv),.sw_n(sw),.octave_up(up),.octave_down(down),.vibrato(vib),.armed(armed));
 performance_control #(.ENABLE_JOYSTICK(1),.HOLD_SAMPLES(8)) controls(
 .clk(clk),.rst(rst),.sample_ce(ce),.online(online),.touched(touched),
 .joystick_up(up),.joystick_down(down),.joystick_vibrato(vib),
 .command_valid(cmdvalid),.command(command),.value(value),.octave_select(octave),
 .gates(gates),.vibrato(output_vib),.spectrum_mode(testmode),.guide_enabled(guide));
 task ticks(input integer n);repeat(n) @(negedge clk);endtask
 task adc(input integer v);mv=v;valid=1;ticks(1);valid=0;ticks(2);endtask
 task center;repeat(3)adc(1650);endtask
 task right;center;adc(3000);endtask
 task left;center;adc(200);endtask
 task guide_set(input bit en);command="G";value=en;cmdvalid=1;ticks(1);cmdvalid=0;ticks(2);endtask
 initial begin
 ticks(4);rst=0;ticks(10);
 repeat(5)adc(3000);if(octave!==1)$fatal(1,"Start held moved octave");
 right;if(octave!==2)$fatal(1,"Clock event lost without audio CE");
 repeat(6)adc(3000);adc(200);if(octave!==2)$fatal(1,"Held or cross-center jump retriggered");
 adc(1650);adc(2000);adc(1650);adc(3000);if(octave!==2)$fatal(1,"Neutral chatter armed too early");
 right;right;if(octave!==3)$fatal(1,"Upper saturation");
 repeat(5)left;if(octave!==0)$fatal(1,"Lower saturation");
 center;mv=3000;ticks(20);if(octave!==0)$fatal(1,"Stale ADC voltage used");
 online=0;ticks(3);online=1;adc(3000);if(octave!==0)$fatal(1,"Reconnect held");
 sw=0;ticks(2);sw=1;ticks(8);if(output_vib)$fatal(1,"Switch bounce");
 sw=0;ticks(10);if(!output_vib)$fatal(1,"Hold vibrato");
 right;if(octave!==0)$fatal(1,"Press tilt changed octave");
 sw=1;ticks(10);if(output_vib)$fatal(1,"Release vibrato");
 adc(3000);if(octave!==0)$fatal(1,"Release tilt retriggered");
 right;if(octave!==1)$fatal(1,"Rearm after press");
 guide_set(1);left;if(octave!==1)$fatal(1,"GUIDE manual override");
 guide_set(0);adc(200);if(octave!==1)$fatal(1,"GUIDE exit held");
 left;if(octave!==0)$fatal(1,"GUIDE exit rearm");
 ce=1;touched=18'h20801;ticks(4);
 if(octave!==0 || output_vib || gates!==1)$fatal(1,"Legacy octave/vibrato leaked or note lost");
 touched=18'hf00;ticks(12);touched=0;ticks(2);
 if(!testmode)$fatal(1,"Four-control calibration lost");
 right;if(octave!==0)$fatal(1,"Test mode manual override");
 sw=0;rst=1;ticks(4);rst=0;ticks(20);if(output_vib)$fatal(1,"Startup pressed");
 sw=1;ticks(12);sw=0;ticks(12);if(!output_vib)$fatal(1,"Startup release recovery");
 $display("ALL TESTS PASSED");$finish;
 end
 initial begin #1000000;$fatal(1,"watchdog");end
endmodule
