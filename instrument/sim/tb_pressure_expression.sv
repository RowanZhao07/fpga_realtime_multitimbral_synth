`timescale 1ns/1ps
module tb_pressure_expression;
 reg clk=0;always #10 clk=~clk;
 reg rst=1,online=0,valid=0,ce=0;reg [11:0] mv=0;
 wire [9:0] gain;wire [11:0] filtered;
 pressure_expression dut(.clk(clk),.rst(rst),.online(online),.sample_valid(valid),
 .sample_ce(ce),.millivolts(mv),.gain(gain),.filtered_mv(filtered));
 wire [9:0] calibrated_gain;
 wire [9:0] measured_gain;wire [11:0] measured_filtered;
 pressure_expression #(.FULL_MV(3235)) measured(
 .clk(clk),.rst(rst),.online(online),.sample_valid(valid),.sample_ce(ce),
 .millivolts(mv),.gain(measured_gain),.filtered_mv(measured_filtered));
 pressure_expression #(.ZERO_MV(200),.FULL_MV(2200)) calibrated(
 .clk(clk),.rst(rst),.online(online),.sample_valid(valid),.sample_ce(ce),
 .millivolts(mv),.gain(calibrated_gain),.filtered_mv());
 integer last_gain=512,sweep,expected,expected_default,expected_custom;
 always @(negedge clk) begin
 if(!rst && (gain<128 || gain>512 || gain>last_gain+1 || gain+1<last_gain))
 $fatal(1,"Gain bound or zipper step %0d -> %0d",last_gain,gain);
 last_gain=gain;
 end
 task tick(input integer n);repeat(n)@(negedge clk);endtask
 task adc(input integer v);mv=v;valid=1;tick(1);valid=0;tick(2);endtask
 initial begin
 tick(4);rst=0;ce=1;tick(10);if(gain!==512)$fatal(1,"Offline fallback");
 online=1;adc(0);tick(400);if(gain!==128)$fatal(1,"No-force floor");
 mv=3072;tick(400);if(filtered!==0 || gain!==128)$fatal(1,"Filter ran without sample_valid");
 adc(3072);if(filtered!==768)$fatal(1,"Attack IIR");
 repeat(40)adc(3072);tick(400);if(gain!==512)$fatal(1,"Full scale");
 adc(0);if(filtered<2600 || filtered>2800)$fatal(1,"Release IIR");
 repeat(80)adc(0);tick(400);if(gain!==128)$fatal(1,"Release settled");
 ce=0;online=0;tick(20);if(gain!==128)$fatal(1,"Gain moved without audio tick");
 ce=1;tick(400);if(gain!==512)$fatal(1,"Offline smooth recovery");
 online=1;adc(4095);tick(400);if(gain!==512)$fatal(1,"Overrange clamp");
 adc(0);repeat(80)adc(0);tick(400);if(gain!==128)$fatal(1,"Zero stable");
 repeat(20)begin adc(8);adc(0);end
 tick(100);if(gain!==128)$fatal(1,"No-force noise deadband");
 repeat(80)adc(1200);tick(400);
 if(calibrated_gain<319 || calibrated_gain>321)$fatal(1,"Custom calibration midpoint");
 repeat(80)adc(200);tick(400);if(calibrated_gain!==128)$fatal(1,"Custom zero");
 repeat(80)adc(2200);tick(400);if(calibrated_gain!==512)$fatal(1,"Custom full scale");
 // Verify the actual 3235 mV calibration in both directions, including every
 // integer input, the noise-floor boundary, full scale and overrange clamp.
 mv=0;valid=1;tick(512);
 for(sweep=0;sweep<=4095;sweep=sweep+1) begin
     mv=sweep;tick(64); // IIR settling plus up to two exact 22-clock divisions.
     expected=sweep<=16 ? 128 : sweep>=3235 ? 512 : 128+(sweep*384)/3235;
     if(measured_filtered!==sweep || measured_gain!==expected)
         $fatal(1,"Measured rising calibration mv=%0d filtered=%0d gain=%0d expected=%0d",sweep,measured_filtered,measured_gain,expected);
     expected_default=sweep<=16 ? 128 : sweep>=3072 ? 512 : 128+(sweep*384)/3072;
     expected_custom=sweep<=216 ? 128 : sweep>=2200 ? 512 : 128+((sweep-200)*384)/2000;
     if(gain!==expected_default || calibrated_gain!==expected_custom)$fatal(1,"Alternative calibration rising at %d",sweep);
 end
 for(sweep=4095;sweep>=0;sweep=sweep-1) begin
     mv=sweep;tick(64);
     expected=sweep<=16 ? 128 : sweep>=3235 ? 512 : 128+(sweep*384)/3235;
     if(measured_filtered!==sweep || measured_gain!==expected)
         $fatal(1,"Measured falling calibration mv=%0d filtered=%0d gain=%0d expected=%0d",sweep,measured_filtered,measured_gain,expected);
     expected_default=sweep<=16 ? 128 : sweep>=3072 ? 512 : 128+(sweep*384)/3072;
     expected_custom=sweep<=216 ? 128 : sweep>=2200 ? 512 : 128+((sweep-200)*384)/2000;
     if(gain!==expected_default || calibrated_gain!==expected_custom)$fatal(1,"Alternative calibration falling at %d",sweep);
 end
 valid=0;
 $display("ALL TESTS PASSED");$finish;
 end
 initial begin #20000000;$fatal(1,"watchdog");end
endmodule
