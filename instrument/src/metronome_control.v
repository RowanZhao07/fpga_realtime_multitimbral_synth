`timescale 1ns/1ps
// X0 is the modifier. Latch one chord until all its controls are released.
module metronome_control #(
    parameter integer HOLD_SAMPLES=24414, // 0.5 s at 50 MHz / 1024
    parameter integer REPEAT_SAMPLES=4883 // one BPM every 100 ms
)(
    input wire clk,rst,sample_ce,online,
    input wire [17:0] touched,
    output reg enabled=0,
    output reg [7:0] bpm=120,
    output reg [2:0] meter=3,
    output reg gesture=0
);
    wire modifier=online && touched[17];
    wire [3:0] keys=online ? touched[11:8] : 4'b0;
    reg [3:0] chord=0;
    reg [16:0] count=0;
    reg used=0,blocked=0;
    always @(posedge clk) begin
        if(rst) begin
            enabled<=0;bpm<=120;meter<=3;gesture<=0;
            chord<=0;count<=0;used<=0;blocked<=0;
        end else if(sample_ce) begin
            if(!online || (!modifier && keys==0)) begin
                gesture<=0;chord<=0;count<=0;used<=0;blocked<=0;
            end else if(modifier && keys==0) begin
                chord<=0;count<=0;used<=0;blocked<=0;
            end else if(modifier && keys!=0 && chord==0 && !blocked) begin
                gesture<=1;chord<=keys;count<=0;used<=0;blocked<=0;
                if(keys==4'b0100 && bpm<240) bpm<=bpm+1'b1;
                if(keys==4'b0010 && bpm>40) bpm<=bpm-1'b1;
            end else if(gesture) begin
                // Changing or releasing part of a chord consumes this gesture.
                // In particular VOL+ and VOL- together never change GUIDE/gain.
                if(!modifier || keys!=chord) begin blocked<=1;count<=0;end
                else if(!blocked) begin
                    if(chord==4'b0010 || chord==4'b0100) begin
                        if(count==REPEAT_SAMPLES-1) begin
                            count<=0;
                            if(chord==4'b0100 && bpm<240) bpm<=bpm+1'b1;
                            if(chord==4'b0010 && bpm>40) bpm<=bpm-1'b1;
                        end else count<=count+1'b1;
                    end else if(!used && (chord==4'b0001 || chord==4'b1000)) begin
                        if(count==HOLD_SAMPLES-1) begin
                            used<=1;
                            if(chord==4'b1000) enabled<=!enabled;
                            else meter<=meter==4 ? 0 : meter+1'b1;
                        end else count<=count+1'b1;
                    end
                end
            end
        end
    end
endmodule
