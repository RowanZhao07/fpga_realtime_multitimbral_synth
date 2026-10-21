`timescale 1ns/1ps
// Sample-synchronous envelopes. Re-trigger attacks from the current level.
// Electric keys decay exponentially; strings swell and retain a longer tail.
module envelope_adsr (
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
    assign active=(level!=0);
    always @(posedge clk) begin
        if(rst) begin level<=0; state<=IDLE; previous_gate<=0; preset<=0; pedal_fraction<=0; end
        else if(sample_ce) begin
            previous_gate<=gate;
            if(!sustain_down || (gate && !previous_gate)) pedal_fraction<=0;
            else if(state==DECAY && preset==1) pedal_fraction<=pedal_total[1:0];
            if(gate && !previous_gate) begin state<=ATTACK; preset<=timbre; end
            // Preserve the physical gate edge so a held tail can be re-struck.
            else if(!gate && !sustain_down &&
                (previous_gate || state==ATTACK || state==DECAY || state==SUSTAIN)) state<=RELEASE;
            else case(state)
                IDLE: level<=0;
                ATTACK: if(level>=16'hFFFF-attack_step) begin level<=16'hFFFF; state<=DECAY; end
                        else level<=level+attack_step;
                DECAY: if(preset==1) begin
                           if(level<=effective_decay) begin level<=0;state<=SUSTAIN;end
                           else level<=level-effective_decay;
                       end
                       else if(level<=sustain_level+decay_step) begin level<=sustain_level; state<=SUSTAIN; end
                       else level<=level-decay_step;
                SUSTAIN: level<=sustain_level;
                RELEASE: if(level<=release_step) begin level<=0; state<=IDLE; end
                         else level<=level-release_step;
                default: begin level<=0; state<=IDLE; end
            endcase
        end
    end
endmodule
