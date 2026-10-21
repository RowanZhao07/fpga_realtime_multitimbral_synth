`timescale 1ns/1ps
// One independent phase accumulator, latched timbre and ADSR per key.
// Read adjacent points on successive fabric clocks, reusing one waveform ROM.
// Eight fractional phase bits suppress the spurs of a 256-point floor lookup.
module synthesis_voice (
    input wire sustain_down,
    input wire clk, rst, sample_ce, gate,
    input wire [31:0] phase_step,
    input wire [1:0] timbre,
    output reg signed [15:0] sample=0,
    output wire active, output wire [7:0] envelope_level
);
    reg [31:0] phase=0;
    reg gate_previous=0;
    reg [1:0] preset=0;
    wire [15:0] envelope;
    assign envelope_level=envelope[15:8];
    envelope_adsr amplitude(.sustain_down(sustain_down),.clk(clk),.rst(rst),.sample_ce(sample_ce),
        .gate(gate),.timbre(timbre),.level(envelope),.active(active));
    wire signed [15:0] waveform;
    reg read_next=0;
    wire [7:0] table_index=phase[31:24]+{7'b0,read_next};
    timbre_lut table_source(.address({preset,table_index}),.value(waveform));
    wire signed [17:0] wave=waveform;
    reg [5:0] pipeline=0;
    reg signed [15:0] base_wave=0;
    reg [7:0] fraction=0;
    reg signed [16:0] slope=0;
    reg signed [25:0] interpolation=0;
    wire signed [25:0] rounded_interpolation=interpolation+26'sd128;
    reg signed [17:0] wave_reg=0;
    reg signed [35:0] product=0;
    always @(posedge clk) begin
        if(rst) begin
            phase<=0; gate_previous<=0; preset<=0; pipeline<=0;
            read_next<=0;base_wave<=0;fraction<=0;slope<=0;interpolation<=0;
            wave_reg<=0; product<=0; sample<=0;
        end else begin
            pipeline<={pipeline[4:0],sample_ce};
            if(sample_ce) begin
                gate_previous<=gate;
                if(gate && !gate_previous) begin
                    // A release tail has a nonzero envelope. Resetting its
                    // phase would insert a click; only restart a silent voice.
                    phase<=active ? phase+phase_step : 32'd0;
                    preset<=timbre;
                end
                else if(gate || active) phase<=phase+phase_step;
            end
            if(pipeline[0]) begin
                base_wave<=waveform;fraction<=phase[23:16];read_next<=1;
            end
            if(pipeline[1]) begin
                slope<=$signed(waveform)-$signed(base_wave);read_next<=0;
            end
            if(pipeline[2]) interpolation<=slope*$signed({1'b0,fraction});
            if(pipeline[3]) wave_reg<=$signed(base_wave)+(rounded_interpolation>>>8);
            if(pipeline[4]) product<=wave_reg*$signed({1'b0,envelope});
            if(pipeline[5]) sample<=product[31:16];
        end
    end
endmodule
