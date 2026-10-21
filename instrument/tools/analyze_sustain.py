"""Validate and render actual RTL PCM with identical gain for both examples."""
from pathlib import Path
import json
import wave
import numpy as np

OUT = Path(__file__).resolve().parents[1] / "sim" / "output"
FS = 50_000_000 / 1024

def main():
    data = np.loadtxt(OUT / "sustain.csv", delimiter=",", skiprows=1)
    dry, wet = data[:, 1], data[:, 2]
    assert len(data) == 195312
    assert np.isfinite(data).all()
    def rms(x, start, end):
        y = x[int(start * FS):int(end * FS)]
        return float(np.sqrt(np.mean(y * y)))
    # Both paths are identical before the pedal is engaged.
    assert np.array_equal(dry[:3906], wet[:3906])
    dry_tail, wet_tail = rms(dry, .43, .55), rms(wet, .43, .55)
    assert wet_tail > 100 and wet_tail > 10 * max(dry_tail, 1), (dry_tail, wet_tail)
    # Pedal up must finish tails; a later empty pedal press must stay silent.
    assert np.max(np.abs(dry[int(2.7*FS):])) == 0
    assert np.max(np.abs(wet[int(2.7*FS):])) == 0
    peak = float(max(np.max(np.abs(dry)), np.max(np.abs(wet))))
    assert 0 < peak < 32767
    def save(name, values):
        with wave.open(str(OUT / name), "wb") as f:
            f.setnchannels(1); f.setsampwidth(2); f.setframerate(round(FS))
            f.writeframes(values.astype("<i2").tobytes())
    # No separate normalization: amplitude differences remain measurable.
    save("sustain_off.wav", dry)
    save("sustain_on.wav", wet)
    save("sustain_comparison.wav", np.concatenate([dry, np.zeros(round(FS/2)), wet]))
    report = dict(source="RTL polyphonic_engine + audio_output, T1, echo off",
                  sample_rate_exact=FS, wav_sample_rate=round(FS), samples=len(data),
                  common_gain=1, peak_pcm=peak, dry_tail_rms=dry_tail,
                  sustain_tail_rms=wet_tail, silent_after_seconds=2.7,
                  comparison_order="off, 0.5 second silence, on")
    (OUT / "sustain_analysis.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report))

if __name__ == "__main__":
    main()
