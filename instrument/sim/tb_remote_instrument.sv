`timescale 1ns/1ps
// End-to-end serial commands -> real instrument controls -> guide lamps/audio.
module tb_remote_instrument;
    reg clk=0;always #10 clk=~clk;
    reg rst=1,rx=1,online=1;reg [17:0] touched=0;
    wire tx,ce;wire [52:0] status;wire [44:0] remote_status;
    wire [83:0] uart_diagnostics;
    wire diagnostics_visible;
    wire [7:0] volume_low;
    wire [7:0] lamps;wire signed [15:0] sample;
    instrument_core #(.UART_CLOCKS_PER_BIT(32)) dut(.clk(clk),.rst(rst),.online(online),
        .touched(touched),.chip_online(2'b11),.pressure_online(1'b0),.pressure_mv(12'd0),
        .control_rx(rx),.control_tx(tx),.control_status(remote_status),.uart_diagnostics(uart_diagnostics),
        .diagnostics_visible(diagnostics_visible),.volume_low(volume_low),
        .key_lights(lamps),.status(status),.monitor_sample(sample),.monitor_ce(ce),
        .dac_bck(),.dac_lrck(),.dac_din(),.led());
    task byte_in(input [7:0] b);
        @(negedge clk);rx=0;repeat(32) @(negedge clk);
        for(integer i=0;i<8;i=i+1) begin rx=b[i];repeat(32) @(negedge clk);end
        rx=1;repeat(32) @(negedge clk);
    endtask
    task send(input string s);
        for(integer i=0;i<s.len();i=i+1) byte_in(s[i]);
        byte_in(10);repeat(500) @(negedge clk);
    endtask
    task send_with_notice(input string s);
        send(s);
        byte_in("T");byte_in("X");byte_in("=");byte_in(13);byte_in(10);
        repeat(500) @(negedge clk);
    endtask
    task frames(input integer n);repeat(n) begin @(posedge ce);@(negedge clk);end endtask
    integer peak;
    initial begin
        repeat(5) @(negedge clk);rst=0;
        if(diagnostics_visible!==0) $fatal(1,"Default instrument display must be clean");
        send("T2");if(status[17:16]!=2) $fatal(1,"UART did not change real timbre");
        if(uart_diagnostics!=={8'd3,8'd0,4'd3,64'h54320A0000000000})
            $fatal(1,"Actual UART evidence did not reach the instrument diagnostics output");
        send_with_notice("D1");
        if(!diagnostics_visible || status[17:16]!=2) $fatal(1,"Debug enable altered the timbre or did not latch");
        send_with_notice("D0");
        if(diagnostics_visible || uart_diagnostics[83:76]!=19) $fatal(1,"Debug hide must preserve raw byte diagnostics");
        send("V4095");if({status[22:18],volume_low}!==13'd4095) $fatal(1,"Display gain must preserve UART low bits");
        send("V4000");touched=18'h400;frames(2);touched=0;frames(2);
        if(status[22:18]!=16) $fatal(1,"Local volume up overflow after arbitrary remote volume");
        send("E1");if(!status[25]) $fatal(1,"Remote echo enable");send("E0");
        send("B90");if(remote_status[20:13]!=90) $fatal(1,"Remote tempo update");
        // Transport status between upload lines must not poison the staging score.
        send_with_notice("N");send_with_notice("A0015");send_with_notice("A0100");
        send_with_notice("Z");send_with_notice("G1");frames(3);
        if(remote_status[44:37]!=0) $fatal(1,"Transport status counted as an upload error");
        if(!status[27] || lamps!==8'h15 || remote_status[12:0]!=13'h15)
            $fatal(1,"Uploaded chord guide did not reach LEDs");
        if(status[7:0]!=0 || status[44:40]!=0) $fatal(1,"Score auto-played audio");
        touched=18'h15;frames(3);touched=0;frames(3);
        if(remote_status[12:0]!=13'h100 || lamps!=0 || status[36:31]!=1)
            $fatal(1,"Guide did not advance to sharp note");
        touched=18'h1000;frames(3);touched=0;frames(3);
        if(status[36:31]!=0) $fatal(1,"Sharp electrode did not complete score");
        send("G0");send("T0");send("V2048");touched=1;frames(2500);
        peak=0;
        repeat(300) begin frames(1);if(sample>peak) peak=sample;end
        if(peak<100) $fatal(1,"Remote control broke live audio");
        send("V0");frames(2500);
        repeat(100) begin frames(1);if(sample!==0) $fatal(1,"Remote mute did not reach audio output");end
        online=0;send("G1");send("V2048");frames(3);
        if(lamps!=0 || status[7:0]!=0) $fatal(1,"Remote commands bypassed touch-offline gating");
        $display("ALL TESTS PASSED");$finish;
    end
    initial begin #200000000;$fatal(1,"Remote instrument watchdog");end
endmodule

module tb_tempo;
    reg clk=0;always #10 clk=~clk;
    reg rst=1;reg [7:0] bpm=120;
    wire flash,beat;
    tempo_clock #(.CLOCK_HZ(1000),.FLASH_CLOCKS(50)) dut(.clk(clk),.rst(rst),.bpm(bpm),.flash(flash),.beat(beat));
    integer count=0;
    always @(negedge clk) if(!rst && beat) count=count+1;
    initial begin
        repeat(5) @(negedge clk);rst=0;repeat(1001) @(posedge clk);#1;
        if(count!=2) $fatal(1,"120 BPM must produce two beats/second");
        @(negedge clk);bpm=60;repeat(3) @(negedge clk);count=0;
        repeat(1001) @(posedge clk);#1;
        if(count!=1) $fatal(1,"60 BPM must produce one beat/second");
        $display("ALL TESTS PASSED");$finish;
    end
endmodule
