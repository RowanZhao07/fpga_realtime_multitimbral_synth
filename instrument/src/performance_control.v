`timescale 1ns/1ps
// Control keys are independent from the eight note gates.
module performance_control #(
    parameter integer HOLD_SAMPLES=48828,
    parameter integer REPEAT_SAMPLES=4883
)(
    input wire clk, rst, sample_ce, online,
    input wire [11:0] touched,
    output wire [7:0] gates,
    output reg [1:0] timbre=0,
    output reg [12:0] volume=2048,
    output wire vibrato,
    output reg spectrum_mode=0,
    output reg echo_enabled=0,
    output reg guide_enabled=0
);
    reg [3:0] previous=0;
    reg [16:0] hold_count=0, repeat_count=0;
    reg combo_used=0;
    reg [16:0] effect_count=0, guide_count=0;
    reg effect_used=0, guide_used=0;
    wire [3:0] control=online ? touched[11:8] : 4'b0;
    wire all_control=&control;
    wire volume_repeat=(repeat_count==REPEAT_SAMPLES-1);
    assign gates=online ? (spectrum_mode ? 8'hFF : touched[7:0]) : 8'h00;
    assign vibrato=online && control[3] && !spectrum_mode && !all_control;
    always @(posedge clk) begin
        if(rst) begin
            previous<=0; timbre<=0; volume<=2048; spectrum_mode<=0;
            hold_count<=0; repeat_count<=0; combo_used<=0;
            effect_count<=0; guide_count<=0; effect_used<=0; guide_used<=0;
            echo_enabled<=0; guide_enabled<=0;
        end else if(sample_ce) begin
            previous<=control;
            if(control==4'b0001 && !spectrum_mode && !combo_used) begin
                if(!effect_used) begin
                    if(effect_count==HOLD_SAMPLES-1) begin
                        echo_enabled<=!echo_enabled; effect_used<=1;
                    end else effect_count<=effect_count+1'b1;
                end
            end else effect_count<=0;
            if(control==4'b0110 && !spectrum_mode && !combo_used) begin
                if(!guide_used) begin
                    if(guide_count==HOLD_SAMPLES-1) begin
                        guide_enabled<=!guide_enabled; guide_used<=1;
                    end else guide_count<=guide_count+1'b1;
                end
            end else guide_count<=0;
            if(control==0) begin effect_used<=0; guide_used<=0; end
            if(!online) begin spectrum_mode<=0; hold_count<=0; combo_used<=0; end
            else if(all_control) begin
                if(!combo_used) begin
                    if(hold_count==HOLD_SAMPLES-1) begin
                        spectrum_mode<=!spectrum_mode; combo_used<=1;
                    end else hold_count<=hold_count+1'b1;
                end
            end else begin hold_count<=0; if(control==0) combo_used<=0; end
            if(control[2:1]==2'b01 || control[2:1]==2'b10) begin
                if(volume_repeat) repeat_count<=0;
                else repeat_count<=repeat_count+1'b1;
            end else repeat_count<=0;
            // Change preset on release; a held all-control gesture consumes it.
            if(previous[0] && !control[0] && !combo_used && !effect_used && !spectrum_mode && online)
                timbre<=timbre+1'b1;
            if(!all_control && !combo_used && !spectrum_mode) begin
                if(control[2:1]==2'b01 && (!previous[1] || volume_repeat) && volume>512)
                    volume<=volume-13'd256;
                if(control[2:1]==2'b10 && (!previous[2] || volume_repeat) && volume<4096)
                    volume<=volume+13'd256;
            end
        end
    end
endmodule
