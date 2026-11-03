"""Check synthesized RTL click captures and export listenable WAV files."""
from pathlib import Path
import json
import wave
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
FS = 50_000_000 / 1024
OUT = ROOT / "outputs/metronome-louder"


def save_wav(path, samples):
    # Preserve the actual PCM amplitude; only change the container sample rate.
    target = np.arange(round(len(samples) * 48000 / FS)) * FS / 48000
    audio = np.rint(np.interp(target, np.arange(len(samples)), samples)).astype("<i2")
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(48000)
        wav.writeframes(audio.tobytes())


def main():
    data = np.loadtxt(ROOT / "instrument/sim/metronome_audio.csv", delimiter=",", skiprows=1, dtype=np.int64)
    OUT.mkdir(parents=True, exist_ok=True)
    report = {"source": "RTL metronome_audio, master 4096, no hardware recording", "sample_rate": FS, "meters": {}}
    combined = []
    for meter, name, counts, accents in [(3, "4_4", 8, [2, 0, 1, 0]), (4, "6_8", 12, [2, 0, 0, 1, 0, 0])]:
        part = data[(data[:, 0] == meter) & (data[:, 1] == 120)]
        ticks = np.flatnonzero(part[:, 4])
        assert len(ticks) == counts + 1, (name, len(ticks))
        intervals = np.diff(part[ticks, 2])
        ideal = FS * 60 / (120 * (3 if meter == 4 else 1))
        assert np.max(np.abs(intervals - ideal)) <= 1
        assert part[ticks, 5].tolist() == [accents[i % len(accents)] for i in range(counts + 1)]
        click_profiles = {}
        for accent, frequency in [(0, 1200), (1, 1600), (2, 2000)]:
            start = next(i for i in ticks[:-1] if part[i, 5] == accent)
            signal = part[start:start + 600, 3].astype(float)
            magnitudes = np.abs(np.fft.rfft(signal * np.hanning(len(signal)), n=16384))
            freq = np.fft.rfftfreq(16384, 1 / FS)
            measured = float(freq[np.argmax(magnitudes)])
            assert abs(measured - frequency) < 80, (accent, measured)
            click_profiles[str(accent)] = {"peak": int(np.max(np.abs(signal))), "frequency_hz": round(measured, 2)}
        assert click_profiles["2"]["peak"] > click_profiles["1"]["peak"] > click_profiles["0"]["peak"]
        audio = part[ticks[0]:ticks[-1], 3]
        assert 9000 < np.max(np.abs(audio)) < 15000
        save_wav(OUT / f"metronome_{name}_120bpm.wav", audio)
        combined.extend([audio, np.zeros(round(FS * .4))])
        report["meters"][name] = {"bpm": 120, "duration_s": len(audio) / FS,
            "interval_samples": sorted(set(intervals.tolist())), "accent_order": accents, "clicks": click_profiles}
    save_wav(OUT / "metronome_4_4_then_6_8.wav", np.concatenate(combined))
    (OUT / "audio_validation.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
