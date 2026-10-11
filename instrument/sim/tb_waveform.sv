`timescale 1ns/1ps
module tb_waveform;
 reg clk=0;always #10 clk=~clk;
 reg rst=1,ce=0,ack=0;reg signed [15:0] sample=0;
 wire we,done;wire [8:0] addr;wire [7:0] data;
 waveform_capture #(.TRIGGER_TIMEOUT(4)) dut(.clk(clk),.rst(rst),.sample_ce(ce),.sample(sample),
 .write_enable(we),.write_address(addr),.write_value(data),.frame_done(done),.frame_ack(ack));
 integer writes=0,i;reg [7:0] captured[0:511];
 always @(posedge clk) if(we) begin
   if(addr!==writes[8:0]) $fatal(1,"Snapshot address order");
   captured[addr]=data;writes=writes+1;
 end
 task tick(input integer value);
 begin @(negedge clk);sample=value;ce=1;@(negedge clk);ce=0;@(negedge clk); end endtask
 task acknowledge;
 begin @(negedge clk);ack=1;@(negedge clk);ack=0; end endtask
 initial begin
 repeat(3) @(negedge clk);rst=0;
 repeat(3) tick(0);if(writes!=0) $fatal(1,"Timeout too early");
 tick(0);repeat(511) tick(0);
 if(!done || writes!=512) $fatal(1,"Silence snapshot incomplete");
 for(i=0;i<512;i=i+1) if(captured[i]!==0) $fatal(1,"Silence not centered");
 repeat(12) tick(32767);if(writes!=512) $fatal(1,"Writes while waiting for ownership");
 acknowledge;writes=0;
 tick(-32768);if(writes!=0) $fatal(1,"Negative sample falsely triggered");
 tick(64);if(writes!=1 || captured[0]!==8'd1) $fatal(1,"Rising crossing trigger");
 for(i=1;i<512;i=i+1) tick(i[0] ? 32767 : -32768);
 if(!done || writes!=512) $fatal(1,"Triggered snapshot incomplete");
 for(i=1;i<512;i=i+1) if(captured[i] !== (i[0] ? 8'h7f : 8'h80)) $fatal(1,"Signed clipping");
 acknowledge;writes=0;
 // DC must still refresh without a crossing. Verify fixed gain, not AGC.
 repeat(4) tick(4096);repeat(511) tick(4096);
 for(i=0;i<512;i=i+1) if(captured[i]!==8'd64) $fatal(1,"4x scale changed");
 rst=1;@(negedge clk);if(done || we) $fatal(1,"Reset publication");rst=0;writes=0;
 repeat(515) tick(0);if(!done || writes!=512) $fatal(1,"Reset restart");
 $display("PASS: rising-zero trigger, silence timeout, 512 ordered signed samples, clipping, ownership pause, reset");
 $display("ALL TESTS PASSED");$finish;
 end
 initial begin #1000000;$fatal(1,"Scope watchdog");end
endmodule
