`timescale 1ns/1ps
// Single-master, open-drain register access. Read transactions fetch two bytes,
// ACK the first, NACK the last. All timing uses clk enables (no fabric clocks).
module i2c_register_master #(
    parameter integer QUARTER = 125,
    parameter integer TIMEOUT = 2500000
)(
    input wire clk, input wire rst,
    input wire start, input wire reading,
    input wire [7:0] address, input wire [7:0] value,
    output reg busy = 0, output reg done = 0, output reg failed = 0,
    output reg [15:0] result = 0,
    inout wire scl, inout wire sda
);
    reg scl_low = 0, sda_low = 0;
    assign scl = scl_low ? 1'b0 : 1'bz;
    assign sda = sda_low ? 1'b0 : 1'bz;
    reg [1:0] scl_sync = 3, sda_sync = 3;
    always @(posedge clk) begin
        scl_sync <= {scl_sync[0], scl};
        sda_sync <= {sda_sync[0], sda};
    end
    localparam IDLE=0, START_A=1, START_B=2, TX_A=3, TX_B=4,
        TX_C=5, TX_D=6, ACK_A=7, ACK_B=8, ACK_C=9, ACK_D=10,
        RESTART_A=11, RESTART_B=12, RESTART_C=13,
        RX_A=14, RX_B=15, RX_C=16, RX_D=17,
        MACK_A=18, MACK_B=19, MACK_C=20, MACK_D=21,
        STOP_A=22, STOP_B=23, STOP_C=24, COMPLETE=25;
    reg [4:0] state = IDLE;
    reg [15:0] divider = 0;
    reg [31:0] watchdog = 0;
    reg rd = 0, second = 0;
    reg [1:0] tx_index = 0;
    reg [2:0] bit_index = 7;
    reg [7:0] reg_addr = 0, reg_value = 0, tx = 0, rx = 0;
    always @(posedge clk) begin
        done <= 0;
        if (rst) begin
            state <= IDLE; busy <= 0; failed <= 0; result <= 0;
            scl_low <= 0; sda_low <= 0; divider <= 0; watchdog <= 0;
        end else if (!busy) begin
            divider <= 0; watchdog <= 0;
            if (start) begin
                busy <= 1; failed <= 0; rd <= reading;
                reg_addr <= address; reg_value <= value;
                result <= 0; tx <= 8'hB4; tx_index <= 0;
                bit_index <= 7; second <= 0; state <= START_A;
            end
        end else if (watchdog == TIMEOUT-1) begin
            // A held-low line must never leave the FPGA holding the other line.
            scl_low <= 0; sda_low <= 0; busy <= 0;
            failed <= 1; done <= 1; state <= IDLE;
        end else begin
            watchdog <= watchdog + 1;
            if (divider == QUARTER-1) begin
                divider <= 0;
                case (state)
                    START_A: if (scl_sync[1] && sda_sync[1]) begin
                        sda_low <= 1; state <= START_B;
                    end
                    START_B: begin scl_low <= 1; state <= TX_A; end
                    TX_A: begin sda_low <= !tx[bit_index]; state <= TX_B; end
                    TX_B: begin scl_low <= 0; state <= TX_C; end
                    TX_C: if (scl_sync[1]) state <= TX_D;
                    TX_D: begin
                        scl_low <= 1;
                        if (bit_index == 0) state <= ACK_A;
                        else begin bit_index <= bit_index-3'd1; state <= TX_A; end
                    end
                    ACK_A: begin sda_low <= 0; state <= ACK_B; end
                    ACK_B: begin scl_low <= 0; state <= ACK_C; end
                    ACK_C: if (scl_sync[1]) begin
                        if (sda_sync[1]) failed <= 1;
                        state <= ACK_D;
                    end
                    ACK_D: begin
                        scl_low <= 1; bit_index <= 7;
                        if (failed) state <= STOP_A;
                        else if (tx_index == 0) begin
                            tx <= reg_addr; tx_index <= 1; state <= TX_A;
                        end else if (tx_index == 1) begin
                            tx_index <= 2;
                            if (rd) state <= RESTART_A;
                            else begin tx <= reg_value; state <= TX_A; end
                        end else if (rd) state <= RX_A;
                        else state <= STOP_A;
                    end
                    RESTART_A: begin sda_low <= 0; state <= RESTART_B; end
                    RESTART_B: begin scl_low <= 0; state <= RESTART_C; end
                    RESTART_C: if (scl_sync[1]) begin
                        sda_low <= 1; tx <= 8'hB5; state <= START_B;
                    end
                    RX_A: begin sda_low <= 0; state <= RX_B; end
                    RX_B: begin scl_low <= 0; state <= RX_C; end
                    RX_C: if (scl_sync[1]) begin
                        rx[bit_index] <= sda_sync[1]; state <= RX_D;
                    end
                    RX_D: begin
                        scl_low <= 1;
                        if (bit_index == 0) state <= MACK_A;
                        else begin bit_index <= bit_index-3'd1; state <= RX_A; end
                    end
                    MACK_A: begin
                        sda_low <= !second;
                        if (second) result[15:8] <= rx;
                        else result[7:0] <= rx;
                        state <= MACK_B;
                    end
                    MACK_B: begin scl_low <= 0; state <= MACK_C; end
                    MACK_C: if (scl_sync[1]) state <= MACK_D;
                    MACK_D: begin
                        scl_low <= 1;
                        if (second) state <= STOP_A;
                        else begin second <= 1; bit_index <= 7; state <= RX_A; end
                    end
                    STOP_A: begin sda_low <= 1; state <= STOP_B; end
                    STOP_B: begin scl_low <= 0; state <= STOP_C; end
                    STOP_C: if (scl_sync[1]) begin
                        sda_low <= 0; state <= COMPLETE;
                    end
                    COMPLETE: begin busy <= 0; done <= 1; state <= IDLE; end
                    default: begin failed <= 1; state <= STOP_A; end
                endcase
            end else divider <= divider+16'd1;
        end
    end
endmodule
