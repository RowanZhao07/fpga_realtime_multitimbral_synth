`timescale 1ns/1ps
module tb_video;
    reg clk=0; always #12.5 clk=~clk;
    reg rst=1;
    wire [10:0] x; wire [9:0] y; wire de,hs,vs,blank;
    video_timing timing(.clk(clk),.rst(rst),.x(x),.y(y),.de(de),.hs(hs),.vs(vs),.vertical_blank(blank));
    wire [9:0] addr; reg [7:0] data=0;
    wire [23:0] rgb;wire od,oh,ov;
    // Deterministic input fixtures for visual layout; not claimed as board audio.
    reg [39:0] status=0;
    instrument_screen screen(.clk(clk),.rst(rst),.x(x),.y(y),.de(de),.hs(hs),.vs(vs),
        .vertical_blank(blank),.status(status),.voice_levels(64'h0000005000B000CC),
        .scope_ready(1'b1),.scope_data(data),.scope_address(),.visual_ready(1'b1),.visual_data(data),
        .visual_address(addr),.rgb(rgb),.out_de(od),.out_hs(oh),.out_vs(ov));
    always @(posedge clk) begin
        if(!addr[9]) data<=$rtoi(65*$sin(6.2831853*addr[8:0]/128));
        else data<=addr[8:0]<200 ? ((addr[5:0]<4) ? (120-(addr[8:0]>>1)) : 8'd0) : 0;
    end
    reg en_de=0,c0=0,c1=0;reg [7:0] byte_data=0;
    wire [9:0] symbol;
    tmds_encoder encoder(.clk(clk),.rst(rst),.de(en_de),.c0(c0),.c1(c1),.data(byte_data),.symbol(symbol));
    integer f,pixels=0,frames=0,total=0,active_pixels=0,hs_pixels=0,vs_pixels=0;
    integer n,b,bitn,rd=0;
    reg [7:0] decoded,q;
    initial begin
        repeat(3) @(negedge clk); rst=0;
        for(n=0;n<4;n=n+1) begin
            {c1,c0}=n; en_de=0; @(negedge clk);
            case(n)
            0:if(symbol!==10'b1101010100) $fatal(1,"Control token 0");
            1:if(symbol!==10'b0010101011) $fatal(1,"Control token 1");
            2:if(symbol!==10'b0101010100) $fatal(1,"Control token 2");
            3:if(symbol!==10'b1010101011) $fatal(1,"Control token 3");
            endcase
        end
        en_de=1;
        for(n=0;n<4096;n=n+1) begin
            byte_data=(n*73)^(n>>4); @(negedge clk);
            q=symbol[9] ? ~symbol[7:0] : symbol[7:0]; decoded[0]=q[0];
            for(bitn=1;bitn<8;bitn=bitn+1) decoded[bitn]=q[bitn]^q[bitn-1]^!symbol[8];
            if(decoded!==byte_data) $fatal(1,"TMDS decode mismatch");
            for(bitn=0;bitn<10;bitn=bitn+1) rd=rd+(symbol[bitn] ? 1 : -1);
            if(rd>8 || rd< -8) $fatal(1,"TMDS running disparity bound");
        end
        status={2'b0,1'b0,6'd4,3'd5,1'b1,1'b0,1'b1,1'b1,1'b1,5'd12,2'd2,8'h15,8'h01};
        wait(blank); @(negedge clk);
        wait(x==0 && y==0);
        f=$fopen("screen.ppm","wb"); $fwrite(f,"P6\n800 600\n255\n");
        repeat(1056*628) begin
            @(negedge clk);
            total=total+1;
            if(de) active_pixels=active_pixels+1;
            if(hs) hs_pixels=hs_pixels+1;
            if(vs) vs_pixels=vs_pixels+1;
            if(od) begin $fwrite(f,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]); pixels=pixels+1; end
        end
        $fclose(f);
        if(active_pixels!=480000 || pixels!=480000 || hs_pixels!=128*628 || vs_pixels!=4*1056)
            $fatal(1,"Raster geometry/pipeline mismatch %d %d",active_pixels,pixels);
        $display("PASS: TMDS round-trip/disparity; 800x600 raster, porches, syncs and rendered RGB");
        $display("ALL TESTS PASSED"); $finish;
    end
    initial begin #40000000; $fatal(1,"Video watchdog"); end
endmodule
