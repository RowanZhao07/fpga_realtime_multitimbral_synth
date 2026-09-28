`timescale 1ns/1ps
// Check the actual board top at 50 MHz, without replacing its clock/reset logic.
module tb_board_clock;
    GSR GSR(.GSRI(1'b1));
    reg clk=0;
    always #10 clk=~clk;
    tri1 scl, sda;
    wire bck, lrck, din;
    wire [7:0] led;
    instrument_top dut(.ref_clk(clk),.mpr_scl(scl),.mpr_sda(sda),
        .dac_bck(bck),.dac_lrck(lrck),.dac_din(din),.led(led));
    time previous_bck=0, previous_frame=0;
    integer edges=0, frames=0;
    always @(bck) if(!dut.rst) begin
        if(previous_bck!=0 && $time-previous_bck!=160)
            $fatal(1,"BCK half-period must be 160 ns at 50 MHz");
        previous_bck=$time;
    end
    always @(posedge bck) begin
        edges=edges+1;
        if($isunknown({lrck,din})) $fatal(1,"Unknown I2S output after reset");
    end
    always @(negedge lrck) if(!dut.rst) begin
        if(previous_frame!=0) begin
            if($time-previous_frame!=20480 || edges!=64)
                $fatal(1,"Expected 48.828125 kHz frames and 64 BCK per frame");
            frames=frames+1;
        end
        previous_frame=$time;
        edges=0;
        if(frames==256) begin
            $display("PASS: board top 50 MHz, BCK 3.125 MHz, LRCK 48.828125 kHz; 256 continuous frames");
            $display("ALL TESTS PASSED");
            $finish;
        end
    end
    initial begin
        #6000000;
        $fatal(1,"Board-clock test timed out");
    end
endmodule
