`timescale 1ns/1ps
// Real engine/PCM output: verify pitch mathematically, then compare held/pedal
// tails bit-for-bit against an engine whose octave selector never moved.
module tb_octave_audio;
    reg clk=0;always #5 clk=~clk;
    reg rst=1,ce=0,pedal=0,vibrato=0;
    reg [12:0] gates=0;
    reg [1:0] octave_select=1,reference_octave=1,timbre=0;
    wire signed [18:0] mixed,reference_mixed;
    wire valid,reference_valid,clipped;
    wire [12:0] active;
    wire signed [15:0] pcm;
    polyphonic_engine dut(.clk(clk),.rst(rst),.sample_ce(ce),.gates(gates),
        .sustain_down(pedal),.timbre(timbre),.octave_select(octave_select),.vibrato(vibrato),
        .mixed(mixed),.valid(valid),.active(active));
    polyphonic_engine reference(.clk(clk),.rst(rst),.sample_ce(ce),.gates(gates),
        .sustain_down(pedal),.timbre(timbre),.octave_select(reference_octave),.vibrato(vibrato),
        .mixed(reference_mixed),.valid(reference_valid));
    audio_output output_stage(.clk(clk),.rst(rst),.valid(valid),.mixed(mixed),
        .volume(13'd4096),.echo_enable(1'b0),.sample(pcm),.clipped(clipped));
    wire [31:0] measured_step[0:12];
    wire [31:0] measured_phase[0:12];
    for(genvar v=0;v<13;v=v+1) begin
        assign measured_step[v]=dut.steps[v];
        assign measured_phase[v]=dut.phase[v];
    end
    task frame;
        begin
            @(negedge clk);ce=1;@(negedge clk);ce=0;wait(valid && reference_valid);repeat(8) @(negedge clk);
            if((^pcm)===1'bx || clipped) $fatal(1,"Unknown or clipped octave PCM");
        end
    endtask
    task reset_audio;
        begin rst=1;gates=0;repeat(4) @(negedge clk);rst=0;frame;end
    endtask
    task same_audio(input integer count);
        repeat(count) begin
            frame;
            if(mixed!==reference_mixed || valid!==reference_valid)
                $fatal(1,"Held/pedal/release sound changed when octave selection moved");
        end
    endtask
    function integer semitone(input integer key);
        case(key)
            0:semitone=0;1:semitone=2;2:semitone=4;3:semitone=5;
            4:semitone=7;5:semitone=9;6:semitone=11;7:semitone=12;
            8:semitone=1;9:semitone=3;10:semitone=6;11:semitone=8;default:semitone=10;
        endcase
    endfunction
    integer f,o,k,n,tone;real hz,actual_hz;
    reg [31:0] phase_before;
    initial begin
        f=$fopen("output/octaves.csv","w");if(!f)$fatal(1,"Cannot create octave PCM capture");
        $fdisplay(f,"octave,key,sample,pcm");
        for(o=0;o<4;o=o+1) begin
            octave_select=o;reference_octave=o;pedal=0;timbre=0;vibrato=0;
            reset_audio;gates=13'h1fff;frame;
            for(k=0;k<13;k=k+1) begin
                hz=440.0*(2.0**((12.0*(o+4)+semitone(k)-69.0)/12.0));
                actual_hz=$itor(measured_step[k])*48828.125/4294967296.0;
                if(actual_hz-hz>0.0001 || hz-actual_hz>0.0001)
                    $fatal(1,"Octave %0d key %0d tuning: %f vs %f",o+3,k,actual_hz,hz);
            end
            repeat(6000) frame;
            if(active!==13'h1fff) $fatal(1,"Missing simultaneous octave voices");
            // Capture the low endpoint, a sharp, A and the high endpoint.
            for(k=0;k<4;k=k+1) begin
                reset_audio;
                case(k) 0:gates=1;1:gates=13'h100;2:gates=13'h020;3:gates=13'h080;endcase
                repeat(6000) frame;
                for(n=0;n<8192;n=n+1) begin frame;$fdisplay(f,"%0d,%0d,%0d,%0d",o+3,k,n,pcm);end
            end
        end
        $fclose(f);
        for(tone=0;tone<4;tone=tone+1) begin
            octave_select=1;reference_octave=1;timbre=tone;pedal=1;vibrato=0;
            reset_audio;gates=13'h101;same_audio(1000);
            octave_select=3;same_audio(500); // Physically held notes stay C4/C#4.
            gates=0;vibrato=1;same_audio(700); // Pedal keeps pitch, vibrato stays live.
            octave_select=0;same_audio(700);
            pedal=0;octave_select=2;same_audio(500); // Release tail also stays put.
            vibrato=0;octave_select=3;gates=1;phase_before=measured_phase[0];frame;
            if(measured_step[0]!==32'd23012828 || measured_step[1]!==32'd24381242)
                $fatal(1,"Old white/sharp tails were retuned");
            if(dut.steps[2]!==32'd92051312) $fatal(1,"New octave note missing from free slot");
            gates=2;frame;
            if(dut.steps[3]!==32'd103324104) $fatal(1,"New D note missed selected octave");
            gates=0;repeat(13000) frame;
            if(active!=0 || pcm!=0) $fatal(1,"Octave voices failed to release");
        end
        $display("PASS: 52 pitches, all-note chords, octave PCM, four-timbre held/pedal/release invariance, vibrato, retrigger and silence");
        $display("ALL TESTS PASSED");$finish;
    end
    initial begin #(64'd4000000000);$fatal(1,"Octave audio watchdog");end
endmodule
