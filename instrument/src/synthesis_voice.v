`timescale 1ns/1ps
// One independent phase accumulator, latched timbre and ADSR per key.
module synthesis_voice (
    input wire clk, rst, sample_ce, gate,
    input wire [31:0] phase_step,
    input wire [1:0] timbre,
    output reg signed [15:0] sample=0,
    output wire active
);
    reg [31:0] phase=0;
    reg gate_previous=0;
    reg [1:0] preset=0;
    wire [15:0] envelope;
    envelope_adsr amplitude(.clk(clk),.rst(rst),.sample_ce(sample_ce),
        .gate(gate),.timbre(timbre),.level(envelope),.active(active));
    wire signed [15:0] waveform;
    timbre_lut table_source(.address({preset,phase[31:24]}),.value(waveform));
    wire signed [17:0] wave=waveform;
    reg [2:0] pipeline=0;
    reg signed [17:0] wave_reg=0;
    reg signed [35:0] product=0;
    always @(posedge clk) begin
        if(rst) begin
            phase<=0; gate_previous<=0; preset<=0; pipeline<=0;
            wave_reg<=0; product<=0; sample<=0;
        end else begin
            pipeline<={pipeline[1:0],sample_ce};
            if(sample_ce) begin
                gate_previous<=gate;
                if(gate && !gate_previous) begin phase<=0; preset<=timbre; end
                else if(gate || active) phase<=phase+phase_step;
            end
            if(pipeline[0]) wave_reg<=wave;
            if(pipeline[1]) product<=wave_reg*$signed({1'b0,envelope});
            if(pipeline[2]) sample<=product[31:16];
        end
    end
endmodule
