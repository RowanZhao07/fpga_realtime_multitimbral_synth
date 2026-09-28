`timescale 1ns/1ps
module instrument_core #(
    parameter ENABLE_ECHO=1'b0
)(
    input wire clk, rst, online,
    input wire [11:0] touched,
    output wire dac_bck, dac_lrck, dac_din,
    output wire [7:0] led,
    output wire [39:0] status, output wire signed [15:0] monitor_sample,
    output wire monitor_ce
);
    wire echo_enabled,guide_enabled;
    wire [2:0] guide_target;
    wire [5:0] guide_position;
    wire sample_ce, vibrato, spectrum_mode, valid, clipped;
    wire [7:0] gates,active;
    wire [1:0] timbre;
    wire [12:0] volume;
    wire signed [18:0] mixed;
    wire signed [15:0] sample;
    reg previous_mode=0;
    always @(posedge clk) previous_mode<=spectrum_mode;
    wire audio_reset=rst || (previous_mode!=spectrum_mode);
    performance_control controls(.clk(clk),.rst(rst),.sample_ce(sample_ce),
        .online(online),.touched(touched),.gates(gates),.timbre(timbre),
        .volume(volume),.vibrato(vibrato),.spectrum_mode(spectrum_mode),.echo_enabled(echo_enabled),.guide_enabled(guide_enabled));
    polyphonic_engine engine(.clk(clk),.rst(audio_reset),.sample_ce(sample_ce),.gates(gates),
        .timbre(spectrum_mode ? 2'b0 : timbre),.vibrato(vibrato),
        .mixed(mixed),.valid(valid),.active(active));
    audio_output output_stage(.clk(clk),.rst(audio_reset),.valid(valid),.mixed(mixed),
        .volume(spectrum_mode ? 13'd2048 : volume),.echo_enable((ENABLE_ECHO || echo_enabled) && !spectrum_mode),
        .sample(sample),.clipped(clipped));
    i2s_transmitter transmitter(.clk(clk),.rst(rst),.sample(sample),
        .sample_ce(sample_ce),.bck(dac_bck),.lrck(dac_lrck),.din(dac_din));
    practice_guide guide(.clk(clk),.rst(rst),.sample_ce(sample_ce),
        .enabled(guide_enabled && online && !spectrum_mode),.gates(gates),
        .target(guide_target),.position(guide_position),.correct());
    assign monitor_sample=sample;
    assign monitor_ce=sample_ce;
    reg [25:0] heartbeat_count=0;
    wire tempo_pulse=heartbeat_count<26'd3125000 ||
        (heartbeat_count>=26'd25000000 && heartbeat_count<26'd28125000);
    assign status={1'b0,tempo_pulse,clipped,guide_position,guide_target,guide_enabled,spectrum_mode,
        echo_enabled,vibrato,online,volume[12:8],timbre,active,gates};
    always @(posedge clk) begin
        if(rst) heartbeat_count<=0;
        else if(heartbeat_count==26'd49999999) heartbeat_count<=0;
        else heartbeat_count<=heartbeat_count+1'b1;
    end
    wire beat=(heartbeat_count<26'd25000000);
    // Held notes take priority. Idle L5..L8 identify the next-note preset.
    wire [7:0] preset_light=8'h10 << timbre;
    wire [7:0] lights= !online ? (beat ? 8'h81 : 8'h00) :
        spectrum_mode ? (beat ? 8'hFF : 8'h00) :
        (|gates) ? gates : guide_enabled ? (tempo_pulse ? (8'b1<<guide_target) : 8'b0) : (preset_light | 8'h02 | {7'd0,beat});
    assign led=~lights;
endmodule
