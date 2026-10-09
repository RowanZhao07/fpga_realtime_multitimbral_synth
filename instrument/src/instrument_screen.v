`timescale 1ns/1ps
// Streaming raster renderer: no external memory or processor.
module instrument_screen(input wire clk,rst,input wire [10:0] x,input wire [9:0] y,
    input wire de,hs,vs,vertical_blank,input wire [39:0] status,
    input wire [63:0] voice_levels,
    input wire scope_ready,input wire [7:0] scope_data,output wire [8:0] scope_address,
    input wire visual_ready,input wire [7:0] visual_data,
    output wire [9:0] visual_address,
    output reg [23:0] rgb=0,output reg out_de=0,out_hs=0,out_vs=0);
    reg [10:0] px=0; reg [9:0] py=0;
    reg de_delay=0,hs_delay=0,vs_delay=0;
    reg [39:0] display_status=0;
    reg [63:0] display_levels=0;
    reg signed [7:0] previous_scope=0;
    wire [7:0] gates=display_status[7:0],active=display_status[15:8];
    wire [1:0] timbre=display_status[17:16];
    wire [4:0] volume=display_status[22:18];
    wire online=display_status[23],vibrato=display_status[24],echo_on=display_status[25];
    wire test_on=display_status[26],guide_on=display_status[27];
    wire [2:0] target=display_status[30:28];
    wire [5:0] position=display_status[36:31];
    wire [10:0] plot_x=x-11'd32;
    assign visual_address={y>=400,plot_x[8:0]};
    assign scope_address=plot_x[8:0];
    wire [5:0] col=px[9:4],row=py[9:4];
    reg [8*50-1:0] text_line;
    reg [7:0] character;
    wire [4:0] glyph;
    font_lut font(.character(character),.row(py[3:1]),.pixels(glyph));
    reg [3:0] voice_count;
    integer k;
    always @* begin
        voice_count=0;
        for(k=0;k<8;k=k+1) voice_count=voice_count+active[k];
        text_line="                                                  ";
        case(row)
        1:text_line="  TANG MEGA / REALTIME INSTRUMENT                 ";
        3:case(timbre)
          0:text_line="  TONE: SINE        8 VOICES / PURE HDL           ";
          1:text_line="  TONE: SQUARE      8 VOICES / PURE HDL           ";
          2:text_line="  TONE: SAW         8 VOICES / PURE HDL           ";
          3:text_line="  TONE: METAL       8 VOICES / PURE HDL           ";
          endcase
        6:text_line="   C4  D4  E4  F4  G4  A4  B4  C5                 ";
        8:text_line="   K0  K1  K2  K3  K4  K5  K6  K7                 ";
        10:text_line="  WAVE / 10.49 MS / TRIG                          ";
        12:text_line="                                   TOUCH          ";
        13:text_line=online ? "                                   ONLINE         " : "                                   OFFLINE        ";
        15:text_line="                                   VOICES:        ";
        18:text_line="                                   VOLUME         ";
        21:text_line=echo_on ? "                                   ECHO ON        " : "                                   ECHO OFF       ";
        23:text_line=vibrato ? "                                   VIB ON         " : "                                   VIB OFF        ";
        24:text_line="  FFT 4096 / HANN / LOG MAGNITUDE                 ";
        26:text_line=guide_on ? "                                   GUIDE ON       " : "                                   GUIDE OFF      ";
        28:text_line="                                   NEXT: K        ";
        30:text_line="                                   STEP:          ";
        32:text_line=test_on ? "                                   8 SINE TEST    " : "                                   LIVE INPUT     ";
        34:text_line="                                   BPM 120        ";
        35:text_line="  0      1.5K    3K      4.5K    6KHZ             ";
        36:text_line="  C0 TONE/ECHO   C1/2 VOL   C3 VIB                ";
        9:text_line="  HELD: GREEN  TAIL: BLUE  NEXT: GOLD             ";
        endcase
        character=col<50 ? (text_line >> ((49-col)*8)) : 8'd32;
        if(row==15 && col==43) character=8'd48+voice_count;
        if(row==28 && col==42) character=8'd48+target;
        if(row==30 && col==41) character=8'd48+(position+1)/10;
        if(row==30 && col==42) character=8'd48+(position+1)%10;
    end
    reg [23:0] color;
    reg signed [11:0] wave_y,previous_y,trace_low,trace_high;
    wire [10:0] key_offset=px-11'd32;
    wire [2:0] key_index=key_offset[8:6];
    wire [7:0] key_level=display_levels>>(key_index*8);
    wire [7:0] tail_blue=8'd55+{1'b0,key_level[7:1]};
    always @* begin
        color=24'h0B1220;
        wave_y=12'sd270-$signed(scope_data);
        previous_y=key_offset==0 ? wave_y : 12'sd270-$signed(previous_scope);
        trace_low=wave_y<previous_y ? wave_y : previous_y;
        trace_high=wave_y>previous_y ? wave_y : previous_y;
        if(py<72) color=24'h14263D;
        if(px>=32 && px<544 && py>=88 && py<122) begin
            color=gates[key_index] ? 24'h20A890 :
                active[key_index] ? {8'h20,8'h48,tail_blue} : 24'h25374B;
            // Envelope meter: one per key, uses actual ADSR level, not a timer.
            if(py>=114 && py<118 && key_offset[5:0]>=4 && key_offset[5:0]<60)
                color=key_offset[5:0]-4 < (key_level>>2) ? 24'h48E0C0 : 24'h14263D;
            if(guide_on && target==key_index && (py<92 || py>=118)) color=24'hF2BE55;
            if(key_offset[5:0]<2 || key_offset[5:0]>=62) color=24'h0B1220;
        end
        if(px>=32 && px<544 && py>=176 && py<372) begin
            color=24'h111F30;
            if(py==270 || px[6:0]==32) color=24'h25364B;
            if(scope_ready && $signed({1'b0,py})>=trace_low-1 && $signed({1'b0,py})<=trace_high+1) color=24'h48E0C0;
        end
        if(px>=32 && px<544 && py>=410 && py<550) begin
            color=24'h111F30;
            if(px[6:0]==32 || py==549) color=24'h25364B;
            if(visual_ready && py>=549-visual_data && visual_data!=0) color=24'h6FA8F4;
        end
        if(px>=560 && px<768 && py>=316 && py<328) begin
            color=px<560+volume*13 ? 24'hE2B759 : 24'h25364B;
        end
        if(guide_on && display_status[38] && px>=760 && px<776 && py>=544 && py<558) color=24'hF2BE55;
        if(px[3:1]<5 && glyph[4-px[3:1]]) color=24'hE1EBF5;
    end
    always @(posedge clk) begin
        px<=x; py<=y; de_delay<=de; hs_delay<=hs; vs_delay<=vs;
        if(rst) begin display_status<=0; display_levels<=0; previous_scope<=0; rgb<=0; out_de<=0; out_hs<=0; out_vs<=0; end
        else begin
            if(vertical_blank) begin display_status<=status; display_levels<=voice_levels; end
            if(de_delay && px>=32 && px<544) previous_scope<=scope_data;
            rgb<=de_delay ? color : 24'd0;
            out_de<=de_delay; out_hs<=hs_delay; out_vs<=vs_delay;
        end
    end
endmodule
