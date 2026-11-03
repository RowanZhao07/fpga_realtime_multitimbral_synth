`timescale 1ns/1ps
module tb_metronome_control;
 reg clk=0;always #10 clk=~clk;
 reg rst=1,online=1;reg [17:0] touched=0;
 wire enabled,gesture,vib;wire [7:0] bpm;wire [2:0] meter,timbre;
 wire [12:0] volume,gates;wire guide,spectrum,y;
 metronome_control #(.HOLD_SAMPLES(6),.REPEAT_SAMPLES(3)) dut(
 .clk(clk),.rst(rst),.sample_ce(1'b1),.online(online),.touched(touched),
 .enabled(enabled),.gesture(gesture),.bpm(bpm),.meter(meter));
 performance_control #(.ENABLE_EXPRESSION(1),.ENABLE_JOYSTICK(1),.HOLD_SAMPLES(6),.REPEAT_SAMPLES(3)) legacy(
 .clk(clk),.rst(rst),.sample_ce(1'b1),.online(online),.touched(touched),
 .joystick_up(1'b0),.joystick_down(1'b0),.joystick_vibrato(1'b0),
 .command_valid(1'b0),.command(8'd0),.value(16'd0),
 .timbre(timbre),.volume(volume),.gates(gates),.vibrato(vib),.guide_enabled(guide),.spectrum_mode(spectrum),.y_enabled(y));
 task step(input integer n);repeat(n)@(negedge clk);endtask
 task release_all;begin touched=0;step(3);end endtask
 task hold(input [3:0] key,input integer n);begin touched=18'h20001 | (key<<8);step(n);end endtask
 integer i,old_bpm;
 initial begin
 step(3);rst=0;step(2);
 if(enabled || bpm!=120 || meter!=3)$fatal(1,"Defaults");
 hold(8,4);release_all;if(enabled)$fatal(1,"Short accidental chord toggled");
 hold(8,40);if(!enabled || vib || y || gates!=1)$fatal(1,"Toggle/held note/VIB/Y conflict");
 touched=18'h801;step(10);if(vib)$fatal(1,"Modifier-first release leaked VIB");release_all;
 hold(8,10);if(enabled)$fatal(1,"Second toggle");
 touched=18'h20000;step(3);hold(1,10);if(meter!=4)$fatal(1,"Retained X0 next chord");
 step(50);if(meter!=4)$fatal(1,"Held meter repeats");
 touched=18'h20000;step(3);release_all;
 for(i=0;i<5;i=i+1)begin hold(1,10);release_all;if(meter!=i)$fatal(1,"Meter order %0d %0d",i,meter);end
 touched=18'h400;step(1);
 hold(4,10);if(bpm!=124 || enabled)$fatal(1,"Repeat while stopped: %0d",bpm);
 touched=18'h400;step(10);if(volume!=2048)$fatal(1,"Release leaked master volume");release_all;
 hold(2,10);release_all;if(bpm!=120)$fatal(1,"Down speed");
 hold(6,30);touched=18'h20400;step(20);release_all;
 if(bpm!=120 || guide || spectrum || timbre || volume!=2048 || y)$fatal(1,"Ambiguous chord leaks");
 hold(4,1000);release_all;if(bpm!=240)$fatal(1,"Upper bound");
 hold(2,1000);release_all;if(bpm!=40)$fatal(1,"Lower bound");
 touched=18'h100;step(2);touched=0;step(2);if(timbre!=1)$fatal(1,"Normal TONE changed");
 touched=18'h400;step(3);release_all;if(volume!=2304)$fatal(1,"Normal VOL+ changed");
 touched=18'h800;step(2);if(!vib)$fatal(1,"Normal VIB changed");release_all;
 online=0;hold(8,20);if(enabled)$fatal(1,"Offline ghost input");release_all;
 $display("ALL TESTS PASSED: metronome defaults, 5 meters, hold/repeat, limits, chord release orders, retained X0 and ordinary controls");$finish;
 end
endmodule
