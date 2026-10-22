`timescale 1ns/1ps
// Real UART parser -> score RAM -> automatic bank -> actual voice frequencies.
module tb_guide_auto;
 reg clk=0;always #10 clk=~clk;
 reg rst=1,rx=1;reg [17:0] touched=0;wire ce;wire [1:0] octave;
 instrument_core #(.UART_CLOCKS_PER_BIT(8)) dut(.clk(clk),.rst(rst),.online(1'b1),
 .sustain_request(1'b1),.touched(touched),.chip_online(2'b11),.pressure_online(1'b0),.pressure_mv(12'd0),
 .control_rx(rx),.monitor_ce(ce),.octave_select(octave));
 defparam dut.guide.TICK_DENOM=32'd983040;
 task byte_in(input [7:0] b);
 @(negedge clk);rx=0;repeat(8)@(negedge clk);
 for(integer n=0;n<8;n++)begin rx=b[n];repeat(8)@(negedge clk);end
 rx=1;repeat(8)@(negedge clk);endtask
 task send(input string s);
 for(integer n=0;n<s.len();n++)byte_in(s[n]);byte_in(10);repeat(150)@(negedge clk);endtask
 task frames(input integer n);repeat(n)begin @(posedge ce);repeat(450)@(negedge clk);end endtask
 initial begin
 repeat(5)@(negedge clk);rst=0;
 send("N");send("O3");send("U2");send("A0001");send("O6");send("A0001");send("Z");send("G1");
 frames(3);if(octave!=0)$fatal(1,"Guide did not select octave 3");
 if(dut.gates!=0)$fatal(1,"Score synthesized its own gate");
 touched=1;frames(10);
 if(dut.engine.steps[0]!=11506414 || dut.guide_position!=0)$fatal(1,"Initial C3 or hold interlock");
 touched=0;frames(4);if(octave!=3 || dut.guide_position!=1)$fatal(1,"Guide did not select octave 6");
 touched=1;frames(10);
 if(dut.engine.steps[0]!=11506414 || dut.engine.steps[1]!=92051312 || dut.voice_count!=2)
 $fatal(1,"Automatic C6 replaced old C3 sustain or wrong mapping");
 send("G0");frames(2);if(octave!=1)$fatal(1,"Manual octave was not restored");
 if(dut.engine.steps[1]!=92051312)$fatal(1,"Disabling guide retuned held note");
 $display("PASS: UART absolute score, automatic 3/6 octave, independent sustain, manual restore");
 $display("ALL TESTS PASSED");$finish;
 end
 initial begin #5000000;$fatal(1,"Guide integration watchdog");end
endmodule
