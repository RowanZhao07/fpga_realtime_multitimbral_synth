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
        # Electric-key character: strong fundamental, a mild hammer overtone
        # spectrum, shaped by the struck/exponential envelope in envelope_adsr.
        if preset == 1: return (math.sin(t)+.35*math.sin(2*t)+.15*math.sin(3*t)
                                +.06*math.sin(5*t)+.025*math.sin(7*t))
        # A gently rolled-off harmonic series for warm sustained strings.
        if preset == 2: return sum(math.sin(h*t)/h**1.35 for h in range(1,13))
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
