`timescale 1ns/1ps
// Strict ASCII lines, LF/CR/CRLF. One-byte K/E reply, no unsolicited traffic.
// Commands do not synthesize note gates. A partial/bad line never executes.
// Complete TX= status lines observed on the Bluetooth link are consumed silently.
module uart_control #(
    parameter integer CLOCKS_PER_BIT=5208,
    parameter integer TIMEOUT_CLOCKS=50000000
)(
    input wire clk,rst,rx,command_ok,
    output wire tx,output reg command_valid=0,input_error=0,
    output reg [7:0] command=0,output reg [15:0] value=0,
    output reg [7:0] accepted=0,rejected=0,
    output wire [83:0] diagnostics);
    wire byte_valid,byte_error,tx_busy;wire [7:0] byte_data;
    reg tx_valid=0;reg [7:0] tx_data=0;
    uart_8n1 #(.CLOCKS_PER_BIT(CLOCKS_PER_BIT)) serial(
        .clk(clk),.rst(rst),.rx(rx),.tx(tx),.tx_valid(tx_valid),.tx_data(tx_data),
        .tx_busy(tx_busy),.rx_data(byte_data),.rx_valid(byte_valid),.rx_error(byte_error));
    // Passive evidence: count bytes/invalid stop bits and freeze the first eight
    // valid bytes after reset, oldest in [63:56]. Missing slots are marked by count.
    reg [7:0] received_bytes=0,framing_errors=0;
    reg [3:0] capture_count=0;
    reg [63:0] first_bytes=0;
    integer trace_index;
    assign diagnostics={received_bytes,framing_errors,capture_count,first_bytes};
    always @(posedge clk) begin
        if(rst) begin
            received_bytes<=0;framing_errors<=0;capture_count<=0;first_bytes<=0;
        end else begin
            if(byte_error && framing_errors!=255) framing_errors<=framing_errors+1'b1;
            if(byte_valid) begin
                if(received_bytes!=255) received_bytes<=received_bytes+1'b1;
                if(capture_count<8) begin
                    for(trace_index=0;trace_index<8;trace_index=trace_index+1)
                        if(capture_count==trace_index) first_bytes[63-8*trace_index -: 8]<=byte_data;
                    capture_count<=capture_count+1'b1;
                end
            end
        end
    end
    reg [7:0] opcode=0;
    reg [2:0] count=0;
    reg [15:0] number=0;
    reg bad=0,dropping=0,reply_pending=0;
    reg tx_notice_match=0;
    wire tx_notice=tx_notice_match && count==3;
    reg [31:0] timeout_count=0;
    wire decimal_digit=byte_data>="0" && byte_data<="9";
    wire hex_upper=byte_data>="A" && byte_data<="F";
    wire hex_lower=byte_data>="a" && byte_data<="f";
    wire [7:0] digit=decimal_digit ? byte_data-8'd48 :
        hex_upper ? byte_data-8'd55 : byte_data-8'd87;
    reg legal;
    always @* begin
        legal=0;
        if(!bad) case(opcode)
        "?","N","Z","R":legal=count==1;
        "T":legal=count==2 && number<=3;
        "D","E","G":legal=count==2 && number<=1;
        "V":legal=count>=2 && count<=5 && number<=4096;
        "L":legal=count>=2 && count<=4 && number<=256;
        "B":legal=count>=2 && count<=4 && number>=40 && number<=240;
        "A":legal=count==5 && number!=0 && number<=16'h1FFF;
        default:legal=0;
        endcase
    end
    always @(posedge clk) begin
        if(rst) begin
            opcode<=0;count<=0;number<=0;bad<=0;dropping<=0;timeout_count<=0;tx_notice_match<=0;
            command_valid<=0;input_error<=0;command<=0;value<=0;
            accepted<=0;rejected<=0;tx_valid<=0;tx_data<=0;reply_pending<=0;
        end else begin
            command_valid<=0;input_error<=0;tx_valid<=0;
            if(reply_pending) begin
                reply_pending<=0;tx_valid<=1;tx_data<=command_ok ? "K" : "E";
                if(command_ok) begin if(accepted!=255) accepted<=accepted+1'b1;end
                else begin if(rejected!=255) rejected<=rejected+1'b1;end
            end
            // A byte/error at the deadline owns this clock; never both time out
            // and execute its delimiter. This also prevents contradictory ACKs.
            if(!byte_valid && !byte_error && !dropping && (count!=0 || bad)) begin
                if(timeout_count==TIMEOUT_CLOCKS-1) begin
                    count<=0;number<=0;bad<=0;dropping<=1;timeout_count<=0;tx_notice_match<=0;
                    input_error<=1;tx_valid<=1;tx_data<="E";
                    if(rejected!=255) rejected<=rejected+1'b1;
                end else timeout_count<=timeout_count+1'b1;
            end else timeout_count<=0;
            if(byte_error) begin bad<=1;timeout_count<=0;tx_notice_match<=0;end
            if(byte_valid) begin
                timeout_count<=0;
                if(byte_data==10 || byte_data==13) begin
                    // A transport status is not a command: replying E here can
                    // provoke another TX= notification and a self-sustaining loop.
                    if(!dropping && !tx_notice && (count!=0 || bad)) begin
                        if(legal) begin
                            command<=opcode;value<=number;command_valid<=1;reply_pending<=1;
                        end else begin
                            input_error<=1;tx_valid<=1;tx_data<="E";
                            if(rejected!=255) rejected<=rejected+1'b1;
                        end
                    end
                    count<=0;number<=0;bad<=0;dropping<=0;tx_notice_match<=0;
                end else if(!dropping) begin
                    // Match only a whole, uncorrupted TX= line. Do not hide TX=0,
                    // prefixes/suffixes, framing errors, or unterminated lines.
                    case(count)
                        0:tx_notice_match<=!bad && byte_data=="T";
                        1:tx_notice_match<=tx_notice_match && byte_data=="X";
                        2:tx_notice_match<=tx_notice_match && byte_data=="=";
                        default:tx_notice_match<=0;
                    endcase
                    if(count==0) begin opcode<=byte_data;count<=1;number<=0;end
                    else if(count==5) bad<=1;
                    else begin
                        count<=count+1'b1;
                        if(opcode=="A" && (decimal_digit || hex_upper || hex_lower))
                            number<={number[11:0],digit[3:0]};
                        else if(opcode!="A" && decimal_digit) number<=number*16'd10+digit;
                        else bad<=1;
                    end
                end
            end
        end
    end
endmodule
