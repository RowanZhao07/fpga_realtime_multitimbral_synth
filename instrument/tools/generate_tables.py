"""Reproduce mathematical waveform and equal-temperament tuning constants."""
import math
from pathlib import Path
import argparse

parser = argparse.ArgumentParser()
parser.add_argument('--clock-hz', type=float, default=50_000_000,
                    help='Master clock; on-board 50 MHz crystal by default')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
fs = args.clock_hz / 1024
lines = ['`timescale 1ns/1ps',
         '// Mathematical single-cycle sine, not recorded audio.',
         'module sine_lut(input wire [7:0] address, output reg signed [15:0] value);',
         '    always @* case(address)']
for i in range(256):
    val = round(8191 * math.sin(2 * math.pi * i / 256))
    lines.append(f"        8'd{i}: value=16'h{val & 65535:04X};")
lines += ['    endcase', 'endmodule', '']
(root/'src/sine_lut.v').write_text('\n'.join(lines), encoding='utf-8')
lines = ['`timescale 1ns/1ps', f'// Tuning for {fs:.8f} samples/second.',
         'module note_frequency #(parameter integer KEY=0)(output wire [31:0] step);',
         '    function [31:0] lookup;', '        input integer k;', '        begin case(k)']
for i, midi in enumerate([60, 62, 64, 65, 67, 69, 71, 72]):
    freq = 440 * 2**((midi-69)/12)
    inc = round(freq/fs*2**32)
    lines.append(f"            {i}: lookup=32'd{inc}; // MIDI {midi}, {freq:.6f} Hz")
lines += ["            default: lookup=0;", '        endcase end', '    endfunction',
          '    assign step=lookup(KEY);', 'endmodule', '']
(root/'src/note_frequency.v').write_text('\n'.join(lines), encoding='utf-8')
print(f'Generated sine and tuning constants: fs={fs:.8f} Hz')
