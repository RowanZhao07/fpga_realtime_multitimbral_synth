`timescale 1ns/1ps
// Real PCM versus PCM delayed by 32 samples (0.65536 ms at 48,828.125 Hz).
// Two 128x128 one-bit banks. Connected Bresenham traces cost no multipliers.
// A bank is published only at vertical blank, and never modified while visible.
module lissajous_capture(
    input wire audio_clk,audio_rst,sample_ce,input wire signed [15:0] sample,
    input wire pixel_clk,pixel_rst,vertical_blank,input wire [13:0] read_address,
    output reg read_value=0,output reg ready=0);
    reg bitmap[0:32767];
    reg [6:0] history[0:31];
    reg [4:0] history_pointer=0;
    reg [5:0] history_count=0;
    wire [6:0] point_x=sample[15:9]^7'h40;
    wire [6:0] point_y=7'd127-history[history_pointer];
    localparam CLEAR=0,CAPTURE=1,DRAW=2,WAIT_SWAP=3;
    reg [1:0] state=CLEAR;
    reg [13:0] clear_address=0;
    reg [8:0] points=0;
    reg first_point=1,last_point=0,write_bank=0,read_bank=1;
    reg [6:0] cursor_x=0,cursor_y=0,target_x=0,target_y=0;
    reg step_x=0,step_y=0;
    reg signed [8:0] dx=0,dy=0,error=0;
    wire signed [9:0] twice_error=$signed({error[8],error})<<<1;
    wire move_x=twice_error>=dy,move_y=twice_error<=dx;
    wire signed [8:0] next_error=error+(move_x ? dy : 9'sd0)+(move_y ? dx : 9'sd0);
    wire [7:0] delta_x=point_x>=cursor_x ? point_x-cursor_x : cursor_x-point_x;
    wire [7:0] delta_y=point_y>=cursor_y ? point_y-cursor_y : cursor_y-point_y;
    reg request=0,acknowledge=0;
    (* syn_preserve=1 *) reg ack_meta=0,ack_sync=0,req_meta=0,req_sync=0;
    // No RAM reset loop: clear only the writable bank, one address per clock.
    always @(posedge audio_clk) begin
        if(!audio_rst) begin
            if(state==CLEAR) bitmap[{write_bank,clear_address}]<=0;
            else if(state==DRAW) bitmap[{write_bank,cursor_y,cursor_x}]<=1;
        end
    end
    always @(posedge audio_clk) begin
        ack_meta<=acknowledge;ack_sync<=ack_meta;
        if(audio_rst) begin
            state<=CLEAR;clear_address<=0;points<=0;first_point<=1;last_point<=0;
            write_bank<=0;request<=0;history_pointer<=0;history_count<=0;
            cursor_x<=0;cursor_y<=0;target_x<=0;target_y<=0;dx<=0;dy<=0;error<=0;
            step_x<=0;step_y<=0;
        end else begin
            if(sample_ce) begin
                history[history_pointer]<=point_x;history_pointer<=history_pointer+1'b1;
                if(history_count<32) history_count<=history_count+1'b1;
            end
            case(state)
            CLEAR: begin
                if(clear_address==16383) begin state<=CAPTURE;points<=0;first_point<=1;end
                else clear_address<=clear_address+1'b1;
            end
            CAPTURE: if(sample_ce && history_count==32) begin
                target_x<=point_x;target_y<=point_y;last_point<=points==511;
                points<=points+1'b1;state<=DRAW;
                if(first_point) begin
                    cursor_x<=point_x;cursor_y<=point_y;dx<=0;dy<=0;error<=0;first_point<=0;
                end else begin
                    dx<=$signed({1'b0,delta_x});dy<=-$signed({1'b0,delta_y});
                    error<=$signed({1'b0,delta_x})-$signed({1'b0,delta_y});
                    step_x<=point_x>cursor_x;step_y<=point_y>cursor_y;
                end
            end
            DRAW: begin
                if(cursor_x==target_x && cursor_y==target_y) begin
                    if(last_point) begin request<=!request;state<=WAIT_SWAP;end
                    else state<=CAPTURE;
                end else begin
                    error<=next_error;
                    if(move_x) cursor_x<=step_x ? cursor_x+1'b1 : cursor_x-1'b1;
                    if(move_y) cursor_y<=step_y ? cursor_y+1'b1 : cursor_y-1'b1;
                end
            end
            WAIT_SWAP: if(ack_sync==request) begin write_bank<=!write_bank;clear_address<=0;state<=CLEAR;end
            endcase
        end
    end
    always @(posedge pixel_clk) begin
        read_value<=bitmap[{read_bank,read_address}];
        req_meta<=request;req_sync<=req_meta;
        if(pixel_rst) begin read_bank<=1;acknowledge<=0;ready<=0;end
        else if(vertical_blank && req_sync!=acknowledge) begin
            read_bank<=!read_bank;acknowledge<=req_sync;ready<=1;
        end
    end
endmodule
