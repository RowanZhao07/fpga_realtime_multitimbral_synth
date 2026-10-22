"""Validate captured RTL samples, write reproducible spectral evidence and WAV."""
from pathlib import Path
import json
import wave
import numpy as np

root = Path(__file__).resolve().parents[1]
data = np.loadtxt(root/'sim/samples.csv', delimiter=',', dtype=np.int64)
fs = 50_000_000 / 1024
out = root/'sim/output'
out.mkdir(exist_ok=True)
def block(n):
    return data[data[:, 0] == n, 2].astype(float)
def spectrum(x):
    return np.fft.rfftfreq(len(x), 1/fs), np.abs(np.fft.rfft(x*np.hanning(len(x))))
def rms(x):
    return float(np.sqrt(np.mean(x*x)))
x = block(0)
freq, mag = spectrum(x)
notes = [440*2**((m-69)/12) for m in [60,62,64,65,67,69,71,72]]
peaks = []
for target in notes:
    ids = np.flatnonzero(abs(freq-target)<4)
    i = ids[np.argmax(mag[ids])]
    assert mag[i] > mag.max()*0.35, f'Missing independent voice: {target}'
    assert abs(freq[i]-target)<2, f'Wrong tuning: {target}'
    peaks.append({'target_hz':target, 'fft_bin_hz':float(freq[i]), 'relative_peak':float(mag[i]/mag.max())})
assert np.all(block(1)[-100:]==0), 'Envelope did not release to silence'
ratio = rms(block(7))/rms(block(8))
assert 0.24 < ratio < 0.26, f'Gain ratio {ratio}'
assert np.max(np.abs(data[:,2])) < 32767, 'Output clipped'
chromatic_freq, chromatic_mag = spectrum(block(9))
chromatic_peaks = []
for midi in range(60,73):
    target = 440*2**((midi-69)/12)
    ids = np.flatnonzero(abs(chromatic_freq-target)<4)
    i = ids[np.argmax(chromatic_mag[ids])]
    assert chromatic_mag[i] > chromatic_mag.max()*0.35, f'Missing chromatic voice: MIDI {midi}'
    assert abs(chromatic_freq[i]-target)<2, f'Wrong chromatic tuning: MIDI {midi}'
    chromatic_peaks.append({'midi':midi,'target_hz':target,'fft_bin_hz':float(chromatic_freq[i])})
harmonics = []
for n in range(4):
    f,m = spectrum(block(2+n))
    values = [float(m[np.abs(f-notes[0]*h)<8].max()) for h in [1,2,3,5]]
    harmonics.append([v/values[0] for v in values])
assert harmonics[0][1]<0.03 and harmonics[0][2]<0.03
# Late-time windows now intentionally have fewer overtones. Early/late evolution
# is verified independently in analyze_dynamic_timbre.py, not against static LUT ratios.
assert harmonics[1][1]<0.03 and harmonics[1][2]<0.03
assert 0.08<harmonics[2][1]<0.4
assert harmonics[3][1]<0.03
result = {'evidence_type':'RTL simulation, not physical audio capture',
          'nominal_sample_rate_hz':fs,'independent_voices':13,'spectral_peaks':peaks,
          'chromatic_peaks':chromatic_peaks,
          'gain_quarter_ratio':ratio,'preset_harmonics_1_2_3_5':harmonics,
          'captured_peak_pcm16':int(np.abs(data[:,2]).max()),'checks_passed':True}
(out/'audio_analysis.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
# Integer WAV header uses nearest sample rate; the exact simulation rate is above.
for name,n in [('eight_voices',0),('thirteen_voices',9),('sine',2),('epiano',3),('strings',4),('metal',5)]:
    with wave.open(str(out/(name+'.wav')),'wb') as w:
        w.setnchannels(1);w.setsampwidth(2);w.setframerate(round(fs))
        w.writeframes(block(n).astype('<i2').tobytes())
try:
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    fig,ax = plt.subplots(figsize=(10,4))
    db = 20*np.log10(np.maximum(mag/mag.max(),1e-6))
    ax.plot(freq,db,lw=1)
    for item in peaks:
        ax.axvline(item['target_hz'],color='orange',alpha=.5,lw=.7)
    ax.set(xlim=(200,580),ylim=(-75,3),xlabel='Frequency (Hz)',ylabel='Relative magnitude (dB)',
           title='Eight independent voices — RTL simulation')
    ax.grid(alpha=.25);fig.tight_layout();fig.savefig(out/'eight_voices_spectrum.png',dpi=150)
except ImportError:
    print('Matplotlib unavailable; JSON and WAV evidence generated.')
print(json.dumps(result,indent=2))
print('AUDIO ANALYSIS PASSED')
