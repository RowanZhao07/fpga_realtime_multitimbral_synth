`timescale 1ns/1ps
// Serial command -> core -> actual shift/latch protocol, independent of X0.
module tb_lamp_diagnostics;
    reg clk=0;always #10 clk=~clk;
    reg rst=1,rx=1,online=1;
    reg [17:0] touched=0;
    wire [7:0] lamps,pins;
    wire [52:0] status;
    wire signed [15:0] sample;
    wire ser,srclk,rclk,oe_n;
    instrument_core #(.UART_CLOCKS_PER_BIT(32),.LAMP_TEST_CLOCKS(50000)) core(.sustain_request(1'b0),
        .clk(clk),.rst(rst),.online(online),.touched(touched),.chip_online(2'b11),
        .pressure_online(1'b0),.pressure_mv(12'd0),.control_rx(rx),.control_tx(),
        .control_status(),.uart_diagnostics(),.diagnostics_visible(),.volume_low(),
        .dac_bck(),.dac_lrck(),.dac_din(),.key_lights(lamps),.led(),
        .status(status),.monitor_sample(sample),.monitor_ce());
    hc595_driver #(.HALF_PERIOD(10),.REFRESH_CYCLES(100)) driver(
        .clk(clk),.rst(rst),.lights(lamps),.serial_data(ser),
        .shift_clock(srclk),.latch_clock(rclk),.oe_n(oe_n));
    hc595_test_device chip(.rst(rst),.ser(ser),.srclk(srclk),.rclk(rclk),
        .oe_n(oe_n),.pins(pins),.storage());
    task byte_in(input [7:0] b);
        @(negedge clk);rx=0;repeat(32) @(negedge clk);
        for(integer bitn=0;bitn<8;bitn=bitn+1) begin rx=b[bitn];repeat(32) @(negedge clk);end
        rx=1;repeat(32) @(negedge clk);
    endtask
    task send(input string s,input [7:0] expected);
        for(integer n=0;n<s.len();n=n+1) byte_in(s[n]);
        byte_in(10);repeat(1500) @(negedge clk);
        if(pins!==expected) $fatal(1,"Lamp diagnostic %s produced %h, expected %h",s,pins,expected);
    endtask
    initial begin
        repeat(5) @(negedge clk);rst=0;
        send("L255",8'hFF);
        if(!status[39] || sample!=0 || status[7:0]!=0 || status[44:40]!=0)
            $fatal(1,"Lamp test must be visible without generating audio gates");
        send("L8",8'h08);send("L16",8'h10);send("L24",8'h18);send("L25",8'h19);
        touched=18'h15;send("L0",0);
        if(status[7:0]!=8'h15) $fatal(1,"Lamp diagnostic changed held notes");
        send("L256",8'h15);
        if(status[39]) $fatal(1,"Explicit diagnostic cancel failed");
        send("L255",8'hFF);
        repeat(51000) @(negedge clk);
        if(status[39] || pins!==8'h15) $fatal(1,"Diagnostic did not expire back to held keys");
        touched=0;online=0;send("L24",8'h18);
        if(status[7:0]!=0 || status[44:40]!=0) $fatal(1,"Offline lamp diagnostic generated notes");
        send("L256",0);
        send("L255",8'hFF);
        rst=1;repeat(5) @(negedge clk);rst=0;repeat(1500) @(negedge clk);
        if(status[39] || pins!==0) $fatal(1,"Reset left diagnostic latched");
        $display("PASS: independent silent lamp masks, touch-offline operation, explicit cancel and timed restore");
        $display("ALL TESTS PASSED");$finish;
    end
    initial begin #5000000;$fatal(1,"Lamp diagnostic watchdog");end
endmodule
