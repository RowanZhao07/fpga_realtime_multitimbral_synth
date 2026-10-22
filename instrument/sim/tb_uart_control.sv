`timescale 1ns/1ps
// Bit-level stimulus catches UART polarity/bit order, framing, parser bounds,
// CRLF double execution, and stale commands after a broken transmission.
module tb_uart_control;
    reg clk=0; always #10 clk=~clk;
    reg rst=1,rx=1,command_ok=1;
    wire tx,valid,error;
    wire [7:0] command,accepted,rejected;
    wire [15:0] value;
    uart_control #(.CLOCKS_PER_BIT(32),.TIMEOUT_CLOCKS(8000)) dut(
        .clk(clk),.rst(rst),.rx(rx),.tx(tx),.command_valid(valid),
        .command(command),.value(value),.command_ok(command_ok),
        .input_error(error),.accepted(accepted),.rejected(rejected));
    integer replies=0,events=0;
    reg [7:0] last_reply,last_command;
    reg [15:0] last_value;
    always @(posedge clk) if(valid) begin
        events=events+1;last_command=command;last_value=value;
    end
    initial forever begin
        @(negedge tx); repeat(48) @(negedge clk);
        for(integer b=0;b<8;b=b+1) begin
            last_reply[b]=tx; repeat(32) @(negedge clk);
        end
        if(tx!==1) $fatal(1,"UART reply stop bit");
        replies=replies+1;
    end
    task byte_in(input [7:0] b,input bit good_stop=1);
        @(negedge clk);rx=0;repeat(32) @(negedge clk);
        for(integer i=0;i<8;i=i+1) begin rx=b[i];repeat(32) @(negedge clk);end
        rx=good_stop;repeat(32) @(negedge clk);rx=1;
    endtask
    task line(input string s,input [7:0] want);
        integer before_reply;
        begin
            before_reply=replies;
            for(integer i=0;i<s.len();i=i+1) byte_in(s[i]);
            byte_in(10);repeat(500) @(negedge clk);
            if(replies!=before_reply+1 || last_reply!==want)
                $fatal(1,"Command %s: reply %h count %0d expected %h",s,last_reply,replies-before_reply,want);
        end
    endtask
    initial begin
        repeat(5) @(negedge clk);rst=0;
        line("?","K");
        line("L255","K");if(last_command!="L" || last_value!=255) $fatal(1,"All-lamp diagnostic parse");
        line("L24","K");if(last_value!=24) $fatal(1,"F4/G4 lamp mask parse");
        line("L0","K");line("L256","K");
        line("L257","E");line("L-1","E");line("LFF","E");line("L","E");
        line("J0","K");line("J256","K");
        if(last_command!="J" || last_value!=256) $fatal(1,"PCB LED9 parse");
        line("J4096","K");line("J8191","K");line("J8192","K");
        line("J8193","E");line("J-1","E");line("JFFFF","E");line("J","E");line("J00000","E");
        line("T3","K");if(last_command!="T" || last_value!=3) $fatal(1,"Timbre parse");
        line("D1","K");if(last_command!="D" || last_value!=1) $fatal(1,"Debug enable parse");
        line("D0","K");if(last_command!="D" || last_value!=0) $fatal(1,"Debug disable parse");
        line("D2","E");line("D01","E");line("D","E");
        line("H1","K");line("H0","K");line("H2","E");line("H01","E");line("H","E");
        line("P0","E");line("P1","E"); // Removed page commands must not execute.
        line("P2","E");line("P01","E");line("P","E");
        line("V4096","K");if(last_value!=4096) $fatal(1,"Volume upper bound");
        line("V0","K");if(last_value!=0) $fatal(1,"Mute parse");
        line("T4","E");line("V4097","E");line("V99999","E");
        line("G2","E");line("B39","E");line("B241","E");
        line("B40","K");line("B240","K");
        line("A1001","K");if(last_value!=16'h1001) $fatal(1,"Score hex decode");
        line("A0000","K");line("A2000","E");line("A000g","E");
        line("A001","E");line("R0","E");line("V-1","E");
        command_ok=0;line("Z","E");command_ok=1;
        line($sformatf("E1%c",13),"K"); // CRLF must execute once.
        byte_in("T");byte_in("2",0);byte_in(10);repeat(500) @(negedge clk);
        if(last_reply!="E") $fatal(1,"Bad stop bit accepted");
        line("T1","K");
        // Reach the timer boundary without simulating a one-second hardware gap.
        // The real UART supplies LF; a received byte at the deadline wins.
        byte_in("V");byte_in("4");
        fork
            byte_in(10);
            begin
                @(posedge dut.byte_valid);
                force dut.timeout_count=7999;
                @(posedge clk);#1;release dut.timeout_count;
            end
        join
        repeat(500) @(negedge clk);
        if(last_reply!="K" || last_command!="V" || last_value!=4)
            $fatal(1,"Deadline LF must execute once and acknowledge success, never E plus execution");
        byte_in("V");byte_in("4");repeat(8500) @(negedge clk);
        if(last_reply!="E") $fatal(1,"Partial command timeout not reported");
        // Reconnect invalidation clears drop state without executing a suffix.
        byte_in("!");byte_in(10);repeat(500) @(negedge clk);
        line("?","K");
        // Never end a stale pending commit with a bare LF when reconnecting.
        byte_in("Z");line("!","E");
        line("V2048","K");
        if(last_value!=2048) $fatal(1,"Parser did not recover");
        $display("ALL TESTS PASSED");$finish;
    end
    initial begin #20000000; $fatal(1,"UART control watchdog"); end
endmodule
