`timescale 1ns/1ps
// Double-buffered dual-clock RAM. Ownership transfers only at vertical blank.
module visual_buffer(input wire audio_clk,audio_rst,
    input wire write_enable,input wire [9:0] write_address,input wire [7:0] write_value,
    input wire frame_done, output reg frame_ack=0,
    input wire pixel_clk,pixel_rst,vertical_blank,
    input wire [9:0] read_address,output reg [7:0] read_value=0,
    output reg ready=0);
    reg [7:0] memory[0:2047];
    reg write_bank=0,read_bank=1;
    reg request=0,acknowledge=0;
    (* syn_preserve=1 *) reg ack_meta=0,ack_sync=0,req_meta=0,req_sync=0;
    reg [1:0] state=0;
    always @(posedge audio_clk) begin
        if(write_enable) memory[{write_bank,write_address}]<=write_value;
        ack_meta<=acknowledge; ack_sync<=ack_meta; frame_ack<=0;
        if(audio_rst) begin write_bank<=0; request<=0; state<=0; end
        else case(state)
        0: if(frame_done) begin request<=!request; state<=1; end
        1: if(ack_sync==request) begin write_bank<=!write_bank; frame_ack<=1; state<=2; end
        2: if(!frame_done) state<=0;
        endcase
    end
    always @(posedge pixel_clk) begin
        read_value<=memory[{read_bank,read_address}];
        req_meta<=request; req_sync<=req_meta;
        if(pixel_rst) begin read_bank<=1; acknowledge<=0; ready<=0; end
        else if(vertical_blank && req_sync!=acknowledge) begin
            read_bank<=!read_bank; acknowledge<=req_sync; ready<=1;
        end
    end
endmodule
