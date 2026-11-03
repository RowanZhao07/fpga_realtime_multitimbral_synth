`timescale 1ns/1ps
module tb_touch_debug;
 GSR GSR(.GSRI(1'b1));
 reg clk=0;always #10 clk=~clk;
 reg rst=1,online=0,rx=1;reg [17:0] touched=0;
 reg [9:0] divider=0;wire ce=divider==0;
 always @(negedge clk) divider<=divider+1'b1;
 wire sustain_on;wire [52:0] status;
 instrument_core #(.DEFAULT_SUSTAIN(1'b1),.DEFAULT_TIMBRE(3'd1),.UART_CLOCKS_PER_BIT(16)) dut(.encoder_a(1'b1),.encoder_b(1'b1),.encoder_sw_n(1'b1),.sustain_info(),
  .clk(clk),.rst(rst),.online(online),.touched(touched),.chip_online(2'b11),
  .pressure_online(1'b0),.pressure_mv(12'd0),.sustain_request(1'b0),.sustain_active(sustain_on),
  .control_rx(rx),.status(status));
 instrument_core #(.DEFAULT_TIMBRE(3'd1)) reference(.encoder_a(1'b1),.encoder_b(1'b1),.encoder_sw_n(1'b1),.sustain_info(),
  .clk(clk),.rst(rst),.online(online),.touched(touched),.chip_online(2'b11),
  .pressure_online(1'b0),.pressure_mv(12'd0),.sustain_request(1'b0),.control_rx(1'b1));
 initial begin force dut.sample_ce=ce;force reference.sample_ce=ce;end
 task tick(input integer n);repeat(n) @(negedge clk);endtask
 task frames(input integer n);repeat(n) begin @(posedge ce);@(negedge ce);end endtask
 task byte_in(input [7:0] b);
  @(negedge clk);rx=0;tick(16);
  for(integer i=0;i<8;i=i+1)begin rx=b[i];tick(16);end
  rx=1;tick(16);
 endtask
 task pedal(input [7:0] value);byte_in("H");byte_in(value);byte_in(10);tick(200);endtask
 reg [10:0] x=640;reg [9:0] y=44;
 instrument_screen #(.TOUCH_DEBUG(1'b1)) screen(.sustain_info(6'd0),.clk(clk),.rst(rst),.x(x),.y(y),
  .de(1'b1),.hs(1'b0),.vs(1'b0),.vertical_blank(1'b1),.status(204'd0),.performance_info(33'd0),.voice_levels(104'd0),.octave_select(2'd1),
  .scope_ready(1'b0),.scope_data(8'd0),.visual_ready(1'b0),.visual_data(8'd0));
 initial begin
  tick(5);rst=0;frames(3);
  if(sustain_on || dut.active!=0 || dut.gates!=0)$fatal(1,"Offline protection bypassed");
  tick(10);if(screen.character!=="S")$fatal(1,"Debug mode label missing");
  x=28;y=568;tick(10);if(screen.character!=="D")$fatal(1,"Default sustain footer missing");
  online=1;frames(3);
  if(!sustain_on || status[17:16]!=1 || reference.sustain_active)$fatal(1,"Incorrect debug/normal defaults");
  if(dut.gates!=0 || dut.active!=0)$fatal(1,"Unexpected automatic notes");
  touched=1;frames(400);
  if(dut.active[0]!==1 || dut.gates!=1)$fatal(1,"Physical touch did not trigger C4");
  touched=0;frames(7000);
  $display("TAIL: debug=%0d normal=%0d gates=%h",dut.engine.envelopes[0],reference.engine.envelopes[0],dut.gates);
  if(!dut.active[0] || reference.active!=0 || dut.gates!=0)$fatal(1,"Default sustain tail or physical release wrong");
  pedal("0");if(sustain_on)$fatal(1,"H0 cannot release debug pedal");
  frames(7000);if(dut.active!=0 || dut.monitor_sample!=0)$fatal(1,"Pedal up did not reach silence");
  pedal("1");if(!sustain_on)$fatal(1,"H1 cannot engage debug pedal");
  if(dut.active!=0)$fatal(1,"Empty pedal press started a note");
  pedal("0");online=0;frames(3);if(sustain_on)$fatal(1,"Disconnected touch must disable pedal");
  online=1;frames(3);if(!sustain_on)$fatal(1,"Reconnect must restore debug default");
  touched=18'h100;frames(3);touched=0;frames(3);
  if(status[17:16]!=2)$fatal(1,"Physical C0 timbre control broken");
  rst=1;frames(2);rst=0;frames(3);
  if(!sustain_on || status[17:16]!=1)$fatal(1,"Reset did not restore debug defaults");
  $display("PASS: real touch gates, default sustain, normal off, H0/H1, offline/reset, labels and C0");
  $display("ALL TESTS PASSED");$finish;
 end
 initial begin #400000000;$fatal(1,"Touch debug watchdog");end
endmodule
