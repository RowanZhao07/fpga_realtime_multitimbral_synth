`timescale 1ns/1ps
// 32 independent note states rendered through one shared mathematical wavetable.
module polyphonic_engine #(parameter VARIABLE_SUSTAIN=1'b0,parameter ENABLE_PITCH_BEND=1'b0)(
    input wire [4:0] sustain_strength,
    input wire sustain_down,clk,rst,sample_ce,
    input wire [12:0] gates,
    input wire [1:0] timbre,octave_select,
    input wire vibrato,
    input wire signed [15:0] pitch_bend,
    output reg signed [18:0] mixed=0,
    output reg valid=0,
    output reg [12:0] active=0,
    output reg [103:0] voice_levels=0,
    output reg [5:0] voice_count=0,
    output reg overrun=0
);
    reg [31:0] phase[0:31],steps[0:31],age[0:31];
    reg [3:0] owner[0:31];
    reg [1:0] preset[0:31];
    reg [15:0] brightness[0:31];
    reg signed [15:0] last_sample[0:31],steal_tail[0:31];
    reg [3:0] fade_left[0:31];
    reg [31:0] occupied=0,held=0,clear_voice=0;
    wire [31:0] sounding;
    wire [15:0] envelopes[0:31];
    reg envelope_tick=0;
    genvar v;
    generate for(v=0;v<32;v=v+1) begin: voice_bank
        envelope_adsr #(.VARIABLE_SUSTAIN(VARIABLE_SUSTAIN)) amplitude(.sustain_strength(sustain_strength),.clk(clk),.rst(rst || clear_voice[v]),.sample_ce(envelope_tick),
            .gate(held[v]),.sustain_down(sustain_down),.timbre(preset[v]),
            .level(envelopes[v]),.active(sounding[v]));
    end endgenerate
    wire [31:0] key_steps[0:12];
    generate for(v=0;v<13;v=v+1) begin: tuning_bank
        note_frequency #(.KEY(v)) tuning(.step(key_steps[v]));
    end endgenerate
    reg [12:0] previous_gates=0,frame_gates=0,rising=0;
    reg [1:0] frame_octave=1,frame_timbre=0;
    reg frame_vibrato=0;
    reg signed [15:0] frame_bend=0;
    reg signed [48:0] bend_product=0;
    reg signed [32:0] bent_step=0;
    reg [23:0] lfo_phase=0;
    wire [7:0] folded=lfo_phase[23] ? ~lfo_phase[22:15] : lfo_phase[22:15];
    wire signed [8:0] lfo=$signed({1'b0,folded})-9'sd128;
    reg [4:0] slot=0;
    reg [3:0] key=0;
    reg [4:0] state=0;
    integer n;
    reg found_free,found_release;
    reg [4:0] free_slot,release_slot,oldest_slot,candidate=0;
    wire [4:0] selected=found_free ? free_slot : found_release ? release_slot : oldest_slot;
    reg [31:0] oldest_age;
    reg [15:0] quietest;
    // Search one candidate per clock: avoids a 32-comparator critical chain.
    // Even 13 simultaneous onsets + all 32 audio voices finish before 1024 clocks.
    wire [31:0] selected_step=frame_octave==0 ? key_steps[key]>>1 :
        frame_octave==1 ? key_steps[key] : frame_octave==2 ? key_steps[key]<<1 : key_steps[key]<<2;
    reg [9:0] address=0;
    wire signed [15:0] wave;
    timbre_lut shared_table(.address(address),.value(wave));
    reg [7:0] fraction=0;
    reg signed [15:0] base=0,sine_base=0;
    reg signed [16:0] slope=0;
    reg signed [25:0] interp=0;
    reg signed [17:0] rich_wave=0,pure_wave=0,shaped_wave=0;
    reg signed [34:0] color_product=0;
    reg signed [35:0] envelope_product=0;
    reg signed [41:0] deviation=0;
    reg signed [20:0] accumulator=0;
    wire signed [20:0] fading_tail=$signed(steal_tail[slot])*$signed({1'b0,fade_left[slot]});
    reg [12:0] next_active=0;
    reg [103:0] next_levels=0;
    reg [5:0] next_count=0;
    wire [7:0] level=envelopes[slot][15:8];
    wire [7:0] old_level=next_levels>>(owner[slot]*8);
    wire [15:0] color_floor=preset[slot]==2 ? 16'd18000 : 16'd0;
    wire [15:0] color_decay=preset[slot]==1 ? (brightness[slot]>>11)+1'b1 :
        preset[slot]==3 ? (brightness[slot]>>9)+1'b1 : 16'd1;
    always @(posedge clk) begin
        valid<=0;envelope_tick<=0;clear_voice<=0;
        if(rst) begin
            occupied<=0;held<=0;previous_gates<=0;frame_gates<=0;rising<=0;
            state<=0;slot<=0;key<=0;lfo_phase<=0;mixed<=0;active<=0;
            voice_levels<=0;voice_count<=0;overrun<=0;accumulator<=0;
            next_active<=0;next_levels<=0;next_count<=0;address<=0;
            candidate<=0;found_free<=0;found_release<=0;free_slot<=0;
            release_slot<=0;oldest_slot<=0;oldest_age<=0;quietest<=16'hffff;
            for(n=0;n<32;n=n+1) begin
                phase[n]<=0;steps[n]<=0;age[n]<=0;owner[n]<=0;preset[n]<=0;brightness[n]<=0;
                last_sample[n]<=0;steal_tail[n]<=0;fade_left[n]<=0;
            end
        end else begin
            if(sample_ce && state!=0) overrun<=1;
            case(state)
            0:if(sample_ce) begin
                frame_gates<=gates;rising<=gates & ~previous_gates;previous_gates<=gates;
                frame_octave<=octave_select;frame_timbre<=timbre;frame_vibrato<=vibrato;
                frame_bend<=ENABLE_PITCH_BEND ? pitch_bend : 16'sd0;
                lfo_phase<=lfo_phase+24'd1718;
                for(n=0;n<32;n=n+1) begin
                    if(occupied[n] && age[n]!=32'hffffffff) age[n]<=age[n]+1'b1;
                    if(held[n] && !gates[owner[n]]) held[n]<=0;
                    if(occupied[n] && !held[n] && !sounding[n] && age[n]>2) occupied[n]<=0;
                end
                key<=0;state<=1;
            end
            1:begin
                if(rising[key]) begin
                    candidate<=0;found_free<=0;found_release<=0;free_slot<=0;
                    release_slot<=0;oldest_slot<=0;oldest_age<=0;quietest<=16'hffff;state<=17;
                end else if(key==12) state<=2;else key<=key+1'b1;
            end
            17:begin
                if(!occupied[candidate] && !found_free) begin free_slot<=candidate;found_free<=1;end
                if(occupied[candidate] && !held[candidate] && !sustain_down &&
                    (!found_release || envelopes[candidate]<quietest)) begin
                    found_release<=1;release_slot<=candidate;quietest<=envelopes[candidate];
                end
                if(age[candidate]>=oldest_age) begin oldest_age<=age[candidate];oldest_slot<=candidate;end
                if(candidate==31) state<=18;else candidate<=candidate+1'b1;
            end
            18:begin
                    occupied[selected]<=1;held[selected]<=1;clear_voice[selected]<=1;
                    owner[selected]<=key;preset[selected]<=frame_timbre;steps[selected]<=selected_step;
                    phase[selected]<=0;age[selected]<=0;brightness[selected]<=16'hffff;
                    steal_tail[selected]<=last_sample[selected];
                    fade_left[selected]<=occupied[selected] ? 4'd8 : 4'd0;
                if(key==12) state<=2;else key<=key+1'b1;
                if(key!=12) state<=1;
            end
            2:begin envelope_tick<=1;state<=3;end
            3:begin slot<=0;accumulator<=0;next_active<=0;next_levels<=0;next_count<=0;state<=4;end
            4:begin
                address<={preset[slot],phase[slot][31:24]};fraction<=phase[slot][23:16];
                deviation<=$signed({1'b0,(steps[slot]>>13)})*lfo;
                bend_product<=$signed({1'b0,steps[slot]})*frame_bend;
                state<=5;
            end
            5:begin base<=wave;address<={preset[slot],(phase[slot][31:24]+8'd1)};
                bent_step<=$signed({1'b0,steps[slot]})+(bend_product>>>16);state<=6;end
            6:begin slope<=$signed(wave)-$signed(base);state<=7;end
            7:begin interp<=slope*$signed({1'b0,fraction});address<={2'b0,phase[slot][31:24]};state<=8;end
            8:begin rich_wave<=$signed(base)+((interp+26'sd128)>>>8);sine_base<=wave;
                address<={2'b0,(phase[slot][31:24]+8'd1)};state<=9;end
            9:begin slope<=$signed(wave)-$signed(sine_base);state<=10;end
            10:begin interp<=slope*$signed({1'b0,fraction});state<=11;end
            11:begin pure_wave<=$signed(sine_base)+((interp+26'sd128)>>>8);state<=12;end
            12:begin color_product<=(rich_wave-pure_wave)*$signed({1'b0,brightness[slot]});state<=13;end
            13:begin shaped_wave<=pure_wave+(color_product>>>16);state<=14;end
            14:begin envelope_product<=shaped_wave*$signed({1'b0,envelopes[slot]});state<=15;end
            15:begin
                if(occupied[slot]) begin
                    // A stolen voice fades its last output over eight samples;
                    // its replacement attacks from zero rather than hard-cutting.
                    accumulator<=accumulator+(envelope_product>>>16)+(fading_tail>>>3);
                    last_sample[slot]<=envelope_product>>>16;
                    if(fade_left[slot]!=0) fade_left[slot]<=fade_left[slot]-1'b1;
                    phase[slot]<=phase[slot]+(ENABLE_PITCH_BEND ? bent_step[31:0] : steps[slot])+(frame_vibrato ? deviation[31:0] : 32'd0);
                    if(brightness[slot]>color_floor+color_decay) brightness[slot]<=brightness[slot]-color_decay;
                    else brightness[slot]<=color_floor;
                    if(sounding[slot]) begin
                        next_active[owner[slot]]<=1;next_count<=next_count+1'b1;
                        if(level>old_level) next_levels[owner[slot]*8+:8]<=level;
                    end
                end
                if(slot==31) state<=16;else begin slot<=slot+1'b1;state<=4;end
            end
            16:begin
                // Fixed extra headroom; adding notes never pumps existing voices.
                mixed<=accumulator>>>1;valid<=1;active<=next_active;
                voice_levels<=next_levels;voice_count<=next_count;state<=0;
            end
            default:state<=0;
            endcase
        end
    end
endmodule
