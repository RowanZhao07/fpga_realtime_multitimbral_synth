`timescale 1ns/1ps
module tb_sustain_control;
 reg clk=0;always #10 clk=~clk;
 reg rst=1,online=1,request=0,rx=1;reg [17:0] touched=0;
 wire sustained;
 instrument_core #(.UART_CLOCKS_PER_BIT(16)) dut(.encoder_a(1'b1),.encoder_b(1'b1),.encoder_sw_n(1'b1),.sustain_info(),.clk(clk),.rst(rst),.online(online),
  .sustain_request(request),.sustain_active(sustained),.touched(touched),
  .chip_online(2'b11),.pressure_online(1'b0),.pressure_mv(12'd0),.control_rx(rx));
 task tick(input integer n);repeat(n) @(negedge clk);endtask
 task byte_in(input [7:0] b);
  @(negedge clk);rx=0;tick(16);
  for(integer i=0;i<8;i=i+1)begin rx=b[i];tick(16);end
  rx=1;tick(16);
 endtask
 task command(input [7:0] value);
  byte_in("H");byte_in(value);byte_in(10);tick(300);
 endtask
 initial begin
  tick(5);rst=0;tick(5);
  command("1");if(!sustained)$fatal(1,"H1 must engage pedal");
  command("2");if(!sustained)$fatal(1,"Invalid H2 changed pedal");
  command("0");if(sustained)$fatal(1,"H0 must release pedal");
  command("1");touched=18'h20800;tick(3000);touched=0;tick(3000);
  if(!sustained || dut.octave_select!==3) $fatal(1,"Octave switch cancelled pedal or selected wrong bank");
  force dut.spectrum_mode=1'b1;tick(3);
  if(dut.octave_select!==1) $fatal(1,"Calibration must remain in octave 4");
  release dut.spectrum_mode;tick(3);
  if(dut.octave_select!==3) $fatal(1,"Calibration exit lost selected octave");
  request=1;tick(2);if(!sustained)$fatal(1,"Hardware request ignored");
  command("0");if(!sustained)$fatal(1,"H0 must not cancel external source");
  request=0;tick(2);if(sustained)$fatal(1,"External release ignored");
  command("1");online=0;tick(2);if(sustained)$fatal(1,"Offline must disable pedal");
  online=1;tick(2);if(sustained)$fatal(1,"Reconnect revived remote request");
  command("1");force dut.spectrum_mode=1'b1;tick(3);
  if(sustained)$fatal(1,"Test mode must disable pedal");
  release dut.spectrum_mode;tick(3);if(sustained)$fatal(1,"Mode exit revived request");
  command("1");rst=1;tick(2);if(sustained)$fatal(1,"Reset must clear pedal");
  $display("ALL TESTS PASSED");$finish;
 end
 initial begin #1000000;$fatal(1,"Control watchdog");end
endmodule
