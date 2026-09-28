`timescale 1ns/1ps
// Sample-synchronous linear ADSR. Re-trigger attacks from the current level.
module envelope_adsr (
    input wire clk, rst, sample_ce, gate,
    input wire [1:0] timbre,
    output reg [15:0] level=0,
    output wire active
);
    localparam IDLE=0, ATTACK=1, DECAY=2, SUSTAIN=3, RELEASE=4;
    reg [2:0] state=IDLE;
    reg previous_gate=0;
    reg [1:0] preset=0;
    wire [15:0] attack_step= preset==0 ? 16'd512 : preset==1 ? 16'd2048 : preset==2 ? 16'd1024 : 16'd4096;
    wire [15:0] decay_step= preset==1 ? 16'd12 : preset==3 ? 16'd4 : 16'd8;
    wire [15:0] sustain_level= preset==0 ? 16'd50000 : preset==1 ? 16'd44000 : preset==2 ? 16'd50000 : 16'd0;
    wire [15:0] release_step= preset==0 ? 16'd16 : preset==1 ? 16'd8 : preset==2 ? 16'd24 : 16'd6;
    assign active=(level!=0);
    always @(posedge clk) begin
        if(rst) begin level<=0; state<=IDLE; previous_gate<=0; preset<=0; end
        else if(sample_ce) begin
            previous_gate<=gate;
            if(gate && !previous_gate) begin state<=ATTACK; preset<=timbre; end
            else if(!gate && previous_gate) state<=RELEASE;
            else case(state)
                IDLE: level<=0;
                ATTACK: if(level>=16'hFFFF-attack_step) begin level<=16'hFFFF; state<=DECAY; end
                        else level<=level+attack_step;
                DECAY: if(level<=sustain_level+decay_step) begin level<=sustain_level; state<=SUSTAIN; end
                       else level<=level-decay_step;
                SUSTAIN: level<=sustain_level;
                RELEASE: if(level<=release_step) begin level<=0; state<=IDLE; end
                         else level<=level-release_step;
                default: begin level<=0; state<=IDLE; end
            endcase
        end
    end
endmodule
