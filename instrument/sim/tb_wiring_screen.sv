`timescale 1ns/1ps
module tb_wiring_screen;
    GSR GSR(.GSRI(1'b1));
    reg clk=0;always #12.5 clk=~clk;
    reg rst=1,blank=0,de=1;reg [10:0] x=0;reg [9:0] y=0;
    reg [203:0] status=0;reg [59:0] wiring=0;
    wire [23:0] rgb;wire od,oh,ov;
    instrument_screen #(.WIRING_DEBUG(1),.ENABLE_JOYSTICK(1)) dut(
        .wiring_status(wiring),.sustain_info(6'd0),.clk(clk),.rst(rst),.x(x),.y(y),.de(de),.hs(1'b0),.vs(1'b0),
        .vertical_blank(blank),.status(status),.performance_info(32'd0),.voice_levels(104'd0),.octave_select(2'd1),
        .scope_ready(1'b0),.scope_data(8'd0),.scope_address(),.visual_ready(1'b0),.visual_data(8'd0),.visual_address(),
        .rgb(rgb),.out_de(od),.out_hs(oh),.out_vs(ov));
    reg [2:0] de_pipe=0;
    always @(posedge clk) de_pipe<={de_pipe[1:0],de};
    task latch;
        @(negedge clk);blank=1;@(negedge clk);blank=0;
    endtask
    task text_at(input integer xx,yy,input string expected);
        for(integer i=0;i<expected.len();i=i+1)begin
            @(negedge clk);x=xx+i*12;y=yy;repeat(4)@(negedge clk);
            if(dut.character!==expected.getc(i))$fatal(1,"Text %0d,%0d[%0d] got %s expected %s",xx,yy,i,dut.character,expected.getc(i));
        end
    endtask
    integer f,xx,yy,pixels=0;
    initial begin
        repeat(5)@(negedge clk);rst=0;latch;
        text_at(148,116,"-");text_at(328,116,"-");
        // Mixed independent states. B has recovered but retains a past fault.
        status[51]=1;
        wiring={12'd1650,16'h6053,16'h7042,16'h7031};latch;
        text_at(28,24,"WIRING CHECK / GPIO V1");
        text_at(656,24,"SILENT");
        text_at(40,88,"TOUCH A 0X5A");text_at(656,88,"OFFLINE");
        text_at(40,116,"SCL E14");text_at(148,116,"1");text_at(220,116,"SDA E13");text_at(328,116,"1");
        text_at(40,140,"LAST E1");text_at(148,140,"NO ACK  ");text_at(360,140,"FAIL 003");
        text_at(40,196,"TOUCH B 0X5A");text_at(656,196,"ONLINE ");
        text_at(40,224,"SCL A16");text_at(220,224,"SDA A15");
        text_at(40,248,"LAST E2");text_at(148,248,"SCL LOW ");text_at(360,248,"FAIL 004");
        text_at(40,304,"ADC     0X48");text_at(656,304,"OFFLINE");
        text_at(40,332,"SCL A20");text_at(148,332,"1");text_at(220,332,"SDA B20");text_at(328,332,"0");
        text_at(40,356,"LAST E3");text_at(148,356,"SDA BUS ");text_at(360,356,"FAIL 005");
        text_at(160,408,"-.--- V");text_at(496,408,"-.--- V");
        // No tearing: changed input is invisible before the next blank.
        wiring[47:32]=16'h7FF7;status[65]=1;status[64:53]=3235;
        text_at(40,356,"LAST E3");text_at(656,304,"OFFLINE");latch;
        text_at(656,304,"ONLINE ");text_at(40,356,"LAST E7");
        text_at(148,356,"NOT RDY ");text_at(360,356,"FAIL 255");
        text_at(160,408,"3.235 V");text_at(496,408,"1.650 V");
        // Screenshot is a labelled synthetic fixture, not a hardware diagnosis.
        status[65]=0;wiring[47:32]=16'h6053;latch;
        @(negedge clk);de=0;repeat(5)@(negedge clk);
        f=$fopen("output/wiring_debug_fixture.ppm","wb");
        $fwrite(f,"P6\n800 600\n255\n");
        for(yy=0;yy<600;yy=yy+1) for(xx=0;xx<804;xx=xx+1) begin
            @(negedge clk);x=xx;y=yy;de=xx<800;
            @(posedge clk);#1;
            if(od!==de_pipe[2] || oh!==0 || ov!==0)$fatal(1,"Diagnostic raster pipeline changed");
            if(od)begin $fwrite(f,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);pixels=pixels+1;end
            else if(rgb!==0)$fatal(1,"Diagnostic blanking not black");
        end
        $fclose(f);
        if(pixels!=480000)$fatal(1,"Raster size %0d",pixels);
        $display("PASS: all six FPGA pin labels, independent online, sticky errors/counts, frame snapshot, 800x600 raster and three-cycle pipeline");
        $display("ALL TESTS PASSED");$finish;
    end
    initial begin #20000000;$fatal(1,"Wiring screen watchdog");end
endmodule
