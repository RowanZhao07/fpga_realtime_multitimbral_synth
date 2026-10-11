"""Export actual RTL chord captures for listening; never a board recording."""
from pathlib import Path
import json
import wave

import numpy as np

root = Path(__file__).resolve().parents[1]
out = root / 'sim/output'
out.mkdir(exist_ok=True)
fs = 50_000_000 / 1024
triad_length = 24414 + 5000


def write_wav(name, samples):
    # A single fixed listening gain for every tone and both revisions. No AGC.
    boosted = samples.astype(np.int64) * 4
    assert np.max(np.abs(boosted)) < 32767, 'Listening export would clip'
    with wave.open(str(out / name), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(round(fs))
        w.writeframes(boosted.astype('<i2').tobytes())


def inspect(path, revision):
    data = np.loadtxt(path, delimiter=',', dtype=np.int64)
    # Capture the full final release for sustained presets in both revisions.
    musical_length = 4 * triad_length + 7000
    capture_length = musical_length + 2 * (16000 + 12000)
    report = []
    comparison = []
    names = ('sine', 'epiano', 'strings', 'metal') if revision == 'after' else ('sine', 'square', 'saw', 'metal')
    for tone, name in enumerate(names):
        samples = data[data[:, 0] == tone, 1]
        assert len(samples) == capture_length, (tone, len(samples))
        assert np.max(np.abs(samples)) < 32767, 'RTL output clipped'
        assert np.all(samples[-100:] == 0), 'Final chord did not release'
        musical = samples[:musical_length]
        assert np.all(musical[-100:] == 0), 'Listening excerpt truncated a release tail'
        write_wav(f'chords_{revision}_{name}.wav', musical)
        comparison.append(musical)
        comparison.append(np.zeros(round(fs * .3), dtype=np.int64))
        # Confirm that C4, E4 and G4 survive a three-note chord for every tone.
        segment = samples[6000:24000].astype(float)
        freqs = np.fft.rfftfreq(len(segment), 1 / fs)
        magnitudes = np.abs(np.fft.rfft(segment * np.hanning(len(segment))))
        for target in (261.625565, 329.627557, 391.995436):
            peak = magnitudes[np.abs(freqs - target) < 7].max()
            assert peak > magnitudes.max() * .3, (revision, name, target)
        report.append({'tone': name, 'peak_pcm16': int(np.abs(samples).max()),
                       'triad_rms_pcm16': float(np.sqrt(np.mean(segment**2)))})
    write_wav(f'chords_{revision}_four_tones.wav', np.concatenate(comparison))
    return report


result = {'evidence': 'RTL simulation, not physical speaker recording',
          'sample_rate_hz': fs, 'wav_playback_gain': 4,
          'tone_order_after': ['sine', 'epiano', 'strings', 'metal'],
          'tone_order_before': ['sine', 'square', 'saw', 'metal'],
          'final_release_samples': 12000,
          'chord_order': ['C4 E4 G4', 'F4 A4 C5', 'G4 B4 D4', 'A4 C5 E4'],
          'after': inspect(root / 'sim/chord_samples.csv', 'after')}
before = out / 'chord_samples_before.csv'
if before.exists():
    result['before'] = inspect(before, 'before')
(out / 'chord_analysis.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
print(json.dumps(result, indent=2))
print('CHORD ANALYSIS PASSED')
