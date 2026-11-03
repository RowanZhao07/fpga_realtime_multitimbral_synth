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
for preset in range(8):
    def waveform(t):
        if preset == 0: return math.sin(t)
        # Electric-key character: strong fundamental, a mild hammer overtone
        # spectrum, shaped by the struck/exponential envelope in envelope_adsr.
        if preset == 1: return (math.sin(t)+.35*math.sin(2*t)+.15*math.sin(3*t)
                                +.06*math.sin(5*t)+.025*math.sin(7*t))
        # A gently rolled-off harmonic series for warm sustained strings.
        if preset == 2: return sum(math.sin(h*t)/h**1.35 for h in range(1,13))
        if preset == 3: return math.sin(t)+math.sin(2*t)+0.7*math.sin(5*t)+0.4*math.sin(9*t)
        # Flute-like, organ-like, plucked-string and bass approximations.
        # All partials are harmonic; the played pitch remains the fundamental.
        if preset == 4: return math.sin(t)+.18*math.sin(2*t)+.08*math.sin(3*t)+.025*math.sin(4*t)
        if preset == 5: return (.85*math.sin(t)+.70*math.sin(2*t)
                                +.40*math.sin(4*t)+.18*math.sin(8*t))
        if preset == 6: return sum(math.sin(h*t)*(.35 if h % 3 == 0 else 1)/h**1.15
                                  for h in range(1,11))
        return math.sin(t)+.50*math.sin(2*t)+.28*math.sin(3*t)+.09*math.sin(4*t)+.035*math.sin(5*t)
    vals=[waveform(2*math.pi*n/256) for n in range(256)]
    scale=8191/max(abs(v) for v in vals)
    waves += [v*scale for v in vals]
rom('timbre_lut', 11, waves)
# 4096-point Hann-windowed FFT, forward transform e^(-j*theta).
rom('fft_cos_lut',11,[32767*math.cos(2*math.pi*n/4096) for n in range(2048)])
rom('fft_sin_lut',11,[-32767*math.sin(2*math.pi*n/4096) for n in range(2048)])
rom('fft_window_lut',12,[32767*(.5-.5*math.cos(2*math.pi*n/4095)) for n in range(4096)])
print('Generated eight analytical waveforms and 4096-point FFT coefficients.')
