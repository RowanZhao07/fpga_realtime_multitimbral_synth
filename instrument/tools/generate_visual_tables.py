"""Reproducible mathematical constants; no sampled recordings or external assets."""
from pathlib import Path
import math

src = Path(__file__).resolve().parents[1] / 'src'

def rom(name, bits, values, width=16):
    lines = ['`timescale 1ns/1ps', '// Generated mathematical constants; see tools/generate_visual_tables.py.',
             f'module {name}(input wire [{bits-1}:0] address, output reg signed [{width-1}:0] value);',
             'always @* case(address)']
    for n, v in enumerate(values):
        lines.append(f"{bits}'d{n}: value={width}'h{round(v)&((1<<width)-1):0{(width+3)//4}X};")
    lines += ['endcase', 'endmodule', '']
    (src/(name+'.v')).write_text('\n'.join(lines), encoding='utf-8')

waves=[]
for preset in range(4):
    def waveform(t):
        if preset == 0: return math.sin(t)
        if preset == 1: return sum(math.sin(h*t)/h for h in range(1,16,2))
        if preset == 2: return sum(math.sin(h*t)/h for h in range(1,16))
        return math.sin(t)+math.sin(2*t)+0.7*math.sin(5*t)+0.4*math.sin(9*t)
    vals=[waveform(2*math.pi*n/256) for n in range(256)]
    scale=8191/max(abs(v) for v in vals)
    waves += [v*scale for v in vals]
rom('timbre_lut', 10, waves)
# 4096-point Hann-windowed FFT, forward transform e^(-j*theta).
rom('fft_cos_lut',11,[32767*math.cos(2*math.pi*n/4096) for n in range(2048)])
rom('fft_sin_lut',11,[-32767*math.sin(2*math.pi*n/4096) for n in range(2048)])
rom('fft_window_lut',12,[32767*(.5-.5*math.cos(2*math.pi*n/4095)) for n in range(4096)])
print('Generated four analytical waveforms and 4096-point FFT coefficients.')
