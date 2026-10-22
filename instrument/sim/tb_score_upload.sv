`timescale 1ns/1ps
module tb_score_upload;
    reg clk=0; always #10 clk=~clk;
    reg rst=1,enabled=1,valid=0,input_error=0;
    reg [7:0] command=0;reg [15:0] value=0;
    reg [12:0] gates=0;
    wire ok,custom,correct;wire [12:0] mask;
    wire [9:0] length;wire [8:0] position;
    practice_guide dut(.clk(clk),.rst(rst),.sample_ce(1'b1),.enabled(enabled),.bpm(8'd120),
        .gates(gates),.target(),.position(position),.correct(correct),
        .command_valid(valid),.command(command),.value(value),.input_error(input_error),
        .command_ok(ok),.target_mask(mask),.length(length),.custom(custom));
    task send(input [7:0] c,input [15:0] v,input bit want_ok=1);
        @(negedge clk);command=c;value=v;valid=1;#1;
        if(ok!==want_ok) $fatal(1,"Score command %s accepted=%b",c,ok);
        @(negedge clk);valid=0; repeat(2) @(negedge clk);
    endtask
    task press(input [12:0] m);gates=m;repeat(4) @(negedge clk);endtask
    initial begin
        repeat(5) @(negedge clk);rst=0;repeat(4) @(negedge clk);
        if(mask!==1 || length!=192 || custom) $fatal(1,"Default score mask=%h length=%d custom=%b word=%h",mask,length,custom,dut.event_word);
        send("Z",0,0);send("N",0);send("Z",0,0);send("N",0);
        send("A",16'h0015);send("A",16'h0100);send("A",16'h0100);
        if(mask!=1 || custom) $fatal(1,"Incomplete upload altered live score");
        send("Z",0);
        if(mask!==13'h15 || length!=3 || !custom || position!=0) $fatal(1,"Atomic score commit");
        press(1);press(5);if(position!=0) $fatal(1,"Partial chord advanced");
        press(13'h95);if(position!=0) $fatal(1,"Wrong extra note accepted");
        press(0);press(13'h15);if(position!=1 || mask!=13'h100) $fatal(1,"Correct chord not accepted");
        press(0);press(13'h100);if(position!=2) $fatal(1,"Sharp guide");
        press(13'h100);if(position!=2) $fatal(1,"Held repeat advanced");
        press(0);press(13'h100);if(position!=0) $fatal(1,"Loop after repeated sharp");
        send("N",0);send("A",2);input_error=1;@(negedge clk);input_error=0;
        send("Z",0,0);if(mask!=13'h15 || length!=3) $fatal(1,"Corrupt upload replaced score");
        send("N",0);send("A",2);
        @(negedge clk);command="Z";valid=1;input_error=1;
        @(negedge clk);valid=0;input_error=0;repeat(2) @(negedge clk);
        if(mask!=13'h15 || length!=3) $fatal(1,"Input error must dominate a simultaneous score commit");
        send("N",0);
        for(integer n=0;n<512;n=n+1) send("A",16'h80);
        send("A",16'h40,0);send("Z",0,0);
        send("N",0);
        for(integer n=0;n<512;n=n+1) send("A",16'h80);
        send("Z",0);if(length!=512 || mask!=13'h80) $fatal(1,"512-step score boundary");
        send("R",0);if(custom || length!=192 || mask!=1) $fatal(1,"Restore built-in score");
        $display("ALL TESTS PASSED");$finish;
    end
    initial begin #1000000;$fatal(1,"Score watchdog");end
endmodule
