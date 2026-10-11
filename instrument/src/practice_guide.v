`timescale 1ns/1ps
// Note events only. The score never generates audio or overrides human gates.
module practice_guide(input wire clk,rst,sample_ce,enabled,
    input wire [12:0] gates,
    input wire command_valid,input_error,
    input wire [7:0] command,input wire [15:0] value,
    output wire command_ok,output wire [12:0] target_mask,
    output wire [6:0] length,output reg custom=0,
    output wire [2:0] target,
    output reg [5:0] position=0,
    output reg correct=0);
    reg [12:0] previous=0;
    reg was_enabled=0;
    // Write only the inactive bank; Z atomically transfers ownership.
    reg [12:0] score_ram [0:127];
    reg active_bank=0,uploading=0,poisoned=0;
    reg [6:0] staged_length=0,active_length=0;
    wire append_ok=uploading && !poisoned && staged_length<64 && value!=0 && value<=16'h1FFF;
    wire commit_ok=uploading && !poisoned && staged_length!=0;
    assign command_ok=!input_error && (command=="A" ? append_ok : command=="Z" ? commit_ok : 1'b1);
    assign length=custom ? active_length : 7'd14;
    assign target_mask=custom ? score_ram[{active_bank,position}] : (13'b1<<score(position));
    // Legacy field reports the first white note; full 13-bit mask drives UI/LEDs.
    reg [2:0] first_white;
    integer n;
    always @* begin
        first_white=0;
        for(n=7;n>=0;n=n-1) if(target_mask[n]) first_white=n;
    end
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
    assign target=first_white;
    always @(posedge clk) begin
        if(rst) begin
            position<=0;previous<=0;was_enabled<=0;correct<=0;
            active_bank<=0;uploading<=0;poisoned<=0;staged_length<=0;active_length<=0;custom<=0;
        end else begin
          correct<=0;
          if(sample_ce) begin
            was_enabled<=enabled; previous<=gates; correct<=0;
            if(!enabled || !was_enabled) position<=0;
            else if(gates==target_mask && |(gates & ~previous)) begin
                position <= {1'b0,position}+7'd1>=length ? 0 : position+1'b1;
                correct<=1;
            end
          end
          if(input_error && uploading) poisoned<=1;
          if(command_valid && !input_error) case(command)
          "N":begin uploading<=1;poisoned<=0;staged_length<=0;end
          "A":if(append_ok) begin
              score_ram[{!active_bank,staged_length[5:0]}]<=value[12:0];
              staged_length<=staged_length+1'b1;
          end else poisoned<=1;
          "Z":if(commit_ok) begin
              active_bank<=!active_bank;active_length<=staged_length;custom<=1;
              uploading<=0;position<=0;previous<=gates;correct<=0;
          end
          "R":begin custom<=0;uploading<=0;poisoned<=0;position<=0;previous<=gates;correct<=0;end
          default:begin end
          endcase
        end
    end
endmodule
