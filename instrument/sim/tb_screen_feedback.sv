`timescale 1ns/1ps
// Sparse pixel probes still use the real RAM and three-clock raster pipeline.
module tb_screen_feedback;
    GSR GSR(.GSRI(1'b1));
    reg clk=0;always #12.5 clk=~clk;
    reg rst=1,blank=0;reg [10:0] x=0;reg [9:0] y=0;
    reg [203:0] status=0;reg [103:0] levels=0;
    reg [1:0] octave_select=1;
    reg [31:0] performance={6'd13,10'd76,9'd4,7'd0};
    reg [7:0] scope=0,source=0;wire [23:0] rgb;
    always @(posedge clk) scope<=source;
    instrument_screen dut(.sustain_info(6'd0),.clk(clk),.rst(rst),.x(x),.y(y),.de(1'b1),.hs(1'b0),.vs(1'b0),
        .vertical_blank(blank),.status(status),.performance_info(performance),.voice_levels(levels),.octave_select(octave_select),
        .scope_ready(1'b1),.scope_data(scope),.scope_address(),
        .visual_ready(1'b0),.visual_data(8'd0),.visual_address(),
        .rgb(rgb),.out_de(),.out_hs(),.out_vs());
    task latch;
        begin @(negedge clk);blank=1;@(negedge clk);blank=0;end
    endtask
    task character_at(input integer xx,yy,input [7:0] expected);
        begin @(negedge clk);x=xx;y=yy;repeat(4) @(negedge clk);
            if(dut.character!==expected) $fatal(1,"HUD label %0d,%0d got %s expected %s",xx,yy,dut.character,expected);
        end
    endtask
    task pixel(input integer xx,yy,input [23:0] expected);
        begin @(negedge clk);x=xx;y=yy;repeat(4) @(negedge clk);
            if(rgb!==expected) $fatal(1,"Pixel %0d,%0d got %h expected %h",xx,yy,rgb,expected);
        end
    endtask
    integer k,left,oct;
    initial begin
        repeat(4) @(negedge clk);rst=0;
        // All thirteen independently addressable held keys, including all sharps.
        status[7:0]=8'hff;status[44:40]=5'h1f;
        status[15:8]=8'hff;status[49:45]=5'h1f;levels={13{8'd200}};latch;
        for(k=0;k<8;k=k+1) pixel(32+k*64,140,24'h91B9E4);
        for(k=0;k<5;k=k+1) pixel(74+64*(k<2 ? k : k+1),120,24'h91B9E4);
        // Keep held C4, release D4 and the last sharp only; other keys idle.
        status[7:0]=1;status[44:40]=0;status[15:8]=3;status[49:45]=5'b10000;latch;
        pixel(32,140,24'h91B9E4);pixel(96,140,24'h91B9E4);
        pixel(160,140,24'hCDD5E5);pixel(394,120,24'h324CB4);
        pixel(137,162,24'h249C8B);pixel(138,162,24'hAAB6CA);
        pixel(420,126,24'h48E0C0);pixel(428,126,24'h29384F);
        // Envelope changes must latch at vertical blank, never mid-frame.
        levels[15:8]=20;levels[103:96]=20;
        pixel(96,140,24'h91B9E4);pixel(394,120,24'h324CB4);latch;
        pixel(96,140,24'h91B98A);pixel(394,120,24'h324C5A);
        pixel(138,162,24'hAAB6CA);pixel(420,126,24'h29384F);
        status[15:8]=1;status[49:45]=0;latch;
        pixel(96,140,24'hCDD5E5);pixel(394,120,24'h202A41);
        status[27]=1;status[78:66]=13'h1002;latch;
        pixel(100,166,24'h48E0A0);pixel(100,140,24'h48E0A0);pixel(100,162,24'h48E0A0);
        pixel(398,90,24'h48E0A0);pixel(398,120,24'h48E0A0);pixel(398,126,24'h48E0A0);
        status[7:0]=2;status[44:40]=5'b10000;latch;
        pixel(100,140,24'h91B9E4);pixel(398,120,24'h91B9E4); // press wins over target
        status[7:0]=0;status[44:40]=0;latch;
        pixel(100,140,24'h48E0A0);pixel(398,120,24'h48E0A0); // release restores target
        performance[4]=1;latch;character_at(576,500,"D");character_at(640,44,"D");
        performance[4]=0;
        source=8'h7f;pixel(40,245,24'h48E0C0);
        source=8'h80;pixel(40,372,24'h48E0C0);
        // Opposite-sign consecutive samples must have a continuous bridge.
        @(negedge clk);source=8'h7f;x=40;y=300;repeat(4) @(negedge clk);
        x=41;source=8'h80;repeat(3) @(negedge clk);
        if(rgb!==24'h48E0C0) $fatal(1,"Opposite-sign adjacent trace is disconnected");
        // A new scanline must not connect its first point to the previous row.
        @(negedge clk);x=28;y=340;source=0;repeat(3) @(negedge clk);
        if(rgb===24'h48E0C0) $fatal(1,"Trace bridges across scanline boundary");
        // The normal guide card stays available through disconnect/reconnect.
        status=0;status[51]=1;status[86:79]=120;status[93:87]=14;latch;
        character_at(576,408,"G");character_at(660,408,"F");
        character_at(576,432,"Y");character_at(636,432,"A");
        character_at(636,452,"0");character_at(708,452,"6");
        character_at(624,476,"1");character_at(648,476,"0");
        character_at(576,500,"L");character_at(576,524,"R");
        status[23]=1;status[50]=1;latch;
        character_at(576,408,"G");
        status[27]=1;status[38]=1;latch;
        character_at(660,408,"N");pixel(754,480,24'hF2BE55);
        status[195]=1;latch;character_at(576,408,"U"); // Explicit D1 UART page.
        status[23]=0;latch;character_at(576,408,"U");
        status[195]=0;latch;character_at(576,408,"G"); // D0 restores guide.
        // Every note label and header must share a vertical-blank octave snapshot.
        for(oct=0;oct<4;oct=oct+1) begin
            octave_select=oct;
            character_at(60,146,8'd51+dut.display_octave);
            latch;
            character_at(256,44,8'd51+oct);
            for(k=0;k<8;k=k+1) character_at(60+64*k,146,8'd51+oct+(k==7));
            for(k=0;k<5;k=k+1) character_at(98+64*(k<2 ? k : k+1),102,8'd51+oct);
            character_at(576,408,"G");character_at(660,408,"N");
        end
        $display("PASS: octaves 3/4/5/6, all 13 note names, C7 endpoint and coherent frame snapshot");
        $display("PASS: guide/song/step/BPM/input/RX card, guide beat and manual UART page across disconnect/reconnect");
        $display("PASS: 13 held keys, white/sharp tails and scaled meters, frame latch, guide priority, fixed zoom, connected trace and row boundary");
        $display("ALL TESTS PASSED");$finish;
    end
    initial begin #100000;$fatal(1,"Screen-feedback watchdog");end
endmodule
