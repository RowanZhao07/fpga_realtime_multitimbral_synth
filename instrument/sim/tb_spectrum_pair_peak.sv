`timescale 1ns/1ps
module tb_spectrum_pair_peak;
 reg clk=0;always #10 clk=~clk;
 reg rst=1,we=0;reg [8:0] addr=0;reg [7:0] value=0;
 wire valid;wire [7:0] pa,pv;
 spectrum_pair_peak dut(.clk(clk),.rst(rst),.write_enable(we),.address(addr),.value(value),.valid(valid),.pair_address(pa),.pair_value(pv));
 integer n;
 initial begin
 repeat(3)@(negedge clk);rst=0;
 for(n=0;n<512;n=n+1)begin
   addr=n;we=1;value=n[0] ? 255-(n/2) : n/2;#1;
   if(valid!==n[0])$fatal(1,"Pair valid");
   if(n[0] && (pa!=n/2 || pv!=((n/2)>127 ? n/2 : 255-n/2)))$fatal(1,"Lost even/odd peak at %0d",n);
   @(negedge clk);we=0;repeat(2)@(negedge clk);
 end
 $display("ALL TESTS PASSED: all 512 FFT bins reduced into 256 peak-preserving pixels");$finish;
 end
endmodule
