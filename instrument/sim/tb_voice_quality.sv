`timescale 1ns/1ps
// Analytic sine oracle catches phase-address truncation; an audible output
// discontinuity catches phase resets while a release tail is still sounding.
module tb_voice_quality;
    reg clk=0; always #10 clk=~clk;
    reg rst=1,ce=0,gate=0;
    wire signed [15:0] sample;
    wire active;
    localparam [31:0] STEP=32'd46025656; // C5 at 48828.125 Hz
    synthesis_voice dut(.clk(clk),.rst(rst),.sample_ce(ce),.gate(gate),
        .phase_step(STEP),.timbre(2'd0),.sample(sample),.active(active));
    task frame;
        begin
            @(negedge clk);ce=1;
            @(negedge clk);ce=0;
            repeat(30) @(negedge clk);
            if((^sample)===1'bx) $fatal(1,"Unknown voice sample");
        end
    endtask
    reg [31:0] reference_phase=0;
    real expected,error,energy=0,rms_error;
    integer previous_sample,jump,failures=0;
    initial begin
        repeat(5) @(negedge clk);rst=0;gate=1;
        frame();
        repeat(7000) begin frame(); reference_phase=reference_phase+STEP; end
        repeat(32768) begin
            frame(); reference_phase=reference_phase+STEP;
            expected=8191.0*50000.0/65536.0*$sin(6.283185307179586*$itor(reference_phase)/4294967296.0);
            // $itor is signed: a negative phase differs by one full cycle.
            error=$itor($signed(sample))-expected;
            energy=energy+error*error;
        end
        rms_error=$sqrt(energy/32768.0);
        $display("QUALITY: C5 sine RMS error versus analytic reference = %0.6f PCM counts",rms_error);
        if(rms_error>3.0) begin
            $display("FAIL: phase lookup produces excessive waveform error");failures=failures+1;
        end
        // Release near a positive peak, then immediately repeat the same key.
        while(sample<6000) frame();
        gate=0;frame();previous_sample=sample;
        gate=1;frame();jump=$signed(sample)-previous_sample;
        if(jump<0) jump=-jump;
        $display("QUALITY: repeated-key output jump = %0d PCM counts",jump);
        if(jump>500) begin
            $display("FAIL: restarting a sounding key discontinuously resets its waveform");failures=failures+1;
        end
        gate=0;repeat(5000) frame();
        if(active || sample!=0) $fatal(1,"Interpolated voice did not release to exact silence");
        if(failures) $fatal(1,"Voice quality failures: %0d",failures);
        $display("ALL TESTS PASSED");$finish;
    end
    initial begin #100000000;$fatal(1,"Voice quality watchdog");end
endmodule

// Same performed notes for both revisions: C, F, G and Am, then dense chords.
// Captures real RTL output, with no waveform normalization in the testbench.
module tb_chord_audio;
    reg clk=0;always #10 clk=~clk;
    reg rst=1,ce=0;
    reg [12:0] gates=0;
    reg [1:0] timbre=0;
    wire signed [18:0] mixed;
    wire signed [15:0] sample;
    wire valid,clipped;
    wire [12:0] active;
    polyphonic_engine engine(.clk(clk),.rst(rst),.sample_ce(ce),.gates(gates),
        .timbre(timbre),.vibrato(1'b0),.mixed(mixed),.valid(valid),.active(active));
    audio_output output_stage(.clk(clk),.rst(rst),.valid(valid),.mixed(mixed),
        .volume(13'd4096),.echo_enable(1'b0),.sample(sample),.clipped(clipped));
    integer f,tone,n;
    task frame;
        begin
            @(negedge clk);ce=1;
            @(negedge clk);ce=0;repeat(30) @(negedge clk);
            if((^sample)===1'bx || clipped) $fatal(1,"Unknown or clipped chord audio");
        end
    endtask
    task capture(input [12:0] notes,input integer count);
        begin
            gates=notes;
            repeat(count) begin frame();$fdisplay(f,"%0d,%0d",tone,$signed(sample));end
        end
    endtask
    initial begin
        f=$fopen("chord_samples.csv","w");if(!f) $fatal(1,"Cannot capture chords");
        repeat(5) @(negedge clk);rst=0;
        for(tone=0;tone<4;tone=tone+1) begin
            timbre=tone;gates=0;repeat(12000) frame();
            capture(13'h015,24414);capture(0,5000); // C4 E4 G4
            capture(13'h0A8,24414);capture(0,5000); // F4 A4 C5
            capture(13'h052,24414);capture(0,5000); // G4 B4 D4
            capture(13'h0A4,24414);capture(0,12000); // A4 C5 E4, retain full string tail
            if(active!=0 || sample!=0) $fatal(1,"Listening excerpt truncated a release tail");
            capture(13'h0FF,16000);capture(0,12000);
            capture(13'h1FFF,16000);capture(0,12000);
            if(active!=0 || sample!=0) $fatal(1,"Chord release stuck");
        end
        $fclose(f);$display("ALL TESTS PASSED");$finish;
    end
    initial begin #1000000000;$fatal(1,"Chord capture watchdog");end
endmodule
