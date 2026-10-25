`timescale 1ns/1ps
module tb_echo;
    reg clk=0; always #10 clk=~clk;
    reg rst=1,valid=0,echo_enable=1;
    reg signed [18:0] mixed=0;
    wire signed [15:0] sample;
    wire clipped;
    audio_output #(.DELAY_BITS(3)) dut(.clk(clk),.rst(rst),.valid(valid),
        .mixed(mixed),.volume(13'd4096),.calibration(1'b0),.echo_enable(echo_enable),.sample(sample),.clipped(clipped));
    task frame(input integer x);
        begin
            @(negedge clk); mixed=x; valid=1;
            @(negedge clk); valid=0; repeat(6) @(negedge clk);
            if((^sample)===1'bx) $fatal(1,"Uninitialized echo RAM escaped mask");
        end
    endtask
    initial begin
        repeat(3) @(negedge clk); rst=0;
        repeat(4100) frame(0);
        frame(500); if(sample!=4000) $fatal(1,"Dry impulse %d",sample);
        repeat(7) begin frame(0); if(sample!=0) $fatal(1,"Echo too early"); end
        frame(0); if(sample!=1000) $fatal(1,"Echo tap amplitude %d",sample);
        repeat(16) begin frame(0); if(sample!=0) $fatal(1,"Feed-forward echo repeated"); end
        echo_enable=0; frame(500); repeat(8) frame(0);
        if(sample!=0) $fatal(1,"Bypass failed");
        $display("PASS: block RAM startup mask, exact delay, quarter-level echo and bypass");
        $display("ALL TESTS PASSED"); $finish;
    end
    initial begin #10000000; $fatal(1,"Echo watchdog"); end
endmodule
