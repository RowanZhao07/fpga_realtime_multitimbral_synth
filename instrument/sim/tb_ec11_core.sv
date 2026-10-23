`timescale 1ns/1ps
module tb_ec11_core;
 reg clk=0;always #10 clk=~clk;
 reg rst=1,online=1,a=1,b=1,sw=1,rx=1;reg [17:0] touched=0;
 wire sustained;wire [5:0] info;wire [103:0] levels;
 instrument_core #(.ENABLE_EC11(1),.DEFAULT_TIMBRE(1),.EC11_FILTER_CLOCKS(4),
  .EC11_BUTTON_CLOCKS(12),.UART_CLOCKS_PER_BIT(16)) dut(.clk(clk),.rst(rst),
  .online(online),.encoder_a(a),.encoder_b(b),.encoder_sw_n(sw),.sustain_info(info),
  .sustain_request(1'b0),.sustain_active(sustained),.touched(touched),.voice_levels(levels),
  .chip_online(2'b11),.pressure_online(1'b0),.pressure_mv(12'd0),.control_rx(rx));
 task tick(input integer n);repeat(n)@(negedge clk);endtask
 task press;sw=0;tick(30);sw=1;tick(30);endtask
 task byte_in(input [7:0] value);
  rx=0;tick(16);for(integer i=0;i<8;i=i+1)begin rx=value[i];tick(16);end
  rx=1;tick(16);
 endtask
 task command(input [7:0] value);byte_in("H");byte_in(value);byte_in(10);tick(300);endtask
 initial begin
  tick(5);rst=0;tick(40);
  if(info!==6'd3)$fatal(1,"EC11 defaults");
  press();if(!sustained)$fatal(1,"Core push connection");
  {a,b}=1;tick(20);{a,b}=0;tick(20);{a,b}=2;tick(20);{a,b}=3;tick(20);
  if(info!=={1'b1,5'd5})$fatal(1,"Core strength connection");
  if(dut.engine.voice_count!=0)$fatal(1,"Knob generated a note");
  touched=1;tick(110000);touched=0;tick(40000);
  if(levels==0)$fatal(1,"Touch -> 32-voice engine has no sustained tail");
  command("0");if(sustained)$fatal(1,"UART H0 cannot release EC11");
  command("1");if(!sustained)$fatal(1,"UART H1 cannot enable EC11");
  press();if(sustained)$fatal(1,"Button cannot override prior H1");
  command("1");online=0;tick(3);if(sustained)$fatal(1,"Offline protection");
  online=1;tick(30);if(info!==6'd3)$fatal(1,"Reconnect defaults");
  press();force dut.spectrum_mode=1;tick(4);if(sustained)$fatal(1,"Test-mode protection");
  release dut.spectrum_mode;tick(40);if(sustained)$fatal(1,"Mode exit revived sustain");
  if(dut.engine.overrun)$fatal(1,"32-voice render overrun");
  $display("ALL TESTS PASSED");$finish;
 end
 initial begin #10000000;$fatal(1,"EC11 core watchdog");end
endmodule
