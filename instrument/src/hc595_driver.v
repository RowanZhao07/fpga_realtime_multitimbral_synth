`timescale 1ns/1ps
module hc595_driver #(
    parameter integer HALF_PERIOD=250,
    parameter integer REFRESH_CYCLES=50000
)(
    input wire clk,rst,
    input wire [7:0] lights,
    output reg serial_data=0,shift_clock=0,latch_clock=0,oe_n=1
);
    // 50 MHz / (2*250) = 100 kHz SRCLK. QA receives lights[0].
    // Snapshot each frame so changing keys never tears a shifted pattern.
    localparam IDLE=0,RISE=1,FALL=2,LATCH=3,FINISH=4;
    localparam integer TIMER_MAX=HALF_PERIOD>REFRESH_CYCLES ? HALF_PERIOD : REFRESH_CYCLES;
    localparam integer TIMER_BITS=TIMER_MAX>1 ? $clog2(TIMER_MAX) : 1;
    reg [2:0] state=IDLE,bit_index=7;
    reg [TIMER_BITS-1:0] timer=0;
    reg [7:0] frame=0;
    reg initializing=1;
    always @(posedge clk) begin
        if(rst) begin
            state<=IDLE;bit_index<=7;timer<=0;frame<=0;initializing<=1;
            serial_data<=0;shift_clock<=0;latch_clock<=0;oe_n<=1;
        end else if(timer!=0) timer<=timer-1'b1;
        else case(state)
            IDLE: begin
                frame<=initializing ? 8'h00 : lights;
                serial_data<=initializing ? 1'b0 : lights[7];
                bit_index<=7;timer<=HALF_PERIOD-1;state<=RISE;
            end
            RISE: begin
                shift_clock<=1;timer<=HALF_PERIOD-1;state<=FALL;
            end
            FALL: begin
                shift_clock<=0;timer<=HALF_PERIOD-1;
                if(bit_index==0) state<=LATCH;
                else begin
                    bit_index<=bit_index-1'b1;frame<={frame[6:0],1'b0};
                    serial_data<=frame[6];state<=RISE;
                end
            end
            LATCH: begin
                latch_clock<=1;timer<=HALF_PERIOD-1;state<=FINISH;
            end
            FINISH: begin
                // First complete transfer was zero; it is now safe to enable.
                latch_clock<=0;oe_n<=0;initializing<=0;
                timer<=REFRESH_CYCLES-1;state<=IDLE;
            end
            default: begin
                state<=IDLE;timer<=0;initializing<=1;
                serial_data<=0;shift_clock<=0;latch_clock<=0;oe_n<=1;
            end
        endcase
    end
endmodule
