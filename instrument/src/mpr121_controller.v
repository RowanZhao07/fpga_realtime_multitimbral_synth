`timescale 1ns/1ps
module mpr121_controller #(
    parameter integer QUARTER=125,
    parameter integer TIMEOUT=2500000,
    parameter integer POWER_WAIT=5000000,
    parameter integer RESET_WAIT=100000,
    parameter integer RETRY_WAIT=25000000,
    parameter integer POLL_WAIT=12500
)(
    input wire clk, input wire rst,
    inout wire scl, inout wire sda,
    output reg online=0,
    output reg [11:0] touched=0
);
    reg start=0, reading=0;
    reg [7:0] address=0, value=0;
    wire busy, done, failed;
    wire [15:0] result;
    i2c_register_master #(.QUARTER(QUARTER), .TIMEOUT(TIMEOUT)) bus (
        .clk(clk), .rst(rst), .start(start), .reading(reading),
        .address(address), .value(value), .busy(busy), .done(done),
        .failed(failed), .result(result), .scl(scl), .sda(sda)
    );
    // NXP register map: stop sensing, configure filters/thresholds, then run.
    // Fixed acquisition current and time match the connected copper electrodes.
    function [15:0] setup_word;
        input [5:0] n;
        begin
            case(n)
                0: setup_word=16'h8063; // soft reset
                1: setup_word=16'h5E00; // stop
                2: setup_word=16'h2B01; 3: setup_word=16'h2C01;
                4: setup_word=16'h2D0E; 5: setup_word=16'h2E00;
                6: setup_word=16'h2F01; 7: setup_word=16'h3005;
                8: setup_word=16'h3101; 9: setup_word=16'h3200;
                10: setup_word=16'h3300; 11: setup_word=16'h3400;
                12: setup_word=16'h3500;
                37: setup_word=16'h5B11; // two consecutive detections for touch and release
                38: setup_word=16'h5C10; // 16 uA
                39: setup_word=16'h5D20; // 0.5 us, 1 ms sampling
                40: setup_word=16'h5E8C; // baseline tracking, 12 electrodes
                default: begin
                    setup_word[15:8]=8'h41+({2'b00,n}-8'd13);
                    setup_word[7:0]=n[0] ? 8'd12 : 8'd6;
                end
            endcase
        end
    endfunction
    reg [5:0] index=0;
    wire [15:0] word_to_write=setup_word(index);
    localparam WAIT=0, ISSUE=1, FINISH=2;
    localparam INIT=0, VERIFY=1, POLL=2;
    reg [1:0] state=WAIT, mode=INIT;
    reg [31:0] delay_count=POWER_WAIT;
    always @(posedge clk) begin
        start<=0;
        if (rst) begin
            online<=0; touched<=0; index<=0; mode<=INIT;
            state<=WAIT; delay_count<=POWER_WAIT;
        end else case(state)
            WAIT: if (delay_count==0) state<=ISSUE;
                  else delay_count<=delay_count-1;
            ISSUE: if (!busy) begin
                reading<=mode!=INIT;
                address<=mode==INIT ? word_to_write[15:8] :
                         (mode==VERIFY ? 8'h5D : 8'h00);
                value<=word_to_write[7:0]; start<=1; state<=FINISH;
            end
            FINISH: if (done) begin
                state<=WAIT; delay_count<=0;
                if (failed || (mode==VERIFY && result!=16'h8C20)) begin
                    online<=0; touched<=0; mode<=INIT; index<=0;
                    delay_count<=RETRY_WAIT;
                end else if (mode==INIT) begin
                    if (index==0) delay_count<=RESET_WAIT;
                    if (index==40) mode<=VERIFY;
                    else index<=index+6'd1;
                end else if (mode==VERIFY) begin
                    online<=1; mode<=POLL; delay_count<=RESET_WAIT;
                end else if (result[15]) begin
                    // MPR121 over-current status is a fault, not a key press.
                    online<=0; touched<=0; mode<=INIT; index<=0;
                    delay_count<=RETRY_WAIT;
                end else begin
                    online<=1; touched<=result[11:0]; delay_count<=POLL_WAIT;
                end
            end
            default: state<=WAIT;
        endcase
    end
endmodule
