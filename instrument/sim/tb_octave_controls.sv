`timescale 1ns/1ps
module tb_octave_controls;
    reg clk=0;always #10 clk=~clk;
    reg rst=1,online=1,ce=1,command_valid=0;
    reg [17:0] touched=0;
    reg [7:0] command=0;reg [15:0] value=0;
    wire [12:0] gates,volume,target_mask;
    wire [1:0] octave_select,timbre;
    wire vibrato,spectrum_mode,echo_enabled,guide_enabled;
    wire [8:0] position;
    performance_control #(.HOLD_SAMPLES(20),.REPEAT_SAMPLES(4)) dut(
        .clk(clk),.rst(rst),.sample_ce(ce),.online(online),.touched(touched),
        .command_valid(command_valid),.command(command),.value(value),
        .gates(gates),.timbre(timbre),.volume(volume),.octave_select(octave_select),
        .vibrato(vibrato),.spectrum_mode(spectrum_mode),.echo_enabled(echo_enabled),.guide_enabled(guide_enabled));
    practice_guide guide(.clk(clk),.rst(rst),.sample_ce(ce),.enabled(guide_enabled),.gates(gates),
        .command_valid(command_valid),.command(command),.value(value),.input_error(1'b0),.bpm(8'd120),
        .target_mask(target_mask),.position(position));
    task ticks(input integer n);repeat(n) @(negedge clk);endtask
    task guide_command(input [7:0] c,input [15:0] v);
      command=c;value=v;command_valid=1;ticks(1);command_valid=0;ticks(3);
    endtask
    task unchanged;
        if(timbre!=0 || volume!=2048 || vibrato || spectrum_mode || echo_enabled || !guide_enabled)
            $fatal(1,"Octave gesture leaked into a legacy control");
    endtask
    task up;begin touched=0;ticks(3);end endtask
    integer o;
    initial begin
        ticks(4);rst=0;ticks(3);
        if(octave_select!==1) $fatal(1,"Default octave must be 4");
        guide_command("N",0);guide_command("A",1);guide_command("A",2);guide_command("A",4);guide_command("A",8);guide_command("A",1);guide_command("Z",0);
        command="G";value=1;command_valid=1;ticks(1);command_valid=0;ticks(3);
        touched=18'h20000;ticks(45);unchanged;
        if(octave_select!==1 || gates!=0) $fatal(1,"X0 alone changed pitch or made sound");up;
        for(o=0;o<4;o=o+1) begin
            touched=18'h20000;ticks(2);
            touched=18'h20000 | (18'h100<<o);ticks(45);
            if(octave_select!==o[1:0] || gates!=0) $fatal(1,"Wrong X0+C%0d mapping",o);
            unchanged;
            // Releasing X0 first must not expose the still-held control.
            touched=18'h100<<o;ticks(45);unchanged;up;unchanged;
            if(position!==o) $fatal(1,"Octave selection reset or advanced GUIDE");
            touched={10'd0,target_mask[7:0]};ticks(3);up;
            if(position!==o+1) $fatal(1,"GUIDE target no longer advances in octave %0d",o+3);
        end
        // All four controls plus X0 is ambiguous, including partial release.
        touched=18'h20f00;ticks(45);unchanged;
        touched=18'h20100;ticks(3);
        if(octave_select!==3) $fatal(1,"Ambiguous chord selected on partial release");up;
        // Controls released first: no second selection until X0 is released.
        touched=18'h20195;ticks(3);
        if(octave_select!==0 || gates!==13'h095) $fatal(1,"Simultaneous gesture/note gates");
        touched=18'h20095;ticks(3);touched=18'h20895;ticks(45);
        if(octave_select!==0 || gates!==13'h095) $fatal(1,"One X0 gesture selected twice");
        unchanged;up;
        // A pending C0 release from before X0 must also be consumed.
        touched=18'h100;ticks(2);touched=18'h20100;ticks(2);up;unchanged;
        // No sample enable: no pitch register update; vibrato is still masked.
        ce=0;touched=18'h20800;ticks(4);
        if(octave_select!==0 || vibrato) $fatal(1,"Asynchronous octave update");
        ce=1;ticks(2);up;if(octave_select!==3) $fatal(1,"Sample-enabled selection missing");
        online=0;ticks(3);if(gates || vibrato) $fatal(1,"Offline protection lost");
        online=1;ticks(3);if(octave_select!==3) $fatal(1,"Reconnect changed selected octave");
        // Original C0 and all-control calibration still work after a gesture.
        touched=18'h100;ticks(2);up;if(timbre!==1) $fatal(1,"Normal C0 no longer works");
        touched=18'hf00;ticks(25);up;if(!spectrum_mode) $fatal(1,"Calibration gesture lost");
        touched=18'h20100;ticks(25);up;if(octave_select!==3) $fatal(1,"Calibration changed stored octave");
        rst=1;ticks(2);rst=0;ticks(3);
        if(octave_select!==1 || guide_enabled || timbre || spectrum_mode) $fatal(1,"Reset defaults");
        $display("PASS: four octave mappings, both release orders, ambiguity, single-shot, note gates, GUIDE, offline/reset and legacy controls");
        $display("ALL TESTS PASSED");$finish;
    end
    initial begin #1000000;$fatal(1,"Octave controls watchdog");end
endmodule
