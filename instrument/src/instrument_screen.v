`timescale 1ns/1ps
// Streaming raster renderer: no external memory or processor.
module instrument_screen #(parameter ENABLE_EC11=1'b0,parameter TOUCH_DEBUG=1'b0, parameter integer WALLPAPER_HOLD_FRAMES=600)(
    input wire [5:0] sustain_info,
    input wire clk,rst,input wire [10:0] x,input wire [9:0] y,
    input wire de,hs,vs,vertical_blank,input wire [203:0] status,
    input wire [103:0] voice_levels,
    input wire [1:0] octave_select,
    input wire [31:0] performance_info,
    input wire scope_ready,input wire [7:0] scope_data,output wire [8:0] scope_address,
    input wire visual_ready,input wire [7:0] visual_data,
    output wire [9:0] visual_address,
    output reg [23:0] rgb=0,output reg out_de=0,out_hs=0,out_vs=0);
    reg [10:0] px0=0,px=0; reg [9:0] py0=0,py=0;
    reg de0=0,hs0=0,vs0=0;
    reg de_delay=0,hs_delay=0,vs_delay=0;
    reg [7:0] plot_data=0;
    reg signed [7:0] scope_plot=0,previous_scope=0;
    reg scope_ready0=0,scope_plot_ready=0;
    reg ready0=0,plot_ready=0;
    wire [23:0] wallpaper_rgb=24'h0B1220;
    wire [2:0] wallpaper_index=0;
    reg [203:0] display_status=0;
    reg [5:0] display_sustain=0;
    reg [31:0] display_performance=0;
    reg [103:0] display_levels=0;
    reg [1:0] display_octave=2'd1;
    wire [7:0] octave_digit=8'd51+{6'd0,display_octave};
    wire diagnostics_visible=display_status[195];
    wire [83:0] uart_diagnostics=display_status[194:111];
    wire [7:0] uart_bytes=uart_diagnostics[83:76],uart_frames=uart_diagnostics[75:68];
    wire [3:0] uart_capture_count=uart_diagnostics[67:64];
    wire [63:0] uart_first_bytes=uart_diagnostics[63:0];
    wire [12:0] guide_mask=display_status[78:66];
    wire [7:0] bpm=display_status[86:79];
    wire [9:0] score_length=display_performance[25:16];
    wire custom_score=display_status[94];
    wire [7:0] rx_ok=display_status[102:95],rx_error=display_status[110:103];
    wire adc_online=display_status[65];
    wire [11:0] pressure_mv=display_status[64:53];
    wire [12:0] gates={display_status[44:40],display_status[7:0]};
    wire [12:0] active={display_status[49:45],display_status[15:8]};
    wire [1:0] timbre=display_status[17:16];
    wire [4:0] volume=display_status[22:18];
    wire [12:0] full_volume={volume,display_status[203:196]};
    wire [20:0] volume_bar_product=full_volume*8'd192;
    wire online=display_status[23],vibrato=display_status[24],echo_on=display_status[25];
    wire test_on=display_status[26],guide_on=display_status[27];
    wire lamp_test=display_status[39];
    wire [8:0] position=display_performance[15:7];
    wire [10:0] plot_x=x-11'd28;
    assign visual_address={y>=396,plot_x[8:0]};
    assign scope_address=plot_x[8:0];
    wire [10:0] key_offset=px-11'd28;
    wire [2:0] key_index=key_offset[8:6];
    wire [7:0] key_level=display_levels>>(key_index*8);
    wire [13:0] key_meter=key_level*6'd56;
    wire [7:0] tail_blue=8'd128+{1'b0,key_level[7:1]};
    wire [7:0] pressure_width=pressure_mv>=3072 ? 8'd192 : {1'b0,pressure_mv[11:4]};
    // Status text is formatted only at the coherent vertical-blank snapshot.
    reg [55:0] pressure_text="0.000 V";
    reg [23:0] volume_text="000",bpm_text="000",rx_text="000",error_text="000";
    reg [15:0] voice_text="00";
    reg [23:0] step_text="001",length_text="192";
    function [7:0] digit;
        input integer n;
        begin digit=8'd48+n;end
    endfunction
    function [23:0] decimal3;
        input integer n;
        begin decimal3={digit((n/100)%10),digit((n/10)%10),digit(n%10)};end
    endfunction
    function [15:0] decimal2;
        input integer n;
        begin decimal2={digit((n/10)%10),digit(n%10)};end
    endfunction
    function [3:0] count_voices;
        input [12:0] mask;integer n;
        begin count_voices=0;for(n=0;n<13;n=n+1) count_voices=count_voices+mask[n];end
    endfunction
    function [7:0] hex_character;
        input [3:0] nibble;
        begin hex_character=nibble<10 ? 8'd48+{4'd0,nibble} : 8'd55+{4'd0,nibble};end
    endfunction
    function [15:0] trace_hex;
        input integer slot;input [63:0] bytes;input [3:0] count;
        reg [7:0] value;
        begin
            value=bytes >> ((7-slot)*8);
            trace_hex=count>slot ? {hex_character(value[7:4]),hex_character(value[3:0])} : "--";
        end
    endfunction
    function [15:0] white_note;
        input integer note;
        input [7:0] oct;
        begin case(note)
            0:white_note={"C",oct};1:white_note={"D",oct};2:white_note={"E",oct};3:white_note={"F",oct};
            4:white_note={"G",oct};5:white_note={"A",oct};6:white_note={"B",oct};default:white_note={"C",(oct+8'd1)};
        endcase end
    endfunction
    function [23:0] sharp_note;
        input integer note;
        input [7:0] oct;
        begin case(note)
            0:sharp_note={"C#",oct};1:sharp_note={"D#",oct};2:sharp_note={"F#",oct};
            3:sharp_note={"G#",oct};default:sharp_note={"A#",oct};
        endcase end
    endfunction
    // Every label has a local origin and an explicit width, rather than a
    // global text grid. A 12x16 cell contains a 10x14 doubled 5x7 glyph.
    reg text_visible;
    reg [10:0] text_dx;reg [9:0] text_dy;
    reg [5:0] text_length;
    reg [511:0] text_line;
    reg [23:0] text_ink;
    // Stage 1 locates a label. Stage 2 decodes its glyph. Stage 3 blends RGB.
    // These align with px0, px and rgb, retaining the original three-clock delay.
    reg label_visible=0;
    reg [10:0] label_dx=0;reg [9:0] label_dy=0;
    reg [5:0] label_length=0;
    reg [511:0] label_line=0;
    reg [23:0] label_ink=0,glyph_ink=0;
    wire [21:0] text_quotient=label_dx*11'd683;
    wire [5:0] text_col=text_quotient[18:13]; // exact /12 within every label (<64 cells)
    wire [5:0] reverse_col=label_length-6'd1-text_col;
    wire [10:0] text_cell_x=label_dx-text_col*12;
    reg [7:0] next_character;
    reg [7:0] character=32;
    reg text_pixel=0;
    wire [4:0] glyph;
    font_lut font(.character(next_character),.row(label_dy[3:1]),.pixels(glyph));
    wire next_text_pixel=label_visible && label_dy<14 && text_cell_x<10 && glyph[4-text_cell_x[3:1]];
    task label;
        input [10:0] raster_x;input [9:0] raster_y;
        input [10:0] left;input [9:0] top;input [5:0] length;
        input [511:0] line;
        input [23:0] ink;
        begin
            if(raster_x>=left && raster_x<left+length*11'd12 && raster_y>=top && raster_y<top+10'd14) begin
                // Labels never overlap: OR selection permits a balanced mux tree
                // instead of a long priority chain through every card's labels.
                text_visible=1;text_dx=text_dx | (raster_x-left);text_dy=text_dy | (raster_y-top);
                text_length=text_length | length;text_line=text_line | line;text_ink=text_ink | ink;
            end
        end
    endtask
    integer key_label,sharp_label;
    always @* begin
        text_visible=0;text_dx=0;text_dy=0;text_length=0;text_line=0;text_ink=0;
        label(x,y,28,24,28,"TANG MEGA / POLYPHONIC SYNTH",24'hF1F1FA);
        label(x,y,28,44,20,{"32 VOICES / OCTAVE ",octave_digit},24'h9CAEC9);
        case(timbre)
            0:label(x,y,416,24,9,"TONE SINE",24'hC8BCFF);
            1:label(x,y,416,24,11,"TONE EPIANO",24'hC8BCFF);
            2:label(x,y,416,24,12,"TONE STRINGS",24'hC8BCFF);
            3:label(x,y,416,24,10,"TONE METAL",24'hC8BCFF);
        endcase
        label(x,y,416,44,9,"48.8K I2S",24'h9CAEC9);
        label(x,y,640,44,lamp_test ? 8 : test_on ? 11 : 10,lamp_test ? "LED TEST" : test_on ? "8 SINE TEST" : TOUCH_DEBUG ? "SUST DEBUG" : guide_on ? (display_performance[6] ? "REST      " : display_performance[5] ? "HOLD      " : "WAIT NOTE ") : "LIVE INPUT",24'hC8BCFF);
        for(key_label=0;key_label<8;key_label=key_label+1)
            label(x,y,48+64*key_label,146,2,white_note(key_label,octave_digit),24'h142137);
        for(sharp_label=0;sharp_label<5;sharp_label=sharp_label+1)
            label(x,y,74+64*(sharp_label<2 ? sharp_label : sharp_label+1),102,3,sharp_note(sharp_label,octave_digit),24'hF1F1FA);
        label(x,y,28,204,12,"DIGITAL WAVE",24'hC8BCFF);
        label(x,y,508,204,2,"4X",24'h9CAEC9);
        label(x,y,28,224,25,"I2S OUT / 10.49 MS / TRIG",24'h9CAEC9);
        label(x,y,28,408,8,"SPECTRUM",24'hC8BCFF);
        label(x,y,396,408,11,"4096 / HANN",24'h9CAEC9);
        label(x,y,28,532,1,"0",24'h9CAEC9);
        label(x,y,140,532,4,"1.5K",24'h9CAEC9);
        label(x,y,272,532,2,"3K",24'h9CAEC9);
        label(x,y,396,532,4,"4.5K",24'h9CAEC9);
        label(x,y,516,532,2,"6K",24'h9CAEC9);
        label(x,y,576,88,online ? 12 : 13,online ? "TOUCH ONLINE" : "TOUCH OFFLINE",online ? 24'h48E0C0 : 24'hFFA3A8);
        label(x,y,576,112,14,{"VOICES ",voice_text," / 32"},24'hF1F1FA);
        label(x,y,576,140,8,"PRESSURE",24'hC8BCFF);
        label(x,y,576,160,7,adc_online ? pressure_text : "-.--- V",24'hF1F1FA);
        label(x,y,adc_online ? 696 : 684,160,adc_online ? 6 : 7,adc_online ? "ADC OK" : "ADC OFF",adc_online ? 24'h48E0C0 : 24'hFFA3A8);
        label(x,y,576,244,11,"MASTER GAIN",24'hC8BCFF);
        label(x,y,720,244,4,{volume_text,"%"},24'hF1F1FA);
        label(x,y,576,296,echo_on ? 7 : 8,echo_on ? "ECHO ON" : "ECHO OFF",24'hF1F1FA);
        label(x,y,576,320,vibrato ? 6 : 7,vibrato ? "VIB ON" : "VIB OFF",24'hF1F1FA);
        label(x,y,576,356,11,"PRE-SPEAKER",24'h9CAEC9);
        if(display_status[37]) label(x,y,720,320,4,"CLIP",24'hFFA3A8);
        if(diagnostics_visible) begin
            label(x,y,576,408,10,"UART DEBUG",24'hC8BCFF);
            label(x,y,576,432,11,{"BY",decimal3(uart_bytes)," FR",decimal3(uart_frames)},24'hF1F1FA);
            label(x,y,576,452,11,{"RX",rx_text," ER",error_text},24'hF1F1FA);
            label(x,y,576,472,8,{"A",digit(display_status[50])," B",digit(display_status[51])," X",digit(display_status[52])},24'hF1F1FA);
            label(x,y,576,496,14,{"D0 ",trace_hex(0,uart_first_bytes,uart_capture_count)," ",trace_hex(1,uart_first_bytes,uart_capture_count)," ",trace_hex(2,uart_first_bytes,uart_capture_count)," ",trace_hex(3,uart_first_bytes,uart_capture_count)},24'hF1F1FA);
            label(x,y,576,520,14,{"D4 ",trace_hex(4,uart_first_bytes,uart_capture_count)," ",trace_hex(5,uart_first_bytes,uart_capture_count)," ",trace_hex(6,uart_first_bytes,uart_capture_count)," ",trace_hex(7,uart_first_bytes,uart_capture_count)},24'hF1F1FA);
        end else begin
            label(x,y,576,408,guide_on ? 8 : 9,guide_on ? "GUIDE ON" : "GUIDE OFF",24'hC8BCFF);
            label(x,y,576,432,custom_score ? 9 : 8,custom_score ? "SONG USER" : "NOCTURNE",24'hF1F1FA);
            label(x,y,576,452,12,{"STEP ",step_text,"/",length_text},24'hF1F1FA);
            label(x,y,576,476,7,{"BPM ",bpm_text},24'hF1F1FA);
            label(x,y,576,500,lamp_test ? 8 : test_on ? 11 : 10,lamp_test ? "LED TEST" : test_on ? "8 SINE TEST" : TOUCH_DEBUG ? "SUST DEBUG" : guide_on ? (display_performance[6] ? "REST      " : display_performance[5] ? "HOLD      " : "WAIT NOTE ") : "LIVE INPUT",24'h9CAEC9);
            label(x,y,576,524,13,{"RX ",rx_text," ER ",error_text},24'h9CAEC9);
        end
        if(ENABLE_EC11)
            label(x,y,28,568,40,{"EC11 SUST ",display_sustain[5] ? "ON " : "OFF"," L",decimal2({27'd0,display_sustain[4:0]}),"/16  TURN / PUSH TOGGLE"},24'hCAD4E6);
        else if(TOUCH_DEBUG)
            label(x,y,28,568,36,"DEFAULT SUSTAIN  UART H0 OFF / H1 ON",24'hCAD4E6);
        else label(x,y,28,568,58,"C0 TONE/ECHO C1/2 GAIN C3 VIB C1+C2 GUIDE X0+C0..3 OCT3..6",24'hCAD4E6);
    end
    always @* begin
        next_character=8'd32;
        if(label_visible && text_col<label_length)
            next_character=label_line >> {reverse_col,3'b000};
    end
    // Constant-radius raster mask: no run-time square root or multipliers.
    function rounded;
        input [10:0] xx,left,right;
        input [9:0] yy,top,bottom;
        reg [9:0] edge_y;
        reg [3:0] inset;
        begin
            edge_y=(yy-top < bottom-1'b1-yy) ? yy-top : bottom-1'b1-yy;
            case(edge_y)
                0:inset=9;1:inset=6;2:inset=5;3:inset=4;
                4:inset=3;5:inset=2;6,7,8:inset=1;
                default:inset=0;
            endcase
            rounded=yy>=top && yy<bottom && xx>=left+inset && xx<right-inset;
        end
    endfunction
    // Subdued translucent cards keep text readable over every wallpaper.
    function [23:0] glass;
        input [23:0] background;
        begin
            glass[23:16]=(background[23:16]>>3)+(background[23:16]>>4)+8'd12;
            glass[15:8]=(background[15:8]>>3)+(background[15:8]>>4)+8'd18;
            glass[7:0]=(background[7:0]>>3)+(background[7:0]>>4)+8'd30;
        end
    endfunction
    // Interpolate eight colour stops across the real 512 FFT bins.
    function [23:0] spectrum_colour;
        input [8:0] bin;
        integer t;
        begin
            t={26'd0,bin[5:0]};
            case(bin[8:6])
                0:begin spectrum_colour[23:16]=73+((10*t)>>6); spectrum_colour[15:8]=229-((13*t)>>6); spectrum_colour[7:0]=206+((38*t)>>6);end
                1:begin spectrum_colour[23:16]=83+((21*t)>>6); spectrum_colour[15:8]=216-((33*t)>>6); spectrum_colour[7:0]=244+((11*t)>>6);end
                2:begin spectrum_colour[23:16]=104+((43*t)>>6); spectrum_colour[15:8]=183-((40*t)>>6); spectrum_colour[7:0]=255;end
                3:begin spectrum_colour[23:16]=147+((52*t)>>6); spectrum_colour[15:8]=143-((5*t)>>6); spectrum_colour[7:0]=255;end
                4:begin spectrum_colour[23:16]=199+((42*t)>>6); spectrum_colour[15:8]=138+((5*t)>>6); spectrum_colour[7:0]=255-((47*t)>>6);end
                5:begin spectrum_colour[23:16]=241+((14*t)>>6); spectrum_colour[15:8]=143+((28*t)>>6); spectrum_colour[7:0]=208-((63*t)>>6);end
                6:begin spectrum_colour[23:16]=255; spectrum_colour[15:8]=171+((39*t)>>6); spectrum_colour[7:0]=145-((22*t)>>6);end
                7:spectrum_colour=24'hFFD27B;
            endcase
        end
    endfunction
    wire panel=rounded(px,16,784,py,12,68) || rounded(px,16,552,py,76,180) ||
        rounded(px,16,552,py,192,384) || rounded(px,16,552,py,396,552) ||
        rounded(px,564,784,py,76,220) || rounded(px,564,784,py,232,384) ||
        rounded(px,564,784,py,396,552) || rounded(px,16,784,py,564,588);
    wire panel_inner=rounded(px,17,783,py,13,67) || rounded(px,17,551,py,77,179) ||
        rounded(px,17,551,py,193,383) || rounded(px,17,551,py,397,551) ||
        rounded(px,565,783,py,77,219) || rounded(px,565,783,py,233,383) ||
        rounded(px,565,783,py,397,551) || rounded(px,17,783,py,565,587);
    wire [23:0] glass_rgb=glass(wallpaper_rgb);
    wire [23:0] bar_rgb=spectrum_colour(key_offset[8:0]);
    wire [23:0] bar_shade={1'b0,bar_rgb[23:17],1'b0,bar_rgb[15:9],1'b0,bar_rgb[7:1]};
    wire [7:0] fft_height=plot_data>>1;
    reg [23:0] color;
    reg signed [11:0] wave_y,previous_y,trace_low,trace_high;
    reg [7:0] sharp_level;
    reg [13:0] sharp_meter;
    integer sharp,dot;
    always @* begin
        color=wallpaper_rgb;
        wave_y=12'sd308-($signed(scope_plot)>>>1);
        previous_y=key_offset==0 ? wave_y : 12'sd308-($signed(previous_scope)>>>1);
        trace_low=wave_y<previous_y ? wave_y : previous_y;
        trace_high=wave_y>previous_y ? wave_y : previous_y;
        sharp_level=0;sharp_meter=0;
        if(panel) color=glass_rgb;
        if(panel && !panel_inner) color=24'h495166;
        if(px>=28 && px<540 && py>=88 && py<168 && key_offset[5:0]<62) begin
            color=gates[key_index] ? 24'h60D9CA :
                active[key_index] ? {8'h91,8'hB9,tail_blue} : 24'hCDD5E5;
            // The meter is the voice ADSR before pressure/master gain and echo.
            if(py>=160 && py<164 && key_offset[5:0]>=3 && key_offset[5:0]<59)
                color=key_offset[5:0]-3<key_meter[13:8] ? 24'h249C8B : 24'hAAB6CA;
            if(guide_on && guide_mask[key_index] && (py<91 || py>=165)) color=24'hF2BE55;
        end
        for(sharp=0;sharp<5;sharp=sharp+1) begin
            sharp_level=display_levels>>((8+sharp)*8);
            sharp_meter=sharp_level*6'd36;
            if(py>=88 && py<134 && px>=(sharp<2 ? 70+64*sharp : 134+64*sharp) &&
                px<(sharp<2 ? 114+64*sharp : 178+64*sharp)) begin
                color=gates[8+sharp] ? 24'h6878B8 :
                    active[8+sharp] ? {8'h32,8'h4C,(8'd80+{1'b0,sharp_level[7:1]})} : 24'h202A41;
                if(py>=124 && py<128 && px>=(sharp<2 ? 74+64*sharp : 138+64*sharp) &&
                    px<(sharp<2 ? 110+64*sharp : 174+64*sharp))
                    color=px-(sharp<2 ? 74+64*sharp : 138+64*sharp)<sharp_meter[13:8] ? 24'h48E0C0 : 24'h29384F;
                if(guide_on && guide_mask[8+sharp] && (py<91 || py>=131)) color=24'hF2BE55;
            end
        end
        if(px>=28 && px<540 && py>=244 && py<=372) begin
            if((py==276 || py==308 || py==340 || key_offset[6:0]==0) && px[1:0]==0) color=24'h3B485F;
            if(scope_plot_ready && $signed({1'b0,py})>=trace_low-2 && $signed({1'b0,py})<=trace_high+2) color=24'h287577;
            if(scope_plot_ready && $signed({1'b0,py})>=trace_low-1 && $signed({1'b0,py})<=trace_high+1) color=24'h48E0C0;
        end
        if(px>=28 && px<540 && py>=436 && py<524) begin
            if((key_offset[6:0]==0 || py==523) && px[1:0]==0) color=24'h3B485F;
            if(plot_ready && py>=523-fft_height && fft_height!=0) begin
                color=py[2:0]==5 ? bar_shade : bar_rgb;
                if(py<=524-fft_height) color=24'hF4EFFF;
            end
        end
        if(px>=576 && px<768 && py>=188 && py<196)
            color=(adc_online && px<576+pressure_width) ? 24'h48E0C0 : 24'h25364B;
        if(px>=576 && px<768 && py>=272 && py<280)
            color=px<576+volume_bar_product[20:12] ? 24'hC8BCFF : 24'h25364B;
        if(!diagnostics_visible && guide_on && display_status[38] && px>=752 && px<764 && py>=476 && py<488)
            color=24'hF2BE55;
        if(text_pixel && panel_inner) color=glyph_ink;
    end
    always @(posedge clk) begin
        px0<=x;py0<=y;de0<=de;hs0<=hs;vs0<=vs;ready0<=visual_ready;
        px<=px0;py<=py0;de_delay<=de0;hs_delay<=hs0;vs_delay<=vs0;
        plot_data<=visual_data;plot_ready<=ready0;
        scope_plot<=scope_data;scope_ready0<=scope_ready;scope_plot_ready<=scope_ready0;
        label_visible<=text_visible;label_dx<=text_dx;label_dy<=text_dy;
        label_length<=text_length;label_line<=text_line;label_ink<=text_ink;
        text_pixel<=next_text_pixel;character<=next_character;glyph_ink<=label_ink;
        if(rst) begin
            display_status<=0;display_sustain<=0;display_levels<=0;rgb<=0;out_de<=0;out_hs<=0;out_vs<=0;
            display_octave<=2'd1;display_performance<=0;
            scope_plot<=0;previous_scope<=0;scope_ready0<=0;scope_plot_ready<=0;
            de0<=0;de_delay<=0;hs0<=0;hs_delay<=0;vs0<=0;vs_delay<=0;
            ready0<=0;plot_ready<=0;
            label_visible<=0;text_pixel<=0;character<=32;glyph_ink<=0;
            pressure_text<="0.000 V";volume_text<="000";bpm_text<="000";
            rx_text<="000";error_text<="000";voice_text<="00";step_text<="01";length_text<="00";
        end else begin
            if(de_delay && px>=28 && px<540 && py>=244 && py<=372) previous_scope<=scope_plot;
            if(vertical_blank) begin
                display_status<=status;display_sustain<=sustain_info;
                display_levels<=voice_levels;
                display_octave<=octave_select;display_performance<=performance_info;
                pressure_text<={digit(status[64:53]/1000),".",decimal3(status[64:53]%1000)," V"};
                volume_text<=decimal3(({status[22:18],status[203:196]}*100)/4096);
                voice_text<=decimal2(performance_info[31:26]);
                step_text<=decimal3({1'b0,performance_info[15:7]}+10'd1);
                length_text<=decimal3(performance_info[25:16]);bpm_text<=decimal3(status[86:79]);
                rx_text<=decimal3(status[102:95]);error_text<=decimal3(status[110:103]);
            end
            rgb<=de_delay ? color : 24'd0;
            out_de<=de_delay; out_hs<=hs_delay; out_vs<=vs_delay;
        end
    end
endmodule
