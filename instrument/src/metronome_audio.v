`timescale 1ns/1ps
// Synthesized electronic bell/tick; no sampled audio, voice slot or effect RAM.
// BPM unit: half note (2/2), quarter (x/4), dotted quarter (6/8).
module metronome_audio #(
    parameter integer CLOCK_HZ=50000000,
    parameter integer SAMPLE_CLOCKS=1024
)(
    input wire clk,rst,sample_ce,enabled,
    input wire [7:0] bpm,
    input wire [2:0] meter,
    input wire [12:0] volume,
    output reg signed [15:0] sample=0,
    output reg [2:0] beat_index=0,
    output wire flash,
    output reg [1:0] accent=0,
    output reg tick=0
);
    localparam [32:0] PERIOD=33'd60*CLOCK_HZ;
    localparam integer FLASH_SAMPLES=CLOCK_HZ/SAMPLE_CLOCKS/20;
    reg [31:0] phase=0;
    reg running=0;
    reg [2:0] old_meter=3;
    reg [11:0] flash_left=0;
    wire [21:0] advance=(meter==4 ? bpm*3 : bpm)*SAMPLE_CLOCKS;
    wire [32:0] next_phase={1'b0,phase}+advance;
    wire restart=!running || old_meter!=meter;
    wire fire=enabled && (restart || next_phase>=PERIOD);
    wire [2:0] last_beat=meter<2 ? 1 : meter==2 ? 2 : meter==3 ? 3 : 5;
    wire [2:0] next_beat=restart || beat_index>=last_beat ? 0 : beat_index+1'b1;
    wire [1:0] next_accent=next_beat==0 ? 2 :
        ((meter==3 && next_beat==2) || (meter==4 && next_beat==3)) ? 1 : 0;
    assign flash=flash_left!=0;
    // Sine plus a quiet third partial, with ~0.3 ms attack and ~12 ms decay.
    // Weak / secondary / downbeat use 1200 / 1600 / 2000 Hz respectively.
    reg [31:0] oscillator=0,step=0;
    reg [15:0] envelope=0,target=0;
    reg attack=0;
    wire signed [15:0] sine,third;
    wire [31:0] phase3=oscillator*3;
    sine_lut fundamental(.address(oscillator[31:24]),.value(sine));
    sine_lut partial(.address(phase3[31:24]),.value(third));
    wire signed [16:0] wave=$signed({sine[15],sine})+($signed({third[15],third})>>>2);
    reg signed [33:0] envelope_product=0;
    reg signed [31:0] gain_product=0;
    reg [12:0] smooth_volume=0;
    reg [1:0] pipeline=0;
    always @(posedge clk) begin
        if(rst) begin
            phase<=0;running<=0;old_meter<=3;beat_index<=0;flash_left<=0;accent<=0;tick<=0;
            oscillator<=0;step<=0;envelope<=0;target<=0;attack<=0;
            envelope_product<=0;gain_product<=0;sample<=0;pipeline<=0;smooth_volume<=0;
        end else begin
            tick<=0;pipeline<={pipeline[0],sample_ce};
            if(sample_ce) begin
                if(smooth_volume<volume) smooth_volume<=smooth_volume+1'b1;
                else if(smooth_volume>volume) smooth_volume<=smooth_volume-1'b1;
                envelope_product<=envelope==0 ? 34'sd0 : wave*$signed({1'b0,envelope});
                old_meter<=meter;running<=enabled;
                if(flash_left!=0) flash_left<=flash_left-1'b1;
                oscillator<=oscillator+step;
                if(!enabled) begin
                    phase<=0;flash_left<=0;attack<=0;beat_index<=0;accent<=0;
                    envelope<=envelope>256 ? envelope-256 : 0;
                end else if(fire) begin
                    // Carry the fractional remainder; BPM edits never reset phase.
                    phase<=restart ? 0 : next_phase-PERIOD;
                    beat_index<=next_beat;accent<=next_accent;tick<=1;flash_left<=FLASH_SAMPLES;
                    oscillator<=0;envelope<=0;attack<=1;
                    target<=next_accent==2 ? 24000 : next_accent==1 ? 18000 : 12000;
                    case(next_accent)
                        2:step<=32'd175921860; // round(2000 * 2^32 / 48828.125)
                        1:step<=32'd140737488;
                        default:step<=32'd105553116;
                    endcase
                end else begin
                    phase<=next_phase[31:0];
                    if(attack) begin
                        if(envelope+17'd2048>=target) begin envelope<=target;attack<=0;end
                        else envelope<=envelope+2048;
                    end else if(envelope!=0) envelope<=envelope-(envelope>>6)-1'b1;
                end
            end
            if(pipeline[0]) gain_product<=($signed(envelope_product)>>>16)*$signed({1'b0,smooth_volume});
            // +12.04 dB relative to M1 (4x amplitude), independent of instrument gain.
            // Worst-case |wave| <= 10240, envelope <= 24000, master <= 4096:
            // output <= 15000, so this stage stays inside signed 16-bit range.
            // The final instrument+click mixer retains its signed saturation.
            if(pipeline[1]) sample<=gain_product>>>10;
        end
    end
endmodule
