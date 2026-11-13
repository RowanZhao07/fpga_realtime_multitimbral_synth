`timescale 1ns/1ps
// Streaming raster renderer: no external memory or processor.
module instrument_screen #(parameter TOUCH_ISOLATION=1'b0,parameter ENABLE_EXPRESSION=1'b0,parameter WIRING_DEBUG=1'b0,parameter ENABLE_JOYSTICK=1'b0,parameter ENABLE_EC11=1'b0,parameter TOUCH_DEBUG=1'b0, parameter integer WALLPAPER_HOLD_FRAMES=600)(
    input wire [279:0] isolation_status,
    input wire [59:0] wiring_status,
    input wire [5:0] sustain_info,
    input wire clk,rst,input wire [10:0] x,input wire [9:0] y,
    input wire de,hs,vs,vertical_blank,input wire [203:0] status,
    input wire [103:0] voice_levels,
    input wire [1:0] octave_select,
    input wire [32:0] performance_info,
    input wire [17:0] metronome_info,
    input wire scope_ready,input wire [7:0] scope_data,output wire [8:0] scope_address,
    input wire liss_ready,liss_data,output wire [13:0] liss_address,
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
    wire [23:0] wallpaper_rgb;
    wire [2:0] wallpaper_index;
    generate if(ENABLE_EXPRESSION && !WIRING_DEBUG && !TOUCH_ISOLATION) begin: background
        wallpaper_renderer #(.HOLD_FRAMES(WALLPAPER_HOLD_FRAMES)) wallpaper(
            .clk(clk),.rst(rst),.vertical_blank(vertical_blank),.x(x),.y(y),
            .rgb(wallpaper_rgb),.image_index(wallpaper_index));
    end else begin: plain_background
        assign wallpaper_rgb=24'h0B1220;assign wallpaper_index=0;
    end endgenerate
    reg liss_plot=0,liss_ready0=0,liss_plot_ready=0;
    wire [10:0] liss_x=x-11'd360;
    wire [9:0] liss_y=y-10'd244;
    assign liss_address={liss_y[6:0],liss_x[6:0]};
    reg [203:0] display_status=0;
    reg [59:0] display_wiring=0;
    reg [279:0] display_isolation=0;
    reg [103:0] isolation_a_text[0:6],isolation_b_text[0:6];
    wire [2:0] isolation_stage=display_isolation[226:224];
    wire isolation_done=display_isolation[232];
    reg [55:0] joystick_text="0.000 V";
    reg [5:0] display_sustain=0;
    reg [32:0] display_performance=0;
    reg [17:0] display_metronome=18'd123264;
    reg [23:0] metro_bpm_text="120";
    wire [2:0] metro_meter=display_metronome[9:7],metro_beat=display_metronome[6:4];
    wire metro_enabled=display_metronome[3],metro_flash=display_metronome[2];
    wire [2:0] metro_beats=metro_meter<2 ? 2 : metro_meter==2 ? 3 : metro_meter==3 ? 4 : 6;
    wire [23:0] meter_text=metro_meter==0 ? "2/2" : metro_meter==1 ? "2/4" : metro_meter==2 ? "3/4" : metro_meter==3 ? "4/4" : "6/8";
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
    wire [2:0] timbre={display_performance[32],display_status[17:16]};
    wire [4:0] volume=display_status[22:18];
    wire [12:0] full_volume={volume,display_status[203:196]};
    wire [20:0] volume_bar_product=full_volume*8'd192;
    wire online=display_status[23],vibrato=display_status[24],echo_on=display_status[25];
    wire touch_fault_visible=ENABLE_EXPRESSION && !online;
    wire test_on=display_status[26],guide_on=display_status[27];
    wire lamp_test=display_status[39];
    wire [8:0] position=display_performance[15:7];
    wire [10:0] plot_x=x-11'd28;
    wire [10:0] compact_plot_x=x-11'd284;
    assign visual_address=ENABLE_EXPRESSION ? {2'b0,compact_plot_x[7:0]} : {y>=396,plot_x[8:0]};
    // Keep the 512-sample / 10.49 ms capture; show alternate points in 256 px.
    assign scope_address=ENABLE_EXPRESSION ? {plot_x[7:0],1'b0} : plot_x[8:0];
    wire [10:0] key_offset=px-11'd28;
    wire [2:0] key_index=key_offset[8:6];
    wire [7:0] key_level=display_levels>>(key_index*8);
    wire [13:0] key_meter=key_level*6'd56;
    wire [7:0] tail_blue=8'd128+{1'b0,key_level[7:1]};
    wire [7:0] pressure_width;
    pressure_mapping pressure_meter(.millivolts(pressure_mv),.gain(),.bar_width(pressure_width));
    // Status text is formatted only at the coherent vertical-blank snapshot.
    reg [55:0] pressure_text="0.000 V";
    reg [23:0] volume_text="000",bpm_text="000",rx_text="000",error_text="000";
    reg [15:0] voice_text="00";
    reg [23:0] step_text="001",length_text="076";
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
    function [63:0] fault_name;
        input [3:0] code;
        begin case(code)
            0:fault_name="NONE    ";1:fault_name="NO ACK  ";
            2:fault_name="SCL LOW ";3:fault_name="SDA BUS ";
            4:fault_name="TIMEOUT ";5:fault_name="CONFIG  ";
            6:fault_name="OVERCUR ";7:fault_name="NOT RDY ";
            default:fault_name="UNKNOWN ";
        endcase end
    endfunction
    function [7:0] idle_digit;
        input valid,level;
        begin idle_digit=valid ? (level ? "1" : "0") : "-";end
    endfunction
    function [87:0] isolation_name;
        input integer n;
        begin case(n)
            0:isolation_name="0 BASE     ";1:isolation_name="1 CORE     ";
            2:isolation_name="2 I2S      ";3:isolation_name="3 FFT/SCOPE";
            4:isolation_name="4 NO LED   ";5:isolation_name="5 FULL     ";
            default:isolation_name="6 BASE     ";
        endcase end
    endfunction
    // Short labels keep the existing three-stage text pipeline timing bounded.
    task wiring_row;
        input [9:0] top;
        input [95:0] name;
        input [23:0] scl_pin,sda_pin;
        input connected;
        input [15:0] info;
        begin
            label(x,y,40,top,12,name,24'hC8BCFF);
            label(x,y,656,top,7,connected ? "ONLINE " : "OFFLINE",connected ? 24'h48E0C0 : 24'hFFA3A8);
            label(x,y,40,top+28,7,{"SCL ",scl_pin},24'hCAD4E6);
            label(x,y,148,top+28,1,idle_digit(info[14],info[13]),24'hF1F1FA);
            label(x,y,220,top+28,7,{"SDA ",sda_pin},24'hCAD4E6);
            label(x,y,328,top+28,1,idle_digit(info[14],info[12]),24'hF1F1FA);
            label(x,y,412,top+28,11,"IDLE SAMPLE",24'h9CAEC9);
            label(x,y,40,top+52,7,{"LAST E",hex_character(info[3:0])},24'hCAD4E6);
            label(x,y,148,top+52,8,fault_name(info[3:0]),info[3:0]!=0 ? 24'hF2BE55 : 24'h48E0C0);
            label(x,y,360,top+52,8,{"FAIL ",decimal3({24'd0,info[11:4]})},24'hCAD4E6);
        end
    endtask
    integer key_label,sharp_label,isolation_row,isolation_format;
    always @* begin
        text_visible=0;text_dx=0;text_dy=0;text_length=0;text_line=0;text_ink=0;
        if(TOUCH_ISOLATION) begin
            label(x,y,28,24,18,"TOUCH ISOLATION T1",24'hF1F1FA);
            label(x,y,520,24,18,isolation_done ? "DONE / DATA FROZEN" : "AUTO / HANDS OFF  ",24'hF2BE55);
            label(x,y,28,52,15,{"A",digit(display_status[50])," B",digit(display_status[51])," ADC",digit(adc_online)," R",decimal3({24'd0,display_isolation[247:240]})},24'hCAD4E6);
            label(x,y,280,52,15,{"MODE ",digit({29'd0,isolation_stage})," LEFT ",decimal2({27'd0,display_isolation[231:227]}),"S"},24'hCAD4E6);
            label(x,y,556,52,10,isolation_done ? "FROZEN    " : display_isolation[233] ? "SETTLING  " : "MEASURING ",24'h9CAEC9);
            label(x,y,28,80,21,{"FFT ",hex_character(display_isolation[263:260]),hex_character(display_isolation[259:256])," FR ",hex_character(display_isolation[271:268]),hex_character(display_isolation[267:264])," SCOPE ",hex_character(display_isolation[279:276]),hex_character(display_isolation[275:272])},24'h9CAEC9);
            label(x,y,28,112,5,"STAGE",24'hC8BCFF);
            label(x,y,196,112,7,"TOUCH A",24'hC8BCFF);
            label(x,y,420,112,7,"TOUCH B",24'hC8BCFF);
            label(x,y,652,112,6,"WINDOW",24'hC8BCFF);
            for(isolation_row=0;isolation_row<7;isolation_row=isolation_row+1) begin
                label(x,y,28,144+44*isolation_row,11,isolation_name(isolation_row),24'hF1F1FA);
                if(display_isolation[isolation_row*32+28]) begin
                    label(x,y,196,144+44*isolation_row,13,isolation_a_text[isolation_row],
                        display_isolation[isolation_row*32+24] ? 24'hFFA3A8 : 24'h48E0C0);
                    label(x,y,420,144+44*isolation_row,13,isolation_b_text[isolation_row],
                        display_isolation[isolation_row*32+25] ? 24'hFFA3A8 : 24'h48E0C0);
                end else begin
                    label(x,y,196,144+44*isolation_row,13,"--- NOT YET  ",24'h9CAEC9);
                    label(x,y,420,144+44*isolation_row,13,"--- NOT YET  ",24'h9CAEC9);
                end
                label(x,y,652,144+44*isolation_row,7,isolation_done || isolation_row<isolation_stage ? "DONE   " :
                    isolation_row==isolation_stage ? "ACTIVE " : "WAIT   ",isolation_row==isolation_stage ? 24'hF2BE55 : 24'h9CAEC9);
            end
            label(x,y,28,456,40,"F FAILS  E ERROR  U SEEN UP  D SEEN DOWN",24'h9CAEC9);
            label(x,y,28,484,35,"2S SETTLE + 20S COUNT IN EACH STAGE",24'h9CAEC9);
            label(x,y,28,512,36,"NO TOUCH / NO REWIRING / ABOUT 3 MIN",24'hCAD4E6);
            label(x,y,28,552,38,isolation_done ? "DONE: TAKE ONE FULL-SCREEN PHOTO      " : "AUTO TEST: KEEP WIRING UNCHANGED      ",24'hF2BE55);
        end else if(WIRING_DEBUG) begin
            label(x,y,28,24,22,"WIRING CHECK / GPIO V1",24'hF1F1FA);
            label(x,y,28,48,28,"B16: JOYSTICK SUPPLY ENABLED",24'h9CAEC9);
            label(x,y,656,24,6,"SILENT",24'hF2BE55);
            wiring_row(88,"TOUCH A 0X5A","E14","E13",display_status[50],display_wiring[15:0]);
            wiring_row(196,"TOUCH B 0X5A","A16","A15",display_status[51],display_wiring[31:16]);
            wiring_row(304,"ADC     0X48","A20","B20",adc_online,display_wiring[47:32]);
            label(x,y,40,408,9,"PRESSURE ",24'hCAD4E6);
            label(x,y,160,408,7,adc_online ? pressure_text : "-.--- V",24'hF1F1FA);
            label(x,y,376,408,9,"JOYSTICK ",24'hCAD4E6);
            label(x,y,496,408,7,adc_online ? joystick_text : "-.--- V",24'hF1F1FA);
            label(x,y,28,456,31,"LAST ERROR STAYS AFTER RECOVERY",24'hF2BE55);
            label(x,y,28,480,37,"FAIL COUNTS FAILED REQUESTS / MAX 255",24'h9CAEC9);
            label(x,y,28,520,27,"LEVEL 1 DOES NOT PROVE 3.3V",24'h9CAEC9);
            label(x,y,28,552,33,"REPORT ALL THREE ROWS WHEN FAILED",24'hCAD4E6);
        end else begin
        label(x,y,28,24,28,"TANG MEGA / POLYPHONIC SYNTH",24'hF1F1FA);
        label(x,y,28,44,20,{"32 VOICES / OCTAVE ",octave_digit},24'h9CAEC9);
        case(timbre)
            0:label(x,y,416,24,9,"TONE SINE",24'hC8BCFF);
            1:label(x,y,416,24,11,"TONE EPIANO",24'hC8BCFF);
            2:label(x,y,416,24,12,"TONE STRINGS",24'hC8BCFF);
            3:label(x,y,416,24,10,"TONE METAL",24'hC8BCFF);
            4:label(x,y,416,24,10,"TONE FLUTE",24'hC8BCFF);
            5:label(x,y,416,24,10,"TONE ORGAN",24'hC8BCFF);
            6:label(x,y,416,24,10,"TONE PLUCK",24'hC8BCFF);
            7:label(x,y,416,24,9,"TONE BASS",24'hC8BCFF);
        endcase
        label(x,y,416,44,9,"48.8K I2S",24'h9CAEC9);
        if(ENABLE_EXPRESSION) label(x,y,640,24,10,"EXPR M3 8T",24'hC8BCFF);
        label(x,y,640,44,lamp_test ? 8 : test_on ? 11 : 10,lamp_test ? "LED TEST" : test_on ? "8 SINE TEST" : TOUCH_DEBUG ? "SUST DEBUG" : guide_on ? (display_performance[4] ? "DONE      " : display_performance[6] ? "REST      " : display_performance[5] ? "HOLD      " : "NEXT NOTE ") : "LIVE INPUT",24'hC8BCFF);
        for(key_label=0;key_label<8;key_label=key_label+1)
            label(x,y,48+64*key_label,146,2,white_note(key_label,octave_digit),24'h142137);
        for(sharp_label=0;sharp_label<5;sharp_label=sharp_label+1)
            label(x,y,74+64*(sharp_label<2 ? sharp_label : sharp_label+1),102,3,sharp_note(sharp_label,octave_digit),24'hF1F1FA);
        label(x,y,28,204,12,"DIGITAL WAVE",24'hC8BCFF);
        label(x,y,ENABLE_EXPRESSION ? 256 : 508,204,2,ENABLE_EXPRESSION ? "3X" : "1X",24'h9CAEC9);
        if(ENABLE_EXPRESSION) begin
            label(x,y,28,224,13,"PCM / 10.49MS",24'hCAD4E6);
            label(x,y,340,204,9,"LISSAJOUS",24'hC8BCFF);
            label(x,y,508,204,2,"3X",24'h9CAEC9);
            label(x,y,340,224,11,"XY / 0.66MS",24'hCAD4E6);
        end else label(x,y,28,224,25,"I2S OUT / 10.49 MS / TRIG",24'h9CAEC9);
        if(ENABLE_EXPRESSION) begin
            label(x,y,28,408,9,"METRONOME",24'hC8BCFF);
            label(x,y,208,408,3,metro_enabled ? "ON " : "OFF",metro_enabled ? 24'h48E0C0 : 24'h9CAEC9);
            label(x>>1,y>>1,14,218,3,metro_bpm_text,24'hF1F1FA);
            label(x,y,112,444,3,"BPM",24'h9CAEC9);
            label(x,y,208,444,3,meter_text,24'hF1F1FA);
            label(x,y,28,474,8,metro_meter==0 ? "1/2 NOTE" : metro_meter==4 ? "DOT 1/4 " : "1/4 NOTE",24'h9CAEC9);
            label(x,y,208,474,3,{digit({29'd0,metro_beat}+1),"/",digit({29'd0,metro_beats})},24'hCAD4E6);
            label(x,y,28,530,17,"X0+C0 METER C3 ON",24'h9CAEC9);
            label(x,y,284,408,8,"SPECTRUM",24'hC8BCFF);
            label(x,y,284,436,11,"4096 / HANN",24'h9CAEC9);
            label(x,y,284,520,1,"0",24'h9CAEC9);
            label(x,y,400,520,2,"3K",24'h9CAEC9);
            label(x,y,516,520,2,"6K",24'h9CAEC9);
        end else begin
            label(x,y,28,408,8,"SPECTRUM",24'hC8BCFF);
            label(x,y,396,408,11,"4096 / HANN",24'h9CAEC9);
            label(x,y,28,532,1,"0",24'h9CAEC9);
            label(x,y,140,532,4,"1.5K",24'h9CAEC9);
            label(x,y,272,532,2,"3K",24'h9CAEC9);
            label(x,y,396,532,4,"4.5K",24'h9CAEC9);
            label(x,y,516,532,2,"6K",24'h9CAEC9);
        end
        label(x,y,576,88,online ? 12 : 13,online ? "TOUCH ONLINE" : "TOUCH OFFLINE",online ? 24'h48E0C0 : 24'hFFA3A8);
        label(x,y,576,112,14,{"VOICES ",voice_text," / 32"},24'hF1F1FA);
        label(x,y,576,140,8,"PRESSURE",24'hC8BCFF);
        label(x,y,576,160,7,adc_online ? pressure_text : "-.--- V",24'hF1F1FA);
        label(x,y,adc_online ? 696 : 684,160,adc_online ? 6 : 7,adc_online ? "ADC OK" : "ADC OFF",adc_online ? 24'h48E0C0 : 24'hFFA3A8);
        label(x,y,576,244,11,"MASTER GAIN",24'hC8BCFF);
        label(x,y,720,244,4,{volume_text,"%"},24'hF1F1FA);
        if(ENABLE_EXPRESSION) begin
            case(display_performance[3:2])
                0:label(x,y,576,296,6,"FX OFF",24'hF1F1FA);
                1:label(x,y,576,296,8,"FX DELAY",24'hF1F1FA);
                2:label(x,y,576,296,9,"FX REVERB",24'hF1F1FA);
                3:label(x,y,576,296,9,"FX CHORUS",24'hF1F1FA);
            endcase
        end else label(x,y,576,296,echo_on ? 7 : 8,echo_on ? "ECHO ON" : "ECHO OFF",24'hF1F1FA);
        label(x,y,576,320,vibrato ? 6 : 7,vibrato ? "VIB ON" : "VIB OFF",24'hF1F1FA);
        if(ENABLE_EXPRESSION) label(x,y,576,356,10,!display_performance[0] ? "Y BEND OFF" : display_performance[1] ? "Y BEND ON " : "Y CENTER  ",24'h9CAEC9);
        else label(x,y,576,356,11,"PRE-SPEAKER",24'h9CAEC9);
        // Soft-knee activity is normal at solo attacks; it is not a fault badge.
        // The audio limiter and its internal telemetry remain intact.
        if(touch_fault_visible) begin
            // These are the live playing-image controllers, not a silent test.
            // E/F are sticky fault/count; S/D are the last settled idle levels.
            label(x,y,576,408,10,"TOUCH LINK",24'hF2BE55);
            label(x,y,576,432,10,{"A",digit(display_status[50])," E",digit({28'd0,display_wiring[3:0]})," F",decimal3({24'd0,display_wiring[11:4]})},24'hF1F1FA);
            label(x,y,576,452,14,{fault_name(display_wiring[3:0])," S",idle_digit(display_wiring[14],display_wiring[13])," D",idle_digit(display_wiring[14],display_wiring[12])},24'hCAD4E6);
            label(x,y,576,480,10,{"B",digit(display_status[51])," E",digit({28'd0,display_wiring[19:16]})," F",decimal3({24'd0,display_wiring[27:20]})},24'hF1F1FA);
            label(x,y,576,500,14,{fault_name(display_wiring[19:16])," S",idle_digit(display_wiring[30],display_wiring[29])," D",idle_digit(display_wiring[30],display_wiring[28])},24'hCAD4E6);
            label(x,y,576,524,10,"AUTO RETRY",24'h9CAEC9);
        end else if(diagnostics_visible) begin
            label(x,y,576,408,10,"UART DEBUG",24'hC8BCFF);
            label(x,y,576,432,11,{"BY",decimal3(uart_bytes)," FR",decimal3(uart_frames)},24'hF1F1FA);
            label(x,y,576,452,11,{"RX",rx_text," ER",error_text},24'hF1F1FA);
            label(x,y,576,472,8,{"A",digit(display_status[50])," B",digit(display_status[51])," X",digit(display_status[52])},24'hF1F1FA);
            label(x,y,576,496,14,{"D0 ",trace_hex(0,uart_first_bytes,uart_capture_count)," ",trace_hex(1,uart_first_bytes,uart_capture_count)," ",trace_hex(2,uart_first_bytes,uart_capture_count)," ",trace_hex(3,uart_first_bytes,uart_capture_count)},24'hF1F1FA);
            label(x,y,576,520,14,{"D4 ",trace_hex(4,uart_first_bytes,uart_capture_count)," ",trace_hex(5,uart_first_bytes,uart_capture_count)," ",trace_hex(6,uart_first_bytes,uart_capture_count)," ",trace_hex(7,uart_first_bytes,uart_capture_count)},24'hF1F1FA);
        end else begin
            label(x,y,576,408,guide_on ? 8 : 9,guide_on ? "GUIDE ON" : "GUIDE OFF",24'hC8BCFF);
            label(x,y,576,432,custom_score ? 9 : 7,custom_score ? "SONG USER" : "YU JIAN",24'hF1F1FA);
            label(x,y,576,452,12,{"STEP ",step_text,"/",length_text},24'hF1F1FA);
            label(x,y,576,476,7,{"BPM ",bpm_text},24'hF1F1FA);
            label(x,y,576,500,lamp_test ? 8 : test_on ? 11 : 10,lamp_test ? "LED TEST" : test_on ? "8 SINE TEST" : TOUCH_DEBUG ? "SUST DEBUG" : guide_on ? (display_performance[4] ? "DONE      " : display_performance[6] ? "REST      " : display_performance[5] ? "HOLD      " : "NEXT NOTE ") : "LIVE INPUT",24'h9CAEC9);
            label(x,y,576,524,13,{"RX ",rx_text," ER ",error_text},24'h9CAEC9);
        end
        if(ENABLE_JOYSTICK) begin
            // Same 60 cells, split into short labels to bound the glyph mux.
            label(x,y,28,568,18,{"EC11 ",display_sustain[5] ? "ON " : "OFF"," L",decimal2({27'd0,display_sustain[4:0]}),"/16 | "},24'hCAD4E6);
            label(x,y,244,568,16,"STICK L/R OCT | ",24'hCAD4E6);
            if(ENABLE_EXPRESSION) begin
                label(x,y,436,568,12,"C3/SW VIB | ",24'hCAD4E6);
                label(x,y,580,568,14,"X0+C1/2 TEMPO ",24'hCAD4E6);
            end else label(x,y,436,568,26,"HOLD SW/C3 VIB | RECENTER ",24'hCAD4E6);
        end
        else if(ENABLE_EC11)
            label(x,y,28,568,40,{"EC11 SUST ",display_sustain[5] ? "ON " : "OFF"," L",decimal2({27'd0,display_sustain[4:0]}),"/16  TURN / PUSH TOGGLE"},24'hCAD4E6);
        else if(TOUCH_DEBUG)
            label(x,y,28,568,36,"DEFAULT SUSTAIN  UART H0 OFF / H1 ON",24'hCAD4E6);
        else label(x,y,28,568,58,"C0 TONE/ECHO C1/2 GAIN C3 VIB C1+C2 GUIDE X0+C0..3 OCT3..6",24'hCAD4E6);
        end
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
            glass[23:16]=(background[23:16]>>2)+(background[23:16]>>3)+8'd8;
            glass[15:8]=(background[15:8]>>2)+(background[15:8]>>3)+8'd10;
            glass[7:0]=(background[7:0]>>2)+(background[7:0]>>3)+8'd18;
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
        rounded(px,16,552,py,192,384) || (ENABLE_EXPRESSION ? (rounded(px,16,264,py,396,552) || rounded(px,272,552,py,396,552)) : rounded(px,16,552,py,396,552)) ||
        rounded(px,564,784,py,76,220) || rounded(px,564,784,py,232,384) ||
        rounded(px,564,784,py,396,552) || rounded(px,16,784,py,564,588);
    wire panel_inner=rounded(px,17,783,py,13,67) || rounded(px,17,551,py,77,179) ||
        rounded(px,17,551,py,193,383) || (ENABLE_EXPRESSION ? (rounded(px,17,263,py,397,551) || rounded(px,273,551,py,397,551)) : rounded(px,17,551,py,397,551)) ||
        rounded(px,565,783,py,77,219) || rounded(px,565,783,py,233,383) ||
        rounded(px,565,783,py,397,551) || rounded(px,17,783,py,565,587);
    wire [23:0] glass_rgb=glass(wallpaper_rgb);
    wire [23:0] bar_rgb=ENABLE_EXPRESSION ? 24'hBCA9F5 : spectrum_colour(key_offset[8:0]);
    wire [23:0] bar_shade={1'b0,bar_rgb[23:17],1'b0,bar_rgb[15:9],1'b0,bar_rgb[7:1]};
    wire [7:0] fft_height=ENABLE_EXPRESSION ? plot_data>>2 : plot_data>>1;
    wire [10:0] fft_offset=px-(ENABLE_EXPRESSION ? 284 : 28);
    wire [9:0] fft_bottom=ENABLE_EXPRESSION ? 507 : 523;
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
        if(panel && !panel_inner) color=24'h737087;
        if(px>=28 && px<540 && py>=88 && py<168 && key_offset[5:0]<62) begin
            color=gates[key_index] ? 24'h91B9E4 :
                (guide_on && guide_mask[key_index]) ? 24'h48E0A0 :
                active[key_index] ? {8'h91,8'hB9,tail_blue} : 24'hCDD5E5;
            // The meter is the voice ADSR before pressure/master gain and echo.
            if(!(guide_on && guide_mask[key_index]) && py>=160 && py<164 && key_offset[5:0]>=3 && key_offset[5:0]<59)
                color=key_offset[5:0]-3<key_meter[13:8] ? 24'h249C8B : 24'hAAB6CA;
        end
        for(sharp=0;sharp<5;sharp=sharp+1) begin
            sharp_level=display_levels>>((8+sharp)*8);
            sharp_meter=sharp_level*6'd36;
            if(py>=88 && py<134 && px>=(sharp<2 ? 70+64*sharp : 134+64*sharp) &&
                px<(sharp<2 ? 114+64*sharp : 178+64*sharp)) begin
                color=gates[8+sharp] ? 24'h91B9E4 :
                    (guide_on && guide_mask[8+sharp]) ? 24'h48E0A0 :
                    active[8+sharp] ? {8'h32,8'h4C,(8'd80+{1'b0,sharp_level[7:1]})} : 24'h202A41;
                if(!(guide_on && guide_mask[8+sharp]) && py>=124 && py<128 && px>=(sharp<2 ? 74+64*sharp : 138+64*sharp) &&
                    px<(sharp<2 ? 110+64*sharp : 174+64*sharp))
                    color=px-(sharp<2 ? 74+64*sharp : 138+64*sharp)<sharp_meter[13:8] ? 24'h48E0C0 : 24'h29384F;
            end
        end
        if(px>=28 && px<(ENABLE_EXPRESSION ? 284 : 540) && py>=244 && py<=372) begin
            if((py==276 || py==308 || py==340 || key_offset[6:0]==0) && px[1:0]==0) color=24'h3B485F;
            if(scope_plot_ready && $signed({1'b0,py})>=trace_low-2 && $signed({1'b0,py})<=trace_high+2) color=24'h287577;
            if(scope_plot_ready && $signed({1'b0,py})>=trace_low-1 && $signed({1'b0,py})<=trace_high+1) color=24'h48E0C0;
        end
        if(ENABLE_EXPRESSION && px>=360 && px<488 && py>=244 && py<372) begin
            if((px==424 || py==308) && px[1:0]==0) color=24'h646779;
            if(liss_plot_ready && liss_plot) color=24'h48E0C0;
        end
        if(px>=(ENABLE_EXPRESSION ? 284 : 28) && px<540 && py>=(ENABLE_EXPRESSION ? 464 : 436) && py<=fft_bottom) begin
            if(((ENABLE_EXPRESSION ? fft_offset[5:0]==0 : fft_offset[6:0]==0) || py==fft_bottom) && px[1:0]==0) color=24'h3B485F;
            if(plot_ready && py>=fft_bottom-fft_height && fft_height!=0) begin
                color=py[2:0]==5 ? bar_shade : bar_rgb;
                if(py<=fft_bottom+1-fft_height) color=24'hF4EFFF;
            end
        end
        if(ENABLE_EXPRESSION) for(dot=0;dot<6;dot=dot+1) begin
            if(dot<metro_beats && px>=28+36*dot && px<52+36*dot && py>=502 && py<514) begin
                color=24'h384259;
                if(metro_enabled && metro_flash && metro_beat==dot)
                    color=dot==0 ? 24'hFFD27B : display_metronome[1:0]==1 ? 24'hC8BCFF : 24'h48E0C0;
            end
        end
        if(px>=576 && px<768 && py>=188 && py<196)
            color=(adc_online && px<576+pressure_width) ? 24'h48E0C0 : 24'h25364B;
        if(px>=576 && px<768 && py>=272 && py<280)
            color=px<576+volume_bar_product[20:12] ? 24'hC8BCFF : 24'h25364B;
        if(!touch_fault_visible && !diagnostics_visible && guide_on && display_status[38] && px>=752 && px<764 && py>=476 && py<488)
            color=24'hF2BE55;
        if(text_pixel && panel_inner) color=glyph_ink;
        if(TOUCH_ISOLATION) begin
            color=24'h0B1220;
            if(px>=20 && px<776 && py>=136 && py<434) color=24'h182237;
            if(text_pixel) color=glyph_ink;
        end else if(WIRING_DEBUG) begin
            color=24'h0B1220;
            if(px>=24 && px<776 && ((py>=76 && py<172) || (py>=184 && py<280) || (py>=292 && py<388)))
                color=24'h182237;
            if(text_pixel) color=glyph_ink;
        end
    end
    always @(posedge clk) begin
        px0<=x;py0<=y;de0<=de;hs0<=hs;vs0<=vs;ready0<=visual_ready;
        px<=px0;py<=py0;de_delay<=de0;hs_delay<=hs0;vs_delay<=vs0;
        plot_data<=visual_data;plot_ready<=ready0;
        scope_plot<=scope_data;scope_ready0<=scope_ready;scope_plot_ready<=scope_ready0;
        liss_plot<=liss_data;liss_ready0<=liss_ready;liss_plot_ready<=liss_ready0;
        label_visible<=text_visible;label_dx<=text_dx;label_dy<=text_dy;
        label_length<=text_length;label_line<=text_line;label_ink<=text_ink;
        text_pixel<=next_text_pixel;character<=next_character;glyph_ink<=label_ink;
        if(rst) begin
            display_isolation<=0;
            for(isolation_format=0;isolation_format<7;isolation_format=isolation_format+1) begin
                isolation_a_text[isolation_format]<=0;isolation_b_text[isolation_format]<=0;
            end
            display_wiring<=0;joystick_text<="0.000 V";
            display_status<=0;display_sustain<=0;display_levels<=0;rgb<=0;out_de<=0;out_hs<=0;out_vs<=0;
            display_octave<=2'd1;display_performance<=0;display_metronome<={8'd120,3'd3,7'd0};metro_bpm_text<="120";
            scope_plot<=0;previous_scope<=0;scope_ready0<=0;scope_plot_ready<=0;
            liss_plot<=0;liss_ready0<=0;liss_plot_ready<=0;
            de0<=0;de_delay<=0;hs0<=0;hs_delay<=0;vs0<=0;vs_delay<=0;
            ready0<=0;plot_ready<=0;
            label_visible<=0;text_pixel<=0;character<=32;glyph_ink<=0;
            pressure_text<="0.000 V";volume_text<="000";bpm_text<="000";
            rx_text<="000";error_text<="000";voice_text<="00";step_text<="01";length_text<="00";
        end else begin
            if(de_delay && px>=28 && px<(ENABLE_EXPRESSION ? 284 : 540) && py>=244 && py<=372) previous_scope<=scope_plot;
            if(vertical_blank) begin
                display_isolation<=isolation_status;
                if(TOUCH_ISOLATION) for(isolation_format=0;isolation_format<7;isolation_format=isolation_format+1) begin
                    isolation_a_text[isolation_format]<={"F",decimal3({24'd0,isolation_status[isolation_format*32 +: 8]}),
                        " E",hex_character(isolation_status[isolation_format*32+16 +: 4]),
                        " U",isolation_status[isolation_format*32+26] ? "1" : "0"," D",isolation_status[isolation_format*32+24] ? "1" : "0"};
                    isolation_b_text[isolation_format]<={"F",decimal3({24'd0,isolation_status[isolation_format*32+8 +: 8]}),
                        " E",hex_character(isolation_status[isolation_format*32+20 +: 4]),
                        " U",isolation_status[isolation_format*32+27] ? "1" : "0"," D",isolation_status[isolation_format*32+25] ? "1" : "0"};
                end
                display_wiring<=wiring_status;
                joystick_text<={digit(wiring_status[59:48]/1000),".",decimal3(wiring_status[59:48]%1000)," V"};
                display_status<=status;display_sustain<=sustain_info;
                display_levels<=voice_levels;
                display_octave<=octave_select;display_performance<=performance_info;
                display_metronome<=metronome_info;metro_bpm_text<=decimal3(metronome_info[17:10]);
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
