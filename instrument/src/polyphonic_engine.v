`timescale 1ns/1ps
module polyphonic_engine (
    input wire clk, rst, sample_ce,
    input wire [12:0] gates,
    input wire [1:0] timbre,
    input wire vibrato,
    output reg signed [18:0] mixed=0,
    output reg valid=0,
    output wire [12:0] active, output wire [103:0] voice_levels
);
    reg [23:0] lfo_phase=0;
    wire [7:0] folded=lfo_phase[23] ? ~lfo_phase[22:15] : lfo_phase[22:15];
    wire signed [8:0] lfo=$signed({1'b0,folded})-9'sd128;
    always @(posedge clk) begin
        if(rst) lfo_phase<=0;
        else if(sample_ce) lfo_phase<=lfo_phase+24'd1718;
    end
    wire signed [15:0] voices[0:12];
    genvar v;
    generate for(v=0;v<13;v=v+1) begin: voice_bank
        wire [31:0] base_step;
        note_frequency #(.KEY(v)) tuning(.step(base_step));
        wire signed [41:0] deviation=$signed({1'b0,(base_step>>13)})*lfo;
        wire [31:0] step= vibrato ? base_step+deviation[31:0] : base_step;
        synthesis_voice voice(.clk(clk),.rst(rst),.sample_ce(sample_ce),
            .gate(gates[v]),.phase_step(step),.timbre(timbre),
            .sample(voices[v]),.active(active[v]),.envelope_level(voice_levels[v*8+:8]));
    end endgenerate
    // Six voice stages, then pair sums and the full-width final sum.
    // Fixed per-voice gain: adding a key never attenuates an already-held key.
    reg [7:0] pipeline=0;
    reg signed [16:0] pair0=0,pair1=0,pair2=0,pair3=0;
    reg signed [16:0] pair4=0,pair5=0,pair6=0;
    always @(posedge clk) begin
        if(rst) begin
            pipeline<=0; mixed<=0; valid<=0;
            pair0<=0; pair1<=0; pair2<=0; pair3<=0; pair4<=0; pair5<=0; pair6<=0;
        end
        else begin
            pipeline<={pipeline[6:0],sample_ce}; valid<=pipeline[7];
            if(pipeline[6]) begin
                pair0<=$signed(voices[0])+$signed(voices[1]);
                pair1<=$signed(voices[2])+$signed(voices[3]);
                pair2<=$signed(voices[4])+$signed(voices[5]);
                pair3<=$signed(voices[6])+$signed(voices[7]);
                pair4<=$signed(voices[8])+$signed(voices[9]);
                pair5<=$signed(voices[10])+$signed(voices[11]);
                pair6<=$signed(voices[12]);
            end
            if(pipeline[7]) mixed<=pair0+pair1+pair2+pair3+pair4+pair5+pair6;
        end
    end
endmodule
