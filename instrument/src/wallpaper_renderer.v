`timescale 1ns/1ps
// 5x integer scaling. The ROM's two clocks align with instrument_screen px/py.
module wallpaper_renderer #(parameter integer HOLD_FRAMES=600)(
    input wire clk,rst,vertical_blank,input wire [10:0] x,input wire [9:0] y,
    output wire [23:0] rgb,output reg [2:0] image_index=0);
    localparam CW=HOLD_FRAMES>1 ? $clog2(HOLD_FRAMES) : 1;
    reg [CW-1:0] frames=0;
    // floor(n/5) is exactly (n*205)>>10 for visible coordinates n<800.
    // Write constant products as shifts/adds: reserve DSPs for audio and FFT.
    wire [17:0] xwide={8'd0,x[9:0]},ywide={8'd0,y};
    wire [17:0] sx_product=(xwide<<7)+(xwide<<6)+(xwide<<3)+(xwide<<2)+xwide;
    wire [17:0] sy_product=(ywide<<7)+(ywide<<6)+(ywide<<3)+(ywide<<2)+ywide;
    wire [7:0] sx=x<800 ? sx_product[17:10] : 8'd0;
    wire [6:0] sy=y<600 ? sy_product[16:10] : 7'd0;
    wire [15:0] image_base=image_index==0 ? 16'd0 : image_index==1 ? 16'd4800 :
        image_index==2 ? 16'd9600 : image_index==3 ? 16'd14400 :
        image_index==4 ? 16'd19200 : image_index==5 ? 16'd24000 :
        image_index==6 ? 16'd28800 : 16'd33600;
    wire [15:0] word_address=image_base+{sy,5'b0}+{sy,3'b0}+sx[7:2];
    wallpaper_rom rom(.clk(clk),.address(word_address),.slot(sx[1:0]),
        .image_index(image_index),.rgb(rgb));
    always @(posedge clk) begin
        if(rst) begin frames<=0;image_index<=0;end
        else if(vertical_blank) begin
            if(frames==HOLD_FRAMES-1) begin frames<=0;image_index<=image_index+1'b1;end
            else frames<=frames+1'b1;
        end
    end
endmodule
