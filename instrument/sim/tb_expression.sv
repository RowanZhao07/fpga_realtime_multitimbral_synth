`timescale 1ns/1ps
module tb_pitch_expression;
 reg clk=0;always #10 clk=~clk;
 reg rst=1,ce=0,en=0,online=1,sv=0;reg [11:0] mv=1450;
 wire armed;wire signed [15:0] bend;
 pitch_expression dut(.clk(clk),.rst(rst),.sample_ce(ce),.enabled(en),.online(online),.sample_valid(sv),.millivolts(mv),.armed(armed),.bend(bend));
 task ticks(input integer n);repeat(n)@(negedge clk);endtask
 task adc(input integer v);begin mv=v;sv=1;ticks(1);sv=0;ticks(5);end endtask
 task frames(input integer n);begin ce=1;ticks(n);ce=0;ticks(1);end endtask
 integer old_bend=0;
 always @(negedge clk) begin
   if(!rst && (bend-old_bend>16 || old_bend-bend>16))$fatal(1,"Pitch slew discontinuity");
   old_bend=bend;
 end
 initial begin
 ticks(4);rst=0;repeat(12)adc(3200);frames(700);
 if(armed || bend!=0)$fatal(1,"Floating/disabled Y used");
 en=1;repeat(12)adc(3200);if(armed)$fatal(1,"Deflected startup armed");
 repeat(8)adc(1450);if(!armed || dut.center!=1450)$fatal(1,"Learn loaded supply neutral");
 adc(1490);frames(600);if(bend!=0)$fatal(1,"Neutral deadband");
 adc(3000);frames(600);if(bend!=8026)$fatal(1,"Up two semitones %d",bend);
 mv=0;frames(10);if(bend!=8026)$fatal(1,"Stale axis used");
 adc(0);frames(1000);if(bend!= -7150)$fatal(1,"Down two semitones %d",bend);
 adc(1450);frames(600);if(bend!=0)$fatal(1,"Return to unbent pitch");
 adc(3000);frames(600);online=0;frames(600);if(armed || bend!=0)$fatal(1,"Disconnect neutral recovery");
 online=1;repeat(8)adc(3000);if(armed)$fatal(1,"Reconnect must recenter");
 repeat(8)adc(1650);adc(3300);frames(600);en=0;frames(600);if(bend!=0 || armed)$fatal(1,"Disabled wheel");
 $display("PASS: disabled Y, neutral learning/deadband, +/-2 semitone endpoints, bounded slew and reconnect");
 $display("ALL TESTS PASSED");$finish;
 end
endmodule

module tb_expression_allocator;
 tb_voice_allocator #(.VARIABLE_SUSTAIN(1),.PITCH_BEND(1)) suite();
endmodule

module tb_expression_effects;
 reg clk=0;always #10 clk=~clk;
 reg rst=1,valid=0,cal=0;reg [1:0] mode=0;reg signed [18:0] mixed=0;
 wire vo;wire signed [18:0] result;
 expression_effects dut(.clk(clk),.rst(rst),.valid(valid),.calibration(cal),.mode(mode),.mixed(mixed),.valid_out(vo),.result(result));
 integer f,n,nonzero,early,late,energy;
 task frame(input integer x);
 integer cycles;
 begin
 @(negedge clk);mixed=x;valid=1;@(negedge clk);valid=0;cycles=0;
 while(!vo && cycles<20)begin @(negedge clk);cycles++;end
 if(!vo || cycles!=8 || (^result)===1'bx)$fatal(1,"Effect deadline/unknown PCM %d",cycles);
 repeat(3)@(negedge clk);
 end endtask
 task reset;begin rst=1;repeat(3)@(negedge clk);rst=0;end endtask
 initial begin
 f=$fopen("expression_effects.csv","w");$fdisplay(f,"mode,n,input,output");
 reset;
 for(n=0;n<2200;n++)begin frame((n%257)*10-1280);if(result!==mixed)$fatal(1,"Dry path altered");end
 for(mode=1;mode!=0;mode=mode+1'b1)begin
 reset;repeat(2100)frame(0);nonzero=0;early=0;late=0;
 for(n=0;n<24000;n++)begin
 frame(n==0 ? 65536 : 0);$fdisplay(f,"%0d,%0d,%0d,%0d",mode,n,mixed,result);
 if(n>0 && result!=0)nonzero++;
 energy=result<0 ? -result : result;
 if(n>=2000 && n<6000)early+=energy;
 if(n>=18000)late+=energy;
 end
 if(mode==1 && nonzero!=0)$fatal(1,"Delay handled by legacy stage, new stage must be dry");
 if(mode==2 && (nonzero<100 || early==0 || late>=early))$fatal(1,"Reverb density/decay %d %d %d",nonzero,early,late);
 if(mode==3 && nonzero<1)$fatal(1,"Chorus delayed impulse missing");
 $display("Mode %0d: delayed nonzero samples %0d, early energy %0d late %0d",mode,nonzero,early,late);
 end
 mode=2;repeat(2100)frame(0);cal=1;
 for(n=0;n<10;n++)begin frame(20000);if(result!=20000)$fatal(1,"Calibration bypass");end
 cal=0;mode=3;repeat(2400)frame(260000);
 mode=2;repeat(2400)frame(-260000);
 reset;repeat(2100)begin frame(0);if(result!=0)$fatal(1,"Reset leaked RAM history");end
 $fclose(f);$display("PASS: reverb impulse density/decay, chorus, dry/calibration bypass, bounded full-scale and reset");
 $display("ALL TESTS PASSED");$finish;
 end
 initial begin #100000000;$fatal(1,"Effects watchdog");end
endmodule

module tb_expression_adc;
 reg clk=0;always #10 clk=~clk;
 reg rst=1,present=1,bad=0,hang=0;tri1 scl,sda;
 wire po,jo,yo,pv,jv,yv;wire [11:0] pm,jm,ym;wire [15:0] diagnostics;
 integer expected=0,count=0;time previous=0,period;
 ads1115_scanner #(.ENABLE_Y(1),.POWER_WAIT(100),.RETRY_WAIT(500)) dut(
 .clk(clk),.rst(rst),.scl(scl),.sda(sda),.pressure_online(po),.pressure_valid(pv),.pressure_mv(pm),
 .joystick_online(jo),.joystick_valid(jv),.joystick_mv(jm),.y_online(yo),.y_valid(yv),.y_mv(ym),.diagnostics(diagnostics));
 shared_ads1115_test_device adc(.scl(scl),.sda(sda),.present(present),.bad_config(bad),.hang_conversion(hang),
 .conversion0(16'd25880),.conversion1(16'd13200),.conversion2(16'd24000));
 always @(negedge clk)begin
 if(pv)begin if(expected!=0 || pm!=3235)$fatal(1,"AIN0 sequencing");expected=1;end
 if(jv)begin if(expected!=1 || jm!=1650)$fatal(1,"AIN1 sequencing");expected=2;end
 if(yv)begin
 if(expected!=2 || ym!=3000)$fatal(1,"AIN2 stale/mux error");expected=0;count++;
 if(previous!=0)begin period=$time-previous;$display("Y period %0d ns",period);if(period<9900000 || period>10050000)$fatal(1,"3-channel budget");end
 previous=$time;
 end
 end
 task recover;begin expected=0;previous=0;wait(yv);@(negedge clk);end endtask
 initial begin
 repeat(4)@(negedge clk);rst=0;wait(count==3);@(negedge clk);
 present=0;wait(!po && !jo && !yo);if(pm || jm || ym)$fatal(1,"Stale shared axis on failure");
 @(negedge clk);present=1;recover;
 bad=1;wait(!po && !jo && !yo);@(negedge clk);bad=0;recover;
 hang=1;wait(!po && !jo && !yo);@(negedge clk);hang=0;recover;
 $display("PASS: AIN0/1/2 real bus cadence, channel isolation, NACK/config/OS-timeout recovery");
 $display("ALL TESTS PASSED");$finish;
 end
 initial begin #200000000;$fatal(1,"ADC watchdog");end
endmodule
