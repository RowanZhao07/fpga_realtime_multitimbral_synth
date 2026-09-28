`timescale 1ns/1ps
// VESA 800x600 60 Hz, 40 MHz pixel clock, positive syncs.
module video_timing(input wire clk,rst,output reg [10:0] x=0,
    output reg [9:0] y=0,output wire de,hs,vs,vertical_blank);
    assign de=x<800 && y<600;
    assign hs=x>=840 && x<968;
    assign vs=y>=601 && y<605;
    assign vertical_blank=x==0 && y==600;
    always @(posedge clk) begin
        if(rst) begin x<=0; y<=0; end
        else if(x==1055) begin x<=0; y<=y==627 ? 0 : y+1'b1; end
        else x<=x+1'b1;
    end
endmodule
