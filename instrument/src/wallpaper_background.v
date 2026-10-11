`timescale 1ns/1ps
// Frame-synchronous slideshow; the audio path never waits for image data.
module wallpaper_background #(parameter integer HOLD_FRAMES=600)(
    input wire clk,rst,vertical_blank,
    input wire [10:0] x,input wire [9:0] y,
    output wire [23:0] rgb,output reg [2:0] image_index=0);
    localparam COUNT_BITS=HOLD_FRAMES>1 ? $clog2(HOLD_FRAMES) : 1;
    reg [COUNT_BITS-1:0] frame_count=0;
    reg blank_d=0;
    always @(posedge clk) begin
        blank_d<=vertical_blank;
        if(rst) begin image_index<=0;frame_count<=0;blank_d<=0;end
        else if(vertical_blank && !blank_d) begin
            if(frame_count==HOLD_FRAMES-1) begin
                frame_count<=0;image_index<=image_index+1'b1;
            end else frame_count<=frame_count+1'b1;
        end
    end
    // floor(v*6/25) is exactly floor(v*15729/65536) for this raster.
    // Sized products avoid division hardware and preserve the 4:3 aspect ratio.
    wire [26:0] scaled_x=x*16'd15729;
    wire [25:0] scaled_y=y*16'd15729;
    wire [7:0] source_x=x<800 ? scaled_x[23:16] : 8'd0;
    wire [7:0] source_y=y<600 ? scaled_y[23:16] : 8'd0;
    wire [7:0] word_x=source_x/8'd3;
    wire [7:0] remainder=source_x-word_x*8'd3;
    wire [16:0] image_base=({14'd0,image_index}<<13)+({14'd0,image_index}<<10);
    wire [16:0] address=image_base+{3'd0,source_y,6'd0}+{9'd0,word_x};
    wallpaper_rom memory(.clk(clk),.address(address),.slot(remainder[1:0]),
        .image_index(image_index),.rgb(rgb));
endmodule
