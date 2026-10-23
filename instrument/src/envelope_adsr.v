`timescale 1ns/1ps
// Sample-synchronous envelopes. Re-trigger attacks from the current level.
// Electric keys decay exponentially; strings swell and retain a longer tail.
module envelope_adsr #(parameter VARIABLE_SUSTAIN=1'b0)(
    input wire [4:0] sustain_strength,
    input wire sustain_down,
    input wire clk, rst, sample_ce, gate,
    input wire [1:0] timbre,
    output reg [15:0] level=0,
    output wire active
);
    localparam IDLE=0, ATTACK=1, DECAY=2, SUSTAIN=3, RELEASE=4;
    reg [2:0] state=IDLE;
    reg previous_gate=0;
    reg [1:0] preset=0;
    wire [15:0] attack_step= preset==0 ? 16'd512 : preset==1 ? 16'd1024 : preset==2 ? 16'd32 : 16'd4096;
    wire [15:0] decay_step= preset==1 ? 16'd12 : preset==3 ? 16'd4 : 16'd8;
    wire [15:0] sustain_level= preset==0 ? 16'd50000 : preset==1 ? 16'd0 : preset==2 ? 16'd50000 : 16'd0;
    wire [15:0] piano_decay=level>=8192 ? (level>>13) : 16'd1;
    // Fractional decrement keeps very quiet pedal tails decaying to zero.
    reg [1:0] pedal_fraction=0;
    wire [17:0] pedal_total={2'b0,piano_decay}+{16'd0,pedal_fraction};
    wire [15:0] effective_decay=sustain_down ? pedal_total[17:2] : piano_decay;
    wire [15:0] release_step= preset==0 ? 16'd16 :
        preset==1 ? (level>=1024 ? (level>>10) : 16'd1) : preset==2 ? 16'd6 : 16'd6;
    // Level 1..16: one original decrement per (level+1) sample ticks.
    // Small per-voice counters avoid variable dividers and multipliers.
    wire [4:0] strength=sustain_strength<1 ? 5'd1 : sustain_strength>16 ? 5'd16 : sustain_strength;
    reg [4:0] decay_count=0,release_count=0;
    reg release_pedal=0;
    wire slow_decay=VARIABLE_SUSTAIN && sustain_down;
    wire [15:0] selected_decay=slow_decay ? (decay_count>=strength ? piano_decay : 16'd0) : effective_decay;
    wire slow_release=VARIABLE_SUSTAIN && release_pedal && sustain_down;
    wire [15:0] selected_release=slow_release ? (release_count>=strength ? release_step : 16'd0) : release_step;
    assign active=(level!=0);
    always @(posedge clk) begin
        if(rst) begin level<=0; state<=IDLE; previous_gate<=0; preset<=0; pedal_fraction<=0; decay_count<=0; release_count<=0; release_pedal<=0; end
        else if(sample_ce) begin
            previous_gate<=gate;
            if(!sustain_down) release_pedal<=0;
            if(!slow_decay || (gate && !previous_gate) || state!=DECAY || preset!=1) decay_count<=0;
            else if(decay_count>=strength) decay_count<=0;
            else decay_count<=decay_count+1'b1;
            if(!slow_release || (gate && !previous_gate) || state!=RELEASE) release_count<=0;
            else if(release_count>=strength) release_count<=0;
            else release_count<=release_count+1'b1;
            if(!sustain_down || (gate && !previous_gate)) pedal_fraction<=0;
            else if(state==DECAY && preset==1) pedal_fraction<=pedal_total[1:0];
            if(gate && !previous_gate) begin state<=ATTACK; preset<=timbre; release_pedal<=0; end
            // Preserve the physical gate edge so a held tail can be re-struck.
            else if(!gate && (VARIABLE_SUSTAIN || !sustain_down) &&
                (previous_gate || state==ATTACK || state==DECAY || state==SUSTAIN)) begin
                state<=RELEASE; release_pedal<=VARIABLE_SUSTAIN && sustain_down;
            end
            else case(state)
                IDLE: level<=0;
                ATTACK: if(level>=16'hFFFF-attack_step) begin level<=16'hFFFF; state<=DECAY; end
                        else level<=level+attack_step;
                DECAY: if(preset==1) begin
                           if(level<=selected_decay) begin level<=0;state<=SUSTAIN;end
                           else level<=level-selected_decay;
                       end
                       else if(level<=sustain_level+decay_step) begin level<=sustain_level; state<=SUSTAIN; end
                       else level<=level-decay_step;
                SUSTAIN: level<=sustain_level;
                RELEASE: if(level<=selected_release) begin level<=0; state<=IDLE; end
                         else level<=level-selected_release;
                default: begin level<=0; state<=IDLE; end
            endcase
        end
    end
endmodule
