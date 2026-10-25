`timescale 1ns/1ps
// Independent 512-sample snapshot. Rising-zero trigger, bounded wait in silence.
// No sample-stream backpressure: only the visual snapshot waits for bank ownership.
module waveform_capture #(parameter integer TRIGGER_TIMEOUT=128)(
    input wire clk,rst,sample_ce,input wire signed [15:0] sample,
    output reg write_enable=0,output reg [8:0] write_address=0,
    output reg [7:0] write_value=0,output reg frame_done=0,input wire frame_ack);
    localparam ARM=0,CAPTURE=1,WAIT_ACK=2;
    reg [1:0] state=ARM;
    localparam WAIT_BITS=TRIGGER_TIMEOUT>1 ? $clog2(TRIGGER_TIMEOUT) : 1;
    reg [WAIT_BITS-1:0] waited=0;
    reg signed [15:0] previous=0;
    reg [8:0] index=0;
    wire crossing=previous<0 && sample>=0;
    wire signed [15:0] scaled=sample>>>8;
    // Full PCM16 scale: +/-32768 spans the plot. No display AGC or extra zoom.
    wire [7:0] height=scaled>127 ? 8'h7f : scaled< -128 ? 8'h80 : scaled[7:0];
    always @(posedge clk) begin
        write_enable<=0;
        if(rst) begin state<=ARM;waited<=0;previous<=0;index<=0;frame_done<=0;
            write_address<=0;write_value<=0; end
        else begin
            if(sample_ce) previous<=sample;
            case(state)
            ARM: if(sample_ce) begin
                if(crossing || waited==TRIGGER_TIMEOUT-1) begin
                    write_enable<=1;write_address<=0;write_value<=height;
                    index<=1;waited<=0;state<=CAPTURE;
                end else waited<=waited+1'b1;
            end
            CAPTURE: if(sample_ce) begin
                write_enable<=1;write_address<=index;write_value<=height;
                if(index==511) begin frame_done<=1;state<=WAIT_ACK; end
                else index<=index+1'b1;
            end
            WAIT_ACK: if(frame_ack) begin frame_done<=0;waited<=0;state<=ARM; end
            default: state<=ARM;
            endcase
        end
    end
endmodule
