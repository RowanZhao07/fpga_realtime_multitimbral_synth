`timescale 1ns/1ps
module tb_synthesis;
    reg clk=0; always #10 clk=~clk;
    reg rst=1,ce=0,vibrato=0;
    reg [12:0] gates=0;
    reg [1:0] timbre=0;
    wire signed [18:0] mixed;
    wire valid; wire [12:0] active;
    polyphonic_engine dut(.sustain_down(1'b0),.clk(clk),.rst(rst),.sample_ce(ce),.gates(gates),
        .timbre(timbre),.vibrato(vibrato),.mixed(mixed),.valid(valid),.active(active));
    reg [12:0] volume=4096;
    reg echo=0;
    wire signed [15:0] sample;
    wire clipped;
    audio_output output_stage(.clk(clk),.rst(rst),.valid(valid),.mixed(mixed),
        .volume(volume),.echo_enable(echo),.sample(sample),.clipped(clipped));
    integer f,n,scenario=0,expected_mix;
    task frame;
        begin
            @(negedge clk); ce=1;
            @(negedge clk); ce=0;
            repeat(14) @(negedge clk);
            if((^sample)===1'bx) begin
                $display("phase=%h step=%h env=%h astep=%h wave=%h product=%h mixed=%h gain=%h",dut.voice_bank[0].voice.phase,dut.voice_bank[0].base_step,dut.voice_bank[0].voice.envelope,dut.voice_bank[0].voice.amplitude.attack_step,dut.voice_bank[0].voice.wave,dut.voice_bank[0].voice.product,mixed,output_stage.smooth_gain);
                $fatal(1,"Unknown sample");
            end
            if(clipped) $fatal(1,"Unexpected clipping");
            expected_mix=0;
            for(integer voice_index=0;voice_index<13;voice_index=voice_index+1)
                expected_mix=expected_mix+$signed(dut.voices[voice_index]);
            if($signed(mixed)!=expected_mix)
                $fatal(1,"Mixer changed independent voice gains or truncated the sum");
        end
    endtask
    task frames(input integer count);
        repeat(count) frame();
    endtask
    task capture(input integer number,input integer count);
        begin
            scenario=number;
            repeat(count) begin frame(); $fdisplay(f,"%0d,%0d,%0d",scenario,$signed(mixed),$signed(sample)); end
        end
    endtask
    initial begin
        f=$fopen("samples.csv","w"); if(!f) $fatal(1,"Cannot write sample capture");
        repeat(4) @(negedge clk); rst=0;
        frames(32); if(sample!==0 || active!==0) $fatal(1,"Idle must be silent");
        gates=8'hFF; frames(7000);
        if(active!==8'hFF) $fatal(1,"Eight voices did not activate");
        if(dut.voice_bank[0].voice.phase===dut.voice_bank[1].voice.phase)
            $fatal(1,"Independent phases did not diverge");
        if(dut.voice_bank[0].voice.amplitude.level!=50000) $fatal(1,"Sustain level mismatch");
        capture(0,32768);
        $display("PASS: eight simultaneous independent voices and stable sustain");
        gates=0; capture(1,5000);
        if(sample!==0 || active!==0) $fatal(1,"Release did not reach zero");
        for(integer tone=0;tone<4;tone=tone+1) begin
            timbre=tone; gates=1; frames(10000); capture(2+tone,8192);
            gates=0; frames(12000);
            if(active!==0) $fatal(1,"Preset release stuck");
        end
        $display("PASS: four presets, ADSR attack/decay/sustain/release");
        timbre=0; gates=1; frames(6000); vibrato=1; capture(6,16384);
        vibrato=0; volume=1024; frames(4096); capture(7,8192);
        volume=4096; frames(4096); capture(8,8192);
        gates=0; frames(1000);
        if(active==0) $fatal(1,"Release tail unexpectedly cut");
        gates=1; frames(1000);
        if(dut.voice_bank[0].voice.amplitude.level==0) $fatal(1,"Retrigger failed");
        $display("PASS: vibrato, volume ramp and note retrigger");
        gates=0; frames(12000);
        gates=13'h1FFF; frames(10000); capture(9,32768);
        if(active!==13'h1FFF) $fatal(1,"Thirteen independent voices did not activate");
        gates=0; frames(12000);
        if(active!=0 || sample!=0) $fatal(1,"Chromatic chord release did not reach silence");
        $display("PASS: thirteen-note chromatic chord, no clipping and complete release");
        $fclose(f); $display("ALL TESTS PASSED"); $finish;
    end
    initial begin #1000000000; $fatal(1,"Simulation watchdog"); end
endmodule
