`timescale 1ns/1ps
// Note events only. The score never generates audio or overrides human gates.
module practice_guide(input wire clk,rst,sample_ce,enabled,
    input wire [7:0] gates,
    output wire [2:0] target,
    output reg [5:0] position=0,
    output reg correct=0);
    reg [7:0] previous=0;
    reg was_enabled=0;
    function [2:0] score;
        input [5:0] p;
        begin case(p)
        0,1,13: score=0;
        2,3,6: score=4;
        4,5: score=5;
        7,8: score=3;
        9,10: score=2;
        default: score=1;
        endcase end
    endfunction
    assign target=score(position);
    always @(posedge clk) begin
        if(rst) begin position<=0; previous<=0; was_enabled<=0; correct<=0; end
        else if(sample_ce) begin
            was_enabled<=enabled; previous<=gates; correct<=0;
            if(!enabled || !was_enabled) position<=0;
            else if((gates & ~previous)==(8'b1<<target)) begin
                position <= position==13 ? 0 : position+1'b1;
                correct<=1;
            end
        end
    end
endmodule
