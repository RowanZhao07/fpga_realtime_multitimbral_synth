`timescale 1ns/1ps
// Board capture: ? LF TX= CR LF T ... with valid UART framing.
// Model the suspected feedback source separately: each UART reply causes TX=.
module tb_uart_tx_notice;
    reg clk=0; always #10 clk=~clk;
    reg rst=1,rx=1,feedback=0;
    wire tx,valid,error;
    wire [7:0] command,accepted,rejected;
    wire [15:0] value;
    wire [83:0] diagnostics;
    uart_control #(.CLOCKS_PER_BIT(32),.TIMEOUT_CLOCKS(8000)) dut(
        .clk(clk),.rst(rst),.rx(rx),.tx(tx),.command_ok(1'b1),
        .command_valid(valid),.input_error(error),.command(command),.value(value),
        .accepted(accepted),.rejected(rejected),.diagnostics(diagnostics));
    integer replies=0,events=0,errors=0,notices=0;
    reg [7:0] last_reply;
    always @(posedge clk) begin
        if(valid) events=events+1;
        if(error) errors=errors+1;
    end
    initial forever begin
        @(negedge tx);repeat(48) @(negedge clk);
        for(integer i=0;i<8;i=i+1) begin last_reply[i]=tx;repeat(32) @(negedge clk);end
        if(tx!==1) $fatal(1,"Bad reply stop bit");
        replies=replies+1;
    end
    task byte_in(input [7:0] b,input bit good_stop=1);
        @(negedge clk);rx=0;repeat(32) @(negedge clk);
        for(integer i=0;i<8;i=i+1) begin rx=b[i];repeat(32) @(negedge clk);end
        rx=good_stop;repeat(32) @(negedge clk);rx=1;
    endtask
    task text_in(input string s);
        for(integer i=0;i<s.len();i=i+1) byte_in(s[i]);
    endtask
    initial forever begin
        wait(feedback && replies>notices);
        notices=notices+1;
        text_in("TX=");byte_in(13);byte_in(10);
    end
    task expect_line(input string s,input [7:0] expected);
        integer before_reply;
        begin
            before_reply=replies;
            text_in(s);byte_in(10);repeat(500) @(negedge clk);
            if(replies!=before_reply+1 || last_reply!==expected)
                $fatal(1,"Line %s reply %h count %0d",s,last_reply,replies-before_reply);
        end
    endtask
    integer before_reply,before_event,before_error;
    initial begin
        repeat(5) @(negedge clk);rst=0;
        feedback=1;text_in("?");byte_in(10);
        repeat(40000) @(negedge clk);
        $display("Feedback replay: replies=%0d commands=%0d errors=%0d first=%h B=%0d F=%0d",
            replies,accepted,rejected,diagnostics[63:0],diagnostics[83:76],diagnostics[75:68]);
        if(replies!=1 || last_reply!="K" || accepted!=1 || rejected!=0 || events!=1 || errors!=0)
            $fatal(1,"TX= notification must not cause an E feedback loop");
        if(diagnostics!=={8'd7,8'd0,4'd7,64'h3F0A54583D0D0A00})
            $fatal(1,"Ignored notification must remain visible in raw diagnostics");
        feedback=0;
        before_reply=replies;before_event=events;before_error=errors;
        // Exact complete lines are status, including a burst with no extra idle.
        repeat(3) begin text_in("TX=");byte_in(13);byte_in(10);end
        text_in("TX=");byte_in(10);
        repeat(9000) @(negedge clk);
        if(replies!=before_reply || events!=before_event || errors!=before_error)
            $fatal(1,"Status generated a reply, command, or delayed timeout");
        // Never swallow a similar invalid command or turn a suffix into a command.
        expect_line("T0","K");expect_line("T3","K");
        expect_line("TX","E");expect_line("TX=0","E");
        expect_line("TX=?","E");expect_line("TTX=","E");
        expect_line("VTX=","E");expect_line("TX=TX=","E");
        expect_line("tx=","E");expect_line("?TX=","E");
        // A corrupt notification must still invalidate a line.
        before_reply=replies;
        text_in("TX");byte_in("=",0);byte_in(13);byte_in(10);
        repeat(500) @(negedge clk);
        if(replies!=before_reply+1 || last_reply!="E") $fatal(1,"Framing error was hidden");
        before_reply=replies;
        byte_in("!",0);repeat(4) @(negedge clk);text_in("TX=");byte_in(10);
        repeat(500) @(negedge clk);
        if(replies!=before_reply+1 || last_reply!="E") $fatal(1,"Preceding framing error was hidden");
        // Unterminated TX= still times out; a later delimiter restores parsing.
        before_reply=replies;text_in("TX=");repeat(8500) @(negedge clk);
        if(replies!=before_reply+1 || last_reply!="E") $fatal(1,"Unterminated status bypassed timeout");
        byte_in(10);expect_line("T1","K");
        before_reply=replies;text_in("TX");
        rst=1;repeat(5) @(negedge clk);rst=0;
        expect_line("=","E");expect_line("?","K");
        $display("PASS: captured TX= feedback stops; exact status only; commands/framing/timeout/reset retained");
        $display("ALL TESTS PASSED");$finish;
    end
    initial begin #20000000;$fatal(1,"TX notice watchdog");end
endmodule
