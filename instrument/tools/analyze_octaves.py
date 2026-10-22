"""Check octave pitch from actual RTL PCM, independently of DDS constants."""
from pathlib import Path
import json
import wave
import numpy as np

root = Path(__file__).resolve().parents[1]
out = root / 'sim/output'
data = np.loadtxt(out / 'octaves.csv', delimiter=',', skiprows=1, dtype=np.int64)
fs = 50_000_000 / 1024
results, clips = [], []
for octave in range(3, 7):
    for key, semitone in enumerate((0, 1, 9, 12)):
        pcm = data[(data[:, 0] == octave) & (data[:, 1] == key), 3].astype(float)
        assert len(pcm) == 8192
        target = 440 * 2 ** ((12 * (octave + 1) + semitone - 69) / 12)
        magnitude = np.abs(np.fft.rfft((pcm - pcm.mean()) * np.hanning(len(pcm))))
        peak = int(np.argmax(magnitude[1:]) + 1)
        a, b, c = np.log(np.maximum(magnitude[peak-1:peak+2], 1e-12))
        offset = .5 * (a - c) / (a - 2*b + c)
        frequency = (peak + offset) * fs / len(pcm)
        assert abs(frequency - target) < .25, (octave, key, frequency, target)
        rms = float(np.sqrt(np.mean(pcm * pcm)))
        assert rms > 100 and np.max(np.abs(pcm)) < 32767
        results.append(dict(octave=octave, semitone=semitone, target_hz=target,
                            measured_hz=float(frequency), error_hz=float(frequency-target), rms=rms))
        clips.extend((pcm.astype('<i2'), np.zeros(round(fs*.05), dtype='<i2')))
record = dict(evidence_type='RTL PCM simulation, not physical recording',
              sample_rate_hz=fs, measured_notes=results, checks_passed=True)
(out / 'octave_analysis.json').write_text(json.dumps(record, indent=2)+'\n', encoding='utf-8')
with wave.open(str(out / 'octaves_3_to_6.wav'), 'wb') as wav:
    wav.setnchannels(1); wav.setsampwidth(2); wav.setframerate(round(fs))
    wav.writeframes(np.concatenate(clips).tobytes())
print(f'OCTAVE AUDIO ANALYSIS PASSED: {len(results)} PCM pitches; maximum error '
      f'{max(abs(r["error_hz"]) for r in results):.6f} Hz')
