"""Check RTL-decoded stereo captures and export eight auditable listening clips."""
from pathlib import Path
import json
import math
import wave
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
FS = 48828.125
NAMES = ("sine", "epiano", "strings", "metal", "flute", "organ", "pluck", "bass")


def write_wav(path, pcm):
    # WAV stores an integer sample rate; resample from the actual RTL rate.
    times = np.arange(math.floor(len(pcm) * 48000 / FS)) * FS / 48000
    converted = np.interp(times, np.arange(len(pcm)), pcm)
    with wave.open(str(path), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(48000)
        f.writeframes(np.rint(converted).astype("<i2").tobytes())


def main():
    data = np.loadtxt(ROOT / "instrument/sim/i2s_audio_samples.csv", delimiter=",", dtype=np.int64)
    assert np.array_equal(data[:, 1], data[:, 2]), "Decoded DAC samples differ from core PCM"
    destination = ROOT / "outputs/eight-timbres"
    destination.mkdir(parents=True, exist_ok=True)
    checks, preview, fingerprints = [], [], []
    for tone, name in enumerate(NAMES):
        pcm = data[data[:, 0] == tone, 2]
        assert len(pcm) >= 19990, (name, "incomplete capture", len(pcm))
        peak = int(np.max(np.abs(pcm)))
        assert 20000 < peak < 32767, (name, "silent/quiet/overflowed", peak)
        assert np.max(np.abs(pcm[-512:])) == 0, (name, "release did not settle")
        # Settled C4 window; interpolation of the FFT peak checks pitch, not just activity.
        segment = pcm[2048:6144].astype(float)
        spectrum = np.abs(np.fft.rfft(segment * np.hanning(len(segment))))
        fundamental = 261.625565
        center = round(fundamental * len(segment) / FS)
        bin_index = center - 2 + int(np.argmax(spectrum[center-2:center+3]))
        a, b, c = np.log(np.maximum(spectrum[bin_index-1:bin_index+2], 1e-12))
        frequency = (bin_index + .5*(a-c)/(a-2*b+c)) * FS / len(segment)
        assert abs(frequency - fundamental) < 2.0, (name, "pitch error", frequency)
        rms = float(np.sqrt(np.mean(segment**2)))
        fingerprints.append(segment / rms)
        filename = f"T{tone}_{name}.wav"
        write_wav(destination / filename, pcm)
        preview.extend((pcm, np.zeros(round(.18*FS))))
        checks.append(dict(tone=tone, name=name, samples=len(pcm), peak_pcm16=peak,
                           fundamental_hz=frequency, hold_rms_pcm16=rms, wav=filename))
    # Detect a bank/address-width error that aliases T4..T7 to T0..T3.
    for a in range(8):
        for b in range(a):
            distance = float(np.sqrt(np.mean((fingerprints[a]-fingerprints[b])**2)))
            assert distance > .025, (a, b, "indistinguishable captured waveforms", distance)
    write_wav(destination / "eight_timbres_C4.wav", np.concatenate(preview))
    report = dict(evidence="RTL simulation: actual I2S pins decoded; not a PCM5102 analog capture",
                  sample_rate_hz=FS, wav_sample_rate_hz=48000,
                  controls="C4, V4096, effects off, no pressure attenuation, 8000 held frames then release",
                  order=list(NAMES), passed=True, checks=checks)
    (destination / "audio_validation.json").write_text(json.dumps(report, indent=2)+"\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
