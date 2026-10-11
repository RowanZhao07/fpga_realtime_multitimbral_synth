`timescale 1ns/1ps
// Capture the external UART evidence without generating traffic or changing replies.
module tb_uart_diagnostics;
    reg clk=0; always #10 clk=~clk;
    reg rst=1,rx=1;
    wire tx,valid,error;
    wire [7:0] command,accepted,rejected;
    wire [15:0] value;
    wire [83:0] diagnostics;
    uart_control #(.CLOCKS_PER_BIT(32),.TIMEOUT_CLOCKS(8000)) dut(
        .clk(clk),.rst(rst),.rx(rx),.tx(tx),.command_ok(1'b1),
        .command_valid(valid),.input_error(error),.command(command),.value(value),
        .accepted(accepted),.rejected(rejected),.diagnostics(diagnostics));
    integer replies=0;
    reg [7:0] reply;
    initial forever begin
        @(negedge tx);repeat(48) @(negedge clk);
        for(integer i=0;i<8;i=i+1) begin reply[i]=tx;repeat(32) @(negedge clk);end
        if(tx!==1) $fatal(1,"Reply has invalid stop bit");
        replies=replies+1;
    end
    task byte_in(input [7:0] b,input bit good_stop=1);
        @(negedge clk);rx=0;repeat(32) @(negedge clk);
        for(integer i=0;i<8;i=i+1) begin rx=b[i];repeat(32) @(negedge clk);end
        rx=good_stop;repeat(32) @(negedge clk);rx=1;
    endtask
    task restart;
        rst=1;rx=1;repeat(5) @(negedge clk);rst=0;repeat(5) @(negedge clk);
    endtask
    initial begin
        restart();
        repeat(40000) @(negedge clk);
        if(diagnostics!==0 || replies!=0) $fatal(1,"Idle diagnostics must stay zero and silent");
        byte_in("?");byte_in(10);repeat(500) @(negedge clk);
        if(accepted!=1 || rejected!=0 || replies!=1 || reply!="K")
            $fatal(1,"A single ping must still produce exactly one K");
        if(diagnostics!=={8'd2,8'd0,4'd2,64'h3F0A000000000000})
            $fatal(1,"Raw capture must preserve query and LF in arrival order");
        byte_in("E");byte_in(13);byte_in(10);byte_in("T");byte_in("1");byte_in(10);
        repeat(500) @(negedge clk);
        if(diagnostics!=={8'd8,8'd0,4'd8,64'h3F0A450D0A54310A})
            $fatal(1,"Capture must retain bytes even when the parser rejects a line");
        if(accepted!=2 || rejected!=1 || replies!=3 || reply!="K")
            $fatal(1,"Diagnostics changed command acceptance or CRLF handling");
        byte_in("R");byte_in(10);repeat(500) @(negedge clk);
        if(diagnostics!=={8'd10,8'd0,4'd8,64'h3F0A450D0A54310A})
            $fatal(1,"First eight bytes must freeze while the total continues");
        byte_in(8'h55,0);repeat(500) @(negedge clk);
        if(diagnostics[83:76]!=10 || diagnostics[75:68]!=1)
            $fatal(1,"Bad stop bit must count separately from valid received bytes");
        // A held-low input reports one framing failure, not a continuing flood.
        restart();rx=0;repeat(40000) @(negedge clk);
        if(diagnostics!=={8'd0,8'd1,4'd0,64'd0}) $fatal(1,"UART break trace");
        rx=1;repeat(40000) @(negedge clk);
        if(diagnostics[75:68]!=1) $fatal(1,"Released break counted repeatedly");
        restart();
        repeat(260) byte_in(8'h30);
        repeat(500) @(negedge clk);
        if(diagnostics!=={8'hFF,8'd0,4'd8,64'h3030303030303030})
            $fatal(1,"Receive counter wrapped or initial evidence was overwritten");
        restart();
        repeat(260) begin byte_in(8'h55,0);repeat(4) @(negedge clk);end
        if(diagnostics[75:68]!=255 || diagnostics[83:76]!=0)
            $fatal(1,"Framing counter wrapped or counted bad frames as data");
        restart();
        if(diagnostics!==0) $fatal(1,"Reset must clear frozen evidence and counters");
        $display("ALL TESTS PASSED");$finish;
    end
    initial begin #20000000;$fatal(1,"Diagnostics watchdog");end
endmodule
