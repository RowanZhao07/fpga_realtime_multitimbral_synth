`timescale 1ns/1ps
// Tuning for 48828.12500000 samples/second.
module note_frequency #(parameter integer KEY=0)(output wire [31:0] step);
    function [31:0] lookup;
        input integer k;
        begin case(k)
            0: lookup=32'd23012828; // MIDI 60, 261.625565 Hz
            1: lookup=32'd25831026; // MIDI 62, 293.664768 Hz
            2: lookup=32'd28994347; // MIDI 64, 329.627557 Hz
            3: lookup=32'd30718440; // MIDI 65, 349.228231 Hz
            4: lookup=32'd34480283; // MIDI 67, 391.995436 Hz
            5: lookup=32'd38702809; // MIDI 69, 440.000000 Hz
            6: lookup=32'd43442435; // MIDI 71, 493.883301 Hz
            7: lookup=32'd46025656; // MIDI 72, 523.251131 Hz
            8: lookup=32'd24381242; // MIDI 61, 277.182631 Hz
            9: lookup=32'd27367019; // MIDI 63, 311.126984 Hz
            10: lookup=32'd32545054; // MIDI 66, 369.994423 Hz
            11: lookup=32'd36530588; // MIDI 68, 415.304698 Hz
            12: lookup=32'd41004198; // MIDI 70, 466.163762 Hz
            default: lookup=0;
        endcase end
    endfunction
    assign step=lookup(KEY);
endmodule
