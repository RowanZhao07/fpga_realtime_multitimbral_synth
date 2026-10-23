`timescale 1ns/1ps
module tb_video;
    GSR GSR(.GSRI(1'b1));
    reg clk=0; always #12.5 clk=~clk;
    reg rst=1;
    wire [10:0] x; wire [9:0] y; wire de,hs,vs,blank;
    video_timing timing(.clk(clk),.rst(rst),.x(x),.y(y),.de(de),.hs(hs),.vs(vs),.vertical_blank(blank));
    wire [9:0] addr; reg [7:0] data=0;
    wire [23:0] rgb;wire od,oh,ov;
    // Deterministic input fixtures for visual layout; not claimed as board audio.
    reg [203:0] status=0;
    reg [1:0] octave_select=1;
    wire [12:0] fixture_active={status[49:45],status[15:8]};
    wire [103:0] fixture_levels;
    for(genvar v=0;v<13;v=v+1) begin: feedback_fixture
        assign fixture_levels[v*8+:8]=fixture_active[v] ? 8'd192 : 8'd0;
    end
    reg expected_adc_online=0,expected_debug=0;
    integer expected_mv=0;
    instrument_screen screen(.sustain_info(6'd0),.clk(clk),.rst(rst),.x(x),.y(y),.de(de),.hs(hs),.vs(vs),
        .vertical_blank(blank),.status(status),.performance_info({6'd13,10'd192,9'd4,7'd0}),.visual_ready(1'b1),.visual_data(data),
        .voice_levels(fixture_levels),.octave_select(octave_select),.scope_ready(1'b1),.scope_data(data),.scope_address(),
        .visual_address(addr),.rgb(rgb),.out_de(od),.out_hs(oh),.out_vs(ov));
    reg [2:0] sync1=0,sync2=0,sync3=0;
    reg [10:0] rendered_x1=0,rendered_x2=0,rendered_x3=0;
    reg [9:0] rendered_y1=0,rendered_y2=0,rendered_y3=0;
    integer warm=0,wave_pixels=0,fft_pixels=0,wallpaper_changes=0;
    reg [23:0] last_wallpaper_pixel=0;
    always @(posedge clk) begin
        sync1<={de,hs,vs};sync2<=sync1;sync3<=sync2;
        rendered_x1<=x;rendered_x2<=rendered_x1;
        rendered_y1<=y;rendered_y2<=rendered_y1;
        rendered_x3<=rendered_x2;rendered_y3<=rendered_y2;
        if(rst) warm<=0;else warm<=warm+1;
    end
    always @(negedge clk) if(!rst && warm>3) begin
        if(screen.text_pixel && !screen.panel_inner)
            $fatal(1,"Text glyph escapes a card at %0d,%0d",screen.px,screen.py);
        if({od,oh,ov}!==sync3) $fatal(1,"Screen RGB/sync pipeline changed");
        if(!od && rgb!==0) $fatal(1,"Blanking must stay black");
        // The unobstructed left margin must contain an image, not a solid fill.
        if(od && rendered_x3==4 && rendered_y3>=72 && rendered_y3<560) begin
            if(rgb!==last_wallpaper_pixel) wallpaper_changes=wallpaper_changes+1;
            last_wallpaper_pixel=rgb;
        end
        if(od && rendered_x3>=28 && rendered_x3<540) begin
            if(rendered_y3>=244 && rendered_y3<=372 && rgb==24'h48E0C0) wave_pixels=wave_pixels+1;
            if(rendered_y3>=436 && rendered_y3<524 && rgb[23:16]<128 && rgb[15:8]>140 && rgb[7:0]>170) fft_pixels=fft_pixels+1;
        end
    end
    always @(posedge clk) begin
        if(!addr[9]) data<=$rtoi(65*$sin(6.2831853*addr[8:0]/128));
        else data<=addr[8:0]<200 ? ((addr[5:0]<4) ? (120-(addr[8:0]>>1)) : 8'd0) : 0;
    end
    reg en_de=0,c0=0,c1=0;reg [7:0] byte_data=0;
    wire [9:0] symbol;
    tmds_encoder encoder(.clk(clk),.rst(rst),.de(en_de),.c0(c0),.c1(c1),.data(byte_data),.symbol(symbol));
    integer f,pixels=0,frames=0,total=0,active_pixels=0,hs_pixels=0,vs_pixels=0;
    integer n,b,bitn,rd=0,oct;
    reg [7:0] decoded,q;
    // Check semantic labels and live values in their new card-local positions.
    always @(negedge clk) if(!rst && warm>3) begin
        if(screen.py==102 && screen.px==86 && screen.character!=="#")
            $fatal(1,"Black key C#4 missing: character=%h",screen.character);
        if(screen.py==146 && screen.px==48 && screen.character!=="C")
            $fatal(1,"White C4 note label is missing");
        if(screen.py==146 && screen.px==60 && screen.character!==8'd51+screen.display_octave)
            $fatal(1,"First C octave digit is stale");
        if(screen.py==146 && screen.px==508 && screen.character!==8'd52+screen.display_octave)
            $fatal(1,"Upper C octave digit is stale");
        if(screen.py==44 && screen.px==256 && screen.character!==8'd51+screen.display_octave)
            $fatal(1,"Octave header is stale");
        if(screen.py==568 && screen.px==712 && screen.character!=="6")
            $fatal(1,"Octave shortcut footer truncated");
        if(screen.py==204 && screen.px==28 && screen.character!=="D")
            $fatal(1,"Waveform must be identified as DIGITAL WAVE");
        if(screen.py==224 && screen.px==28 && screen.character!=="I")
            $fatal(1,"I2S output label lost its leading character");
        if(screen.py==224 && screen.px==316 && screen.character!=="G")
            $fatal(1,"Trigger label truncated");
        if(expected_adc_online && screen.py==160) begin
            if(screen.px==576 && screen.character!==(48+expected_mv/1000)) $fatal(1,"ADC whole volts digit");
            if(screen.px==588 && screen.character!==".") $fatal(1,"ADC decimal point");
            if(screen.px==600 && screen.character!==(48+(expected_mv/100)%10)) $fatal(1,"ADC hundreds digit");
            if(screen.px==612 && screen.character!==(48+(expected_mv/10)%10)) $fatal(1,"ADC tens digit");
            if(screen.px==624 && screen.character!==(48+expected_mv%10)) $fatal(1,"ADC units digit");
        end
        if(screen.py==192 && screen.px==600 &&
            screen.color!==(expected_adc_online ? 24'h48E0C0 : 24'h25364B))
            $fatal(1,"Pressure bar must represent valid ADC data");
        if(screen.py==192 && screen.px==740 && screen.color!==24'h25364B)
            $fatal(1,"Pressure bar should be empty beyond 2V");
        if(expected_adc_online && expected_debug) begin
            if(screen.py==44 && screen.px==652 && screen.character!=="E") $fatal(1,"LED TEST mode not displayed");
            if(screen.py==496 && screen.px==612 && screen.character!=="3") $fatal(1,"UART 3F high nibble");
            if(screen.py==496 && screen.px==624 && screen.character!=="F") $fatal(1,"UART 3F low nibble");
            if(screen.py==496 && screen.px==660 && screen.character!=="A") $fatal(1,"UART 0A low nibble");
            if(screen.py==520 && screen.px==660 && screen.character!=="4") $fatal(1,"UART 54 low nibble");
            if(screen.py==520 && screen.px==696 && screen.character!=="0") $fatal(1,"Captured zero vs missing byte");
            if(screen.py==520 && screen.px==732 && screen.character!=="-") $fatal(1,"Missing UART byte");
        end
        if(expected_adc_online && !expected_debug) begin
            if(screen.py==476 && screen.px==636 && screen.character!=="9") $fatal(1,"BPM 090");
            if(screen.py==452 && screen.px==708 && screen.character!=="2") $fatal(1,"Score length 192");
            if(screen.py==524 && screen.px==636 && screen.character!=="2") $fatal(1,"RX 012");
            if(screen.py==524 && screen.px==720 && screen.character!=="2") $fatal(1,"ERR 002");
            if(screen.py==166 && screen.px==48 && screen.color!==24'hF2BE55) $fatal(1,"White chord target border");
            if(screen.py==90 && screen.px==80 && screen.color!==24'hF2BE55) $fatal(1,"Sharp target border");
        end
    end
    task capture_frame(input string filename);
        begin
            pixels=0;active_pixels=0;hs_pixels=0;vs_pixels=0;total=0;
            wait(x==0 && y==0);
            f=$fopen(filename,"wb"); $fwrite(f,"P6\n800 600\n255\n");
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
        end
    endtask
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
        status={8'd2,8'd12,1'b1,7'd64,8'd90,13'h105,1'b1,12'd2000,1'b1,2'b11,5'h1F,5'h15,2'b0,1'b0,6'd4,3'd5,1'b1,1'b0,1'b1,1'b1,1'b1,5'd12,2'd2,8'hFF,8'h15};
        status[194:111]={8'd255,8'd1,4'd7,64'h3F0A450D0A540000};
        status[195]=1;
        status[39]=1;
        wait(blank); @(negedge clk);
        expected_adc_online=1;expected_debug=1;expected_mv=2000;
        capture_frame("screen_debug.ppm");
        status[195]=0;
        status[39]=0;
        wait(blank); @(negedge clk);expected_debug=0;
        capture_frame("screen.ppm");
        for(oct=0;oct<4;oct=oct+1) begin
            octave_select=oct;wait(blank);@(negedge clk);
            capture_frame($sformatf("screen_octave_%0d.ppm",oct+3));
        end
        octave_select=1;
        // Longest offline/test labels and a non-step UART gain value.
        status[23]=0;status[50]=0;status[65]=0;status[26]=1;status[37]=1;
        status[17:16]=1;status[22:18]=15;status[203:196]=255;
        wait(blank); repeat(2) @(negedge clk);expected_adc_online=0;
        if(screen.volume_text!=="099") $fatal(1,"V4095 must display 099 percent, got %s",screen.volume_text);
        capture_frame("screen_offline.ppm");
        if(wallpaper_changes>1) $fatal(1,"Background must be the resource-free solid color");
        if(wave_pixels<1000 || fft_pixels<1000) $fatal(1,"Waveform or FFT is missing from the default UI");
        $display("PASS: TMDS round-trip/disparity; 800x600 raster; normal/debug/offline HUD, glyph bounds and precise gain");
        $display("ALL TESTS PASSED"); $finish;
    end
    initial begin #350000000; $fatal(1,"Video watchdog"); end
endmodule
