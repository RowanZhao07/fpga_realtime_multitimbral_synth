`timescale 1ns/1ps
module video_output(input wire pixel_clk,serial_clk,rst,
    input wire [23:0] rgb,input wire de,hs,vs,
    output wire [2:0] tmds_p,tmds_n,output wire tmds_clock_p,tmds_clock_n);
    wire [9:0] blue,green,red;
    tmds_encoder eb(.clk(pixel_clk),.rst(rst),.de(de),.c0(hs),.c1(vs),.data(rgb[7:0]),.symbol(blue));
    tmds_encoder eg(.clk(pixel_clk),.rst(rst),.de(de),.c0(1'b0),.c1(1'b0),.data(rgb[15:8]),.symbol(green));
    tmds_encoder er(.clk(pixel_clk),.rst(rst),.de(de),.c0(1'b0),.c1(1'b0),.data(rgb[23:16]),.symbol(red));
    wire [39:0] words={10'b0000011111,red,green,blue};
    wire [3:0] serial;
    genvar c;
    generate for(c=0;c<4;c=c+1) begin: lanes
        // Assert asynchronously; release locally on a common pixel-clock phase.
        // Keep the 200 MHz clock on dedicated OSER10 FCLK pins, not fabric FFs.
        // Pixel/FCLK remain related in STA, including both-edge reset recovery.
        (* syn_preserve=1, syn_keep=1 *) reg [2:0] reset_pipe=0;
        always @(posedge pixel_clk or posedge rst) begin
            if(rst) reset_pipe<=0;
            else reset_pipe<={reset_pipe[1:0],1'b1};
        end
        // Require both final release stages. During monotonic reset release
        // this matches !reset_pipe[2], but retains a real two-input LUT rather
        // than an inverter absorbed into the serializer's pin polarity.
        // Its delay protects removal; recovery/removal both remain timed.
        (* syn_keep=1, syn_dont_touch=1 *) wire serializer_reset;
        LUT2 #(.INIT(4'b0111)) reset_gate(.I0(reset_pipe[2]),
            .I1(reset_pipe[1]),.F(serializer_reset));
        OSER10 serializer(.Q(serial[c]),.D0(words[10*c]),.D1(words[10*c+1]),
            .D2(words[10*c+2]),.D3(words[10*c+3]),.D4(words[10*c+4]),.D5(words[10*c+5]),
            .D6(words[10*c+6]),.D7(words[10*c+7]),.D8(words[10*c+8]),.D9(words[10*c+9]),
            .PCLK(pixel_clk),.FCLK(serial_clk),.RESET(serializer_reset));
        if(c<3) TLVDS_OBUF buffer(.I(serial[c]),.O(tmds_p[c]),.OB(tmds_n[c]));
        else TLVDS_OBUF buffer(.I(serial[c]),.O(tmds_clock_p),.OB(tmds_clock_n));
    end endgenerate
endmodule
