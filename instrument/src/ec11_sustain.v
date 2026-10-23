`timescale 1ns/1ps
// Passive EC11 contacts: A/B/common to GND, push switch active low.
// 2 transitions per detent suits 30-detent/15-pulse EC11 variants.
module ec11_sustain #(
    parameter integer FILTER_CLOCKS=50000,
    parameter integer BUTTON_CLOCKS=500000,
    parameter integer TRANSITIONS_PER_STEP=2,
    parameter REVERSE=1'b0
)(
    input wire clk,rst,a,b,sw_n,set_valid,set_enabled,
    output reg enabled=0,
    output reg [4:0] strength=5'd3
);
    (* ASYNC_REG="TRUE" *) reg [2:0] sync1=3'b111,sync2=3'b111;
    always @(posedge clk) begin
        if(rst) begin sync1<=3'b111;sync2<=3'b111;end
        else begin sync1<={sw_n,a,b};sync2<=sync1;end
    end
    localparam integer AB_BITS=FILTER_CLOCKS>1 ? $clog2(FILTER_CLOCKS) : 1;
    localparam integer SW_BITS=BUTTON_CLOCKS>1 ? $clog2(BUTTON_CLOCKS) : 1;
    reg [AB_BITS-1:0] ab_count=0;
    reg [SW_BITS-1:0] sw_count=0;
    reg [1:0] candidate=2'b11,stable=2'b11,previous=2'b11;
    reg button=1,button_previous=1;
    reg armed=0,button_armed=0;
    reg signed [3:0] movement=0;
    reg signed [3:0] delta;
    wire signed [3:0] next_movement=movement+delta;
    always @* begin
        delta=0;
        case({previous,stable})
            4'b1101,4'b0100,4'b0010,4'b1011:delta=REVERSE ? -1 : 1;
            4'b1110,4'b1000,4'b0001,4'b0111:delta=REVERSE ? 1 : -1;
            default:delta=0;
        endcase
    end
    always @(posedge clk) begin
        if(rst) begin
            ab_count<=0;sw_count<=0;candidate<=2'b11;stable<=2'b11;
            previous<=2'b11;button<=1;button_previous<=1;
            movement<=0;armed<=0;button_armed<=0;enabled<=0;strength<=5'd3;
        end else begin
            // Filter A/B as one Gray-code word; independently filter the button.
            if(sync2[1:0]!=candidate) begin candidate<=sync2[1:0];ab_count<=0;end
            else if(ab_count==FILTER_CLOCKS-1) begin stable<=candidate;armed<=1;end
            else ab_count<=ab_count+1'b1;
            if(sync2[2]==button) sw_count<=0;
            else if(sw_count==BUTTON_CLOCKS-1) begin button<=sync2[2];sw_count<=0;end
            else sw_count<=sw_count+1'b1;
            button_previous<=button;
            if(armed && button && sync2[2]) button_armed<=1;
            if(set_valid) enabled<=set_enabled;
            else if(button_armed && button_previous && !button) enabled<=!enabled;
            previous<=stable;
            if(!armed) movement<=0;
            else if(previous!=stable) begin
                // Both bits changing is an illegal jump: discard the partial step.
                if((previous^stable)==2'b11) movement<=0;
                else if(next_movement>=TRANSITIONS_PER_STEP) begin
                    movement<=0;if(strength<16) strength<=strength+1'b1;
                end else if(next_movement<=-TRANSITIONS_PER_STEP) begin
                    movement<=0;if(strength>1) strength<=strength-1'b1;
                end else movement<=next_movement;
            end
            // Establish startup phase without treating power-up as rotation.
            if(!armed && sync2[1:0]==candidate && ab_count==FILTER_CLOCKS-1)
                previous<=candidate;
        end
    end
endmodule
