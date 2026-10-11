`timescale 1ns/1ps
// Export real RTL pixels for all eight banks, including reset and 7->0 wrap.
// Shortened hold time only accelerates simulation; no forced internal state.
module tb_wallpaper;
    GSR GSR(.GSRI(1'b1));
    reg clk=0;always #12.5 clk=~clk;
    reg rst=1,blank=0,de=0;
    reg [10:0] x=0;reg [9:0] y=0;
    wire [23:0] raw_rgb,rgb;
    wire [2:0] image_index;
    wire od,oh,ov;wire [9:0] addr;
    reg [7:0] data=0;
    reg [203:0] status=0;
    wire [12:0] fixture_active={status[49:45],status[15:8]};
    wire [103:0] fixture_levels;
    for(genvar v=0;v<13;v=v+1) begin: feedback_fixture
        assign fixture_levels[v*8+:8]=fixture_active[v] ? 8'd192 : 8'd0;
    end
    wallpaper_background #(.HOLD_FRAMES(2)) background(.clk(clk),.rst(rst),
        .vertical_blank(blank),.x(x),.y(y),.rgb(raw_rgb),.image_index(image_index));
    instrument_screen #(.WALLPAPER_HOLD_FRAMES(2)) screen(.clk(clk),.rst(rst),
        .x(x),.y(y),.de(de),.hs(1'b0),.vs(1'b0),.vertical_blank(blank),
        .status(status),.visual_ready(1'b1),.visual_data(data),.visual_address(addr),
        .voice_levels(fixture_levels),.scope_ready(1'b1),.scope_data(data),.scope_address(),
        .rgb(rgb),.out_de(od),.out_hs(oh),.out_vs(ov));
    reg [1:0] valid=0;
    always @(posedge clk) begin
        valid<={valid[0],de};
        if(!addr[9]) data<=$rtoi(48*$sin(6.2831853*addr[8:0]/128));
        else data<=addr[3:0]<10 ? 30+((511-addr[8:0])>>3)+((addr[7:4]*11)%40) : 0;
    end
    integer raw_file,screen_file,raw_count,screen_count,xx,yy,bank;
    reg capturing=0;
    always @(negedge clk) if(capturing) begin
        if(valid[1]) begin
            if(^raw_rgb===1'bx) $fatal(1,"Unknown wallpaper pixel");
            $fwrite(raw_file,"%c%c%c",raw_rgb[23:16],raw_rgb[15:8],raw_rgb[7:0]);
            raw_count=raw_count+1;
        end
        if(od) begin
            $fwrite(screen_file,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);
            screen_count=screen_count+1;
        end
    end
    task blank_frame;
        begin
            @(negedge clk);blank=1;
            repeat(4) @(negedge clk);
            blank=0;
            repeat(4) @(negedge clk);
        end
    endtask
    initial begin
        status[7:0]=8'h15;status[15:8]=8'h15;status[22:18]=12;
        status[23]=1;status[25]=1;status[50]=1;status[51]=1;
        status[65]=1;status[64:53]=2000;status[86:79]=90;status[93:87]=14;
        repeat(3) @(negedge clk);rst=0;
        // Capture status and prove a held blank is counted once, not four times.
        blank_frame();
        if(image_index!==0) $fatal(1,"Slideshow advanced early or counted blank levels");
        for(bank=0;bank<8;bank=bank+1) begin
            if(image_index!==bank || screen.wallpaper_index!==bank) $fatal(1,"Image order");
            raw_file=$fopen($sformatf("wallpaper_%0d.ppm",bank+1),"wb");
            screen_file=$fopen($sformatf("gallery_%0d.ppm",bank+1),"wb");
            $fwrite(raw_file,"P6\n800 600\n255\n");
            $fwrite(screen_file,"P6\n800 600\n255\n");
            raw_count=0;screen_count=0;capturing=1;
            for(yy=0;yy<600;yy=yy+1)
                for(xx=0;xx<800;xx=xx+1) begin
                    @(negedge clk);x=xx;y=yy;de=1;
                    if(image_index!==bank) $fatal(1,"Wallpaper tore during active frame");
                end
            @(negedge clk);de=0;
            repeat(4) @(negedge clk);
            capturing=0;$fclose(raw_file);$fclose(screen_file);
            if(raw_count!=480000 || screen_count!=480000) $fatal(1,"Pixel loss in gallery");
            blank_frame();
            if(image_index!==((bank+1)%8)) $fatal(1,"Slideshow order/wrap");
            blank_frame();
            if(image_index!==((bank+1)%8)) $fatal(1,"Hold period");
        end
        rst=1;repeat(3) @(negedge clk);
        if(image_index!==0) $fatal(1,"Reset did not restore first wallpaper");
        $display("PASS: eight image banks, blank-edge hold, active-frame stability, wrap, reset, RGB export");
        $display("ALL TESTS PASSED");$finish;
    end
    initial begin #150000000;$fatal(1,"Wallpaper watchdog");end
endmodule
