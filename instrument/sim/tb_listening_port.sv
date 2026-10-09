`timescale 1ns/1ps
module tb_listening_port;
 reg clk=0;always #10 clk=~clk;
 reg rst=1,pc=0,ec=0,rv=0;reg signed [15:0] ps=0,es=0;reg [95:0] payload=0;
 wire ce,ext,ready,valid,update;wire signed [15:0] value;wire [31:0] index;wire [95:0] latest;
 wire external_ce;wire signed [15:0] external_value;wire [31:0] external_index;
 listening_analysis_port #(.EXPIRE_CYCLES(8)) dut(.clk(clk),.rst(rst),.playback_ce(pc),.playback_sample(ps),
 .external_ce(ec),.external_sample(es),.analysis_ce(ce),.analysis_sample(value),.analysis_external(ext),
 .sample_index(index),.result_valid(rv),.result_payload(payload),.result_ready(ready),
 .latest_result(latest),.latest_valid(valid),.result_update(update));
 listening_analysis_port #(.SOURCE_EXTERNAL(1)) external_dut(.clk(clk),.rst(rst),.playback_ce(pc),.playback_sample(ps),
 .external_ce(ec),.external_sample(es),.analysis_ce(external_ce),.analysis_sample(external_value),
 .analysis_external(),.sample_index(external_index),.result_valid(1'b0),.result_payload(96'd0),
 .result_ready(),.latest_result(),.latest_valid(),.result_update());
 initial begin
 repeat(3) @(negedge clk);if(ce || ready || valid) $fatal(1,"Reset qualification");rst=0;
 pc=1;ps=-1234;es=5678;#1;
 if(!ce || value!=-1234 || ext || external_ce) $fatal(1,"Source separation");
 @(negedge clk);pc=0;if(index!=1 || external_index!=0) $fatal(1,"Sample index");
 ec=1;#1;if(!external_ce || external_value!=5678 || ce) $fatal(1,"External selection");
 @(negedge clk);ec=0;if(external_index!=1) $fatal(1,"External sample index");
 rv=1;payload=96'h123456789ABCDEF001234567;@(negedge clk);rv=0;
 if(!ready || !valid || !update || latest!==payload) $fatal(1,"Result handshake");
 @(negedge clk);if(update) $fatal(1,"Update must pulse");
 repeat(7) @(negedge clk);if(valid) $fatal(1,"Stale result did not expire without samples");
 rv=1;payload=96'h99;@(negedge clk);rv=0;if(!valid || latest!==payload) $fatal(1,"Fresh result");
 rst=1;@(negedge clk);if(valid || index || latest) $fatal(1,"Reset state");
 $display("PASS: source identity, signed PCM, monotonically indexed samples, result handshake, wall-clock stale expiry, reset");
 $display("ALL TESTS PASSED");$finish;
 end
 initial begin #100000;$fatal(1,"Analysis-port watchdog");end
endmodule
