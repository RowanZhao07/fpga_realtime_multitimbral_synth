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
    inout wire scl, sda, scl_b, sda_b,
    output wire online,
    output wire [1:0] chip_online,
    output wire [17:0] touched,
    output wire [31:0] diagnostics,
    output wire [1:0] failure_event
);
    // Independent buses; both factory ADD-to-GND jumpers stay intact (0x5A).
    // A ELE0..9: K0 S0 K1 S1 K2 K3 S2 K4 S3 K5.
    // B ELE0..7: S4 K6 K7 X0 C0 C1 C2 C3.
    wire [11:0] raw_a,raw_b;
    mpr121_electrode_bank #(.ELECTRODES(10),.QUARTER(QUARTER),.TIMEOUT(TIMEOUT),
        .POWER_WAIT(POWER_WAIT),.RESET_WAIT(RESET_WAIT),.RETRY_WAIT(RETRY_WAIT),.POLL_WAIT(POLL_WAIT)) bank_a (
        .clk(clk),.rst(rst),.scl(scl),.sda(sda),.online(chip_online[0]),.touched(raw_a),.diagnostics(diagnostics[15:0]),.failure_event(failure_event[0]));
    mpr121_electrode_bank #(.ELECTRODES(8),.QUARTER(QUARTER),.TIMEOUT(TIMEOUT),
        .POWER_WAIT(POWER_WAIT),.RESET_WAIT(RESET_WAIT),.RETRY_WAIT(RETRY_WAIT),.POLL_WAIT(POLL_WAIT)) bank_b (
        .clk(clk),.rst(rst),.scl(scl_b),.sda(sda_b),.online(chip_online[1]),.touched(raw_b),.diagnostics(diagnostics[31:16]),.failure_event(failure_event[1]));
    // Preserve fail-closed behavior and the established logical key layout.
    assign online=&chip_online;
    assign touched=online ? {raw_b[3],raw_b[0],raw_a[8],raw_a[6],raw_a[3],raw_a[1],
        raw_b[7:4],raw_b[2],raw_b[1],raw_a[9],raw_a[7],raw_a[5],raw_a[4],raw_a[2],raw_a[0]} : 18'd0;
endmodule

// One physical bus and its own initialization, timeout and retry state.
module mpr121_electrode_bank #(
    parameter [3:0] ELECTRODES=10,
    parameter integer QUARTER=125,
    parameter integer TIMEOUT=2500000,
    parameter integer POWER_WAIT=5000000,
    parameter integer RESET_WAIT=100000,
    parameter integer RETRY_WAIT=25000000,
    parameter integer POLL_WAIT=12500
)(
    input wire clk, rst,
    inout wire scl, sda,
    output reg online=0,
    output reg [11:0] touched=0,
    output wire [15:0] diagnostics,
    output reg failure_event=0
);
    localparam [7:0] ECR={4'h8,ELECTRODES};
    reg start=0, reading=0;
    reg [7:0] address=0, value=0;
    wire busy, done, failed;
    wire [15:0] result;
    wire [3:0] bus_error;
    reg [3:0] last_error=0;
    reg [7:0] failures=0;
    wire [2:0] idle_lines;
    // Preserve the last fault across retries/recovery. 5=config mismatch, 6=OVCF.
    assign diagnostics={busy,idle_lines,failures,last_error};
    i2c_register_master #(.QUARTER(QUARTER), .TIMEOUT(TIMEOUT)) bus (
        .clk(clk), .rst(rst), .start(start), .reading(reading), .device_address(7'h5A),
        .address(address), .value(value), .busy(busy), .done(done),
        .failed(failed), .result(result), .error_code(bus_error),.idle_lines(idle_lines),.scl(scl), .sda(sda)
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
                40: setup_word={8'h5E,ECR}; // only connected electrodes
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
        failure_event<=0;
        if (rst) begin
            online<=0; touched<=0; index<=0; mode<=INIT;
            state<=WAIT; delay_count<=POWER_WAIT;
            reading<=0; address<=0; value<=0;
            last_error<=0;failures<=0;
        end else begin
          if(delay_count!=0) delay_count<=delay_count-1'b1;
          case(state)
            WAIT: if (delay_count==0) state<=ISSUE;
            ISSUE: if (!busy) begin
                reading<=mode!=INIT;
                address<=mode==INIT ? word_to_write[15:8] :
                         (mode==VERIFY ? 8'h5D : 8'h00);
                value<=word_to_write[7:0]; start<=1; state<=FINISH;
            end
            FINISH: if (done) begin
                state<=WAIT; delay_count<=0;
                if (failed || (mode==VERIFY && result!={ECR,8'h20}) ||
                    (mode==POLL && result[15])) begin
                    // NACK, config mismatch or over-current releases this bank.
                    online<=0; touched<=0; mode<=INIT; index<=0;
                    last_error<=failed ? bus_error : mode==VERIFY ? 4'd5 : 4'd6;
                    failure_event<=1;
                    if(failures!=255) failures<=failures+1'b1;
                    delay_count<=RETRY_WAIT;
                end else if (mode==INIT) begin
                    if (index==0) delay_count<=RESET_WAIT;
                    if (index==40) mode<=VERIFY;
                    else index<=index+6'd1;
                end else if (mode==VERIFY) begin
                    // Report ONLINE only after a fresh touch-status read.
                    mode<=POLL; delay_count<=RESET_WAIT;
                end else begin
                    online<=1; touched<=result[11:0];
                    delay_count<=POLL_WAIT;
                end
            end
            default: state<=WAIT;
          endcase
        end
    end
endmodule
