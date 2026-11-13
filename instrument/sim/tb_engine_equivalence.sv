`timescale 1ns/1ps
// The frozen reference is our pre-optimization release. Compare at fixed sample
// boundaries, allowing valid to arrive earlier but never allowing PCM/state drift.
module engine_equivalence_case #(parameter VARIABLE_SUSTAIN=0, PITCH_BEND=0)(output reg done=0);
    reg clk=0; always #10 clk=~clk;
    reg rst=1, ce=0, pedal=1, vibrato=0;
    reg [12:0] gates=0;
    reg [2:0] timbre=0;
    reg [1:0] octave=1;
    reg [4:0] strength=16;
    reg signed [15:0] bend=0;
    wire signed [18:0] actual, expected;
    wire av, ev, ao, eo;
    wire [12:0] aa, ea;
    wire [103:0] al, el;
    wire [5:0] ac, ec;
    polyphonic_engine #(.VARIABLE_SUSTAIN(VARIABLE_SUSTAIN),.ENABLE_PITCH_BEND(PITCH_BEND)) dut(
        .clk(clk),.rst(rst),.sample_ce(ce),.sustain_down(pedal),.sustain_strength(strength),
        .gates(gates),.timbre(timbre),.octave_select(octave),.vibrato(vibrato),.pitch_bend(bend),
        .mixed(actual),.valid(av),.overrun(ao),.active(aa),.voice_levels(al),.voice_count(ac));
    polyphonic_engine_reference #(.VARIABLE_SUSTAIN(VARIABLE_SUSTAIN),.ENABLE_PITCH_BEND(PITCH_BEND)) ref_dut(
        .clk(clk),.rst(rst),.sample_ce(ce),.sustain_down(pedal),.sustain_strength(strength),
        .gates(gates),.timbre(timbre),.octave_select(octave),.vibrato(vibrato),.pitch_bend(bend),
        .mixed(expected),.valid(ev),.overrun(eo),.active(ea),.voice_levels(el),.voice_count(ec));
`ifdef __ICARUS__
    initial begin
        #1; force dut.address=11'd1; force ref_dut.address=11'd1;
        #1; release dut.address; release ref_dut.address;
    end
`endif
    integer frames=0, a_cycles, e_cycles, a_pulses, e_pulses;
    integer max_actual=0, max_expected=0, full_frames=0, steals=0, f, i, k, c;
    reg [31:0] rng=32'h71e0cafe;
    // Hierarchical per-lane checks must have elaboration-time constant indices.
    genvar voice;
    reg check_state=0;
    generate for(voice=0;voice<32;voice=voice+1) begin: state_checks
        always @(posedge check_state) begin
            if(dut.phase[voice]!==ref_dut.phase[voice] || dut.steps[voice]!==ref_dut.steps[voice] ||
               dut.age[voice]!==ref_dut.age[voice] || dut.owner[voice]!==ref_dut.owner[voice] ||
               dut.preset[voice]!==ref_dut.preset[voice] || dut.brightness[voice]!==ref_dut.brightness[voice] ||
               dut.last_sample[voice]!==ref_dut.last_sample[voice] ||
               dut.steal_tail[voice]!==ref_dut.steal_tail[voice] || dut.fade_left[voice]!==ref_dut.fade_left[voice] ||
               dut.envelopes[voice]!==ref_dut.envelopes[voice] ||
               dut.voice_bank[voice].amplitude.state!==ref_dut.voice_bank[voice].amplitude.state)
                $fatal(1,"Voice state mismatch mode=%0d frame=%0d slot=%0d",VARIABLE_SUSTAIN,frames,voice);
        end
    end endgenerate
    task frame(input integer scenario);
        begin
            ce=1; @(negedge clk); ce=0;
            a_cycles=0; e_cycles=0; a_pulses=0; e_pulses=0;
            for(c=1;c<=1023;c=c+1) begin
                @(negedge clk);
                if(av) begin a_cycles=c; a_pulses=a_pulses+1; end
                if(ev) begin e_cycles=c; e_pulses=e_pulses+1; end
            end
            if(a_pulses!=1 || e_pulses!=1 || ao || eo || a_cycles>600 || a_cycles>e_cycles)
                $fatal(1,"Deadline/valid mismatch frame=%0d cycles=%0d/%0d pulses=%0d/%0d",frames,a_cycles,e_cycles,a_pulses,e_pulses);
            if(actual!==expected || aa!==ea || al!==el || ac!==ec || (^actual)===1'bx ||
               dut.occupied!==ref_dut.occupied || dut.held!==ref_dut.held)
                $fatal(1,"PCM/allocator mismatch mode=%0d frame=%0d PCM=%0d/%0d",VARIABLE_SUSTAIN,frames,actual,expected);
            check_state=1; #1; check_state=0;
            if(a_cycles>max_actual) max_actual=a_cycles;
            if(e_cycles>max_expected) max_expected=e_cycles;
            if(ac==32) full_frames=full_frames+1;
            for(i=0;i<32;i=i+1) if(dut.fade_left[i]!=0) steals=steals+1;
            $fdisplay(f,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",VARIABLE_SUSTAIN,frames,scenario,ac,a_cycles,e_cycles,actual,expected);
            frames=frames+1;
        end
    endtask
    initial begin
        f=$fopen(VARIABLE_SUSTAIN ? "output/engine_equivalence_expression.csv" : "output/engine_equivalence_legacy.csv","w");
        $fdisplay(f,"variable_sustain,frame,scenario,voices,optimized_clocks,baseline_clocks,optimized_pcm,baseline_pcm");
        repeat(4) @(negedge clk); rst=0;
        repeat(8) frame(0);
        gates=1; repeat(160) frame(1);
        // Dense onset, repeated notes, all presets/octaves and oldest tie order.
        for(k=0;k<32;k=k+1) begin
            gates=0; frame(2);
            timbre=k%8; octave=k%4; gates=13'h1fff; repeat(8) frame(2);
        end
        if(ac!=32) $fatal(1,"Dense stimulus did not fill the voice pool");
        // Releasing with pedal up exercises quietest-release ranking and ties.
        for(k=0;k<1024;k=k+1) begin
            rng=rng*32'd1664525+32'd1013904223;
            gates=k%11==0 ? 13'h1fff : k%7==0 ? 13'd0 : rng[12:0];
            timbre=rng[15:13]; octave=rng[17:16]; vibrato=rng[18];
            pedal=k%64<32; strength=rng[24:20];
            case(k%4)
                0:bend=16'sd8026; 1:bend=-16'sd7150;
                2:bend=16'sd0; default:bend=rng[31:16];
            endcase
            frame(3);
        end
        gates=0; pedal=0; repeat(12000) frame(4);
        if(ac!=0 || actual!=0 || dut.occupied!=0) $fatal(1,"Release did not reach exact silence");
        if(full_frames<100 || steals<100 || max_actual>600 || max_expected<800)
            $fatal(1,"Insufficient stress coverage %0d %0d %0d/%0d",full_frames,steals,max_actual,max_expected);
        // Abort in flight and restart; neither stale voice state nor valid may leak.
        gates=13'h1fff; ce=1; @(negedge clk); ce=0;
        repeat(23) @(negedge clk); rst=1; repeat(4) @(negedge clk); rst=0; gates=0;
        repeat(8) frame(5); gates=1; repeat(8) frame(5);
        $fclose(f);
        $display("PASS: mode=%0d %0d bit-exact frames, %0d full-pool frames, %0d fading tails; max %0d -> %0d clocks",
            VARIABLE_SUSTAIN,frames,full_frames,steals,max_expected,max_actual);
        done=1;
    end
endmodule

module tb_engine_equivalence;
    wire legacy_done, expression_done;
    engine_equivalence_case legacy(legacy_done);
    engine_equivalence_case #(.VARIABLE_SUSTAIN(1),.PITCH_BEND(1)) expression(expression_done);
    initial begin
        wait(legacy_done && expression_done);
        $display("ALL TESTS PASSED"); $finish;
    end
    initial begin #400000000; $fatal(1,"Engine equivalence watchdog"); end
endmodule
