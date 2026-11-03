`timescale 1ns/1ps
module tb_controls;
    reg clk=0; always #10 clk=~clk;
    reg rst=1,online=1,ce=1;
    reg [17:0] touched=0;
    wire [12:0] gates;
    wire [2:0] timbre;
    wire [12:0] volume;
    wire vibrato,spectrum_mode,echo_enabled,guide_enabled;
    performance_control #(.HOLD_SAMPLES(20),.REPEAT_SAMPLES(4)) dut(
        .clk(clk),.rst(rst),.sample_ce(ce),.online(online),.touched(touched),
        .command_valid(1'b0),.command(8'd0),.value(16'd0),.gates(gates),.timbre(timbre),.volume(volume),.vibrato(vibrato),.spectrum_mode(spectrum_mode),
        .echo_enabled(echo_enabled),.guide_enabled(guide_enabled));
    task ticks(input integer n); repeat(n) @(negedge clk); endtask
    initial begin
        ticks(3); rst=0; ticks(2);
        touched=18'h1F000; ticks(2);
        if(gates!==13'h1F00) $fatal(1,"Five independent chromatic note gates");
        touched=18'h20000; ticks(2);
        if(gates!=0 || timbre!=0 || vibrato) $fatal(1,"X0 must remain reserved");
        touched=12'h095; ticks(2); if(gates!==8'h95) $fatal(1,"Polyphonic gates");
        touched=12'h195; ticks(10); if(timbre!=0) $fatal(1,"Premature preset change");
        touched=12'h095; ticks(2); if(timbre!=1 || gates!=8'h95) $fatal(1,"Preset release edge");
        touched=12'h695;ticks(2);touched=12'h295;ticks(1);
        if(volume!=2048)$fatal(1,"Legacy simultaneous VOL release must not retrigger initial volume step");
        touched=12'h295; ticks(80); if(volume!=512 || gates!=8'h95) $fatal(1,"Volume down limit");
        touched=12'h495; ticks(80); if(volume!=4096) $fatal(1,"Volume up limit");
        touched=12'h895; ticks(2); if(!vibrato || gates!=8'h95) $fatal(1,"Independent vibrato");
        touched=12'hF00; ticks(40); if(!spectrum_mode || gates!=8'hFF) $fatal(1,"Spectrum gesture");
        ticks(50); if(!spectrum_mode) $fatal(1,"Held gesture toggled twice");
        touched=0; ticks(3); if(timbre!=1) $fatal(1,"Gesture leaked preset event");
        touched=12'hF00; ticks(21); if(spectrum_mode) $fatal(1,"Spectrum exit");
        touched=0; ticks(3);
        if(echo_enabled || guide_enabled) $fatal(1,"Effects must default off");
        touched=12'h100; ticks(50); if(!echo_enabled) $fatal(1,"Echo long press");
        touched=0; ticks(3); if(timbre!=1) $fatal(1,"Echo leaked preset event");
        touched=12'h100; ticks(21); if(echo_enabled) $fatal(1,"Echo exit");
        touched=0; ticks(3);
        touched=12'h600; ticks(50); if(!guide_enabled) $fatal(1,"Guide long press");
        touched=0; ticks(3); if(volume!=4096) $fatal(1,"Guide changed volume");
        online=0; ticks(2);
        if(gates!=0 || vibrato || spectrum_mode) $fatal(1,"Offline safety");
        $display("PASS: independent note/control keys, volume bounds, preset edge, long gesture, offline release");
        $display("ALL TESTS PASSED"); $finish;
    end
    initial begin #1000000; $fatal(1,"Control watchdog"); end
endmodule
