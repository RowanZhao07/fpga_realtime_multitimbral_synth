`timescale 1ns/1ps
// All events are one clk wide; consumer must not gate them with audio sample_ce.
module joystick_control #(
    parameter integer CENTER_MV=1650, TRIGGER_MV=800, RETURN_MV=300,
    parameter integer CENTER_SAMPLES=8, BUTTON_CLOCKS=500000,
    parameter REVERSE=1'b0, BUTTON_ACTIVE_LOW=1'b1
)(
    input wire clk,rst,online,sample_valid,allow_octave,
    input wire [11:0] millivolts,
    input wire sw_n,
    output reg octave_up=0,octave_down=0,
    output wire vibrato,
    output reg armed=0
);
    localparam integer BITS=BUTTON_CLOCKS>1 ? $clog2(BUTTON_CLOCKS+1) : 1;
    localparam integer CBITS=CENTER_SAMPLES>1 ? $clog2(CENTER_SAMPLES+1) : 1;
    reg sw_meta=1,sw_sync=1,pressed=0,button_ready=0;
    reg [BITS-1:0] button_count=0;
    reg [CBITS-1:0] center_count=0;
    wire raw_pressed=BUTTON_ACTIVE_LOW ? !sw_sync : sw_sync;
    wire centered=(millivolts>=CENTER_MV-RETURN_MV && millivolts<=CENTER_MV+RETURN_MV);
    assign vibrato=pressed && button_ready;
    always @(posedge clk) begin
        sw_meta<=sw_n;sw_sync<=sw_meta;
        octave_up<=0;octave_down<=0;
        if(rst) begin
            sw_meta<=BUTTON_ACTIVE_LOW;sw_sync<=BUTTON_ACTIVE_LOW;
            pressed<=0;button_ready<=0;button_count<=0;
            center_count<=0;armed<=0;
        end else begin
            // Require a stable released button after reset, then debounce both edges.
            if(!button_ready) begin
                if(raw_pressed) button_count<=0;
                else if(button_count==BUTTON_CLOCKS-1) begin
                    button_ready<=1;button_count<=0;
                end else button_count<=button_count+1'b1;
            end else if(raw_pressed==pressed) button_count<=0;
            else if(button_count==BUTTON_CLOCKS-1) begin
                pressed<=raw_pressed;button_count<=0;
            end else button_count<=button_count+1'b1;
            // Reconnection, GUIDE/test mode and pressing all require a fresh neutral.
            if(!online || !allow_octave || raw_pressed || pressed) begin
                armed<=0;center_count<=0;
            end else if(sample_valid) begin
                if(centered) begin
                    if(center_count==CENTER_SAMPLES-1) armed<=1;
                    else center_count<=center_count+1'b1;
                end else begin
                    center_count<=0;
                    if(armed && millivolts>=CENTER_MV+TRIGGER_MV) begin
                        octave_up<=!REVERSE;octave_down<=REVERSE;armed<=0;
                    end else if(armed && millivolts<=CENTER_MV-TRIGGER_MV) begin
                        octave_down<=!REVERSE;octave_up<=REVERSE;armed<=0;
                    end
                end
            end
        end
    end
endmodule
