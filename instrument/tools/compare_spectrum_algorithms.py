"""Reproducible arithmetic/resource exploration; not an FPGA timing benchmark.

The packed-real FFT is a floating-point algorithm prototype only. Production RTL
remains the verified 4096-point Hann FFT until fixed-point/P&R evidence exists.
"""
import argparse
import json
from pathlib import Path
import numpy as np

FS = 50_000_000 / 1024


def packed_real_fft(x):
    """N real samples -> N/2 complex FFT -> conjugate-pair postprocessing."""
    n = len(x)
    z = np.fft.fft(x[::2] + 1j*x[1::2])
    k = np.arange(n//2 + 1)
    a, b = z[k % (n//2)], z[-k % (n//2)].conjugate()
    return (a+b)/2 - .5j*np.exp(-2j*np.pi*k/n)*(a-b)


def goertzel_power(x, frequencies):
    """Floating-point fixed-frequency energy prototype (not a tone classifier)."""
    coefficient = 2*np.cos(2*np.pi*np.asarray(frequencies)/FS)
    s1, s2 = np.zeros_like(coefficient), np.zeros_like(coefficient)
    for sample in x:
        s0 = sample+coefficient*s1-s2
        s2, s1 = s1, s0
    return np.maximum(0, s1*s1+s2*s2-coefficient*s1*s2)


def report():
    rng = np.random.default_rng(20261031)
    tests = {}
    for name, x in {
        "silence": np.zeros(4096), "dc": np.ones(4096),
        "nyquist": (-1.)**np.arange(4096),
        "random": rng.normal(size=4096),
        "two_tones": np.sin(2*np.pi*261.625565*np.arange(4096)/FS)
                     + .5*np.sin(2*np.pi*293.664768*np.arange(4096)/FS),
    }.items():
        # Same symmetric Hann convention as generate_visual_tables.py.
        x = x*(.5-.5*np.cos(2*np.pi*np.arange(4096)/4095))
        error = float(np.max(np.abs(packed_real_fft(x)-np.fft.rfft(x))))
        if error > 1e-9:
            raise AssertionError((name, error))
        tests[name] = {"max_absolute_complex_error": error}
    targets = 440*2**((np.array([60,62,64,65,67,69,71,72])-69)/12)
    t = np.arange(4096)/FS
    probe = (np.sin(2*np.pi*targets[0]*t)+.5*np.sin(2*np.pi*targets[4]*t))*np.hanning(4096)
    direct = np.abs(np.exp(-2j*np.pi*targets[:,None]*t) @ probe)**2
    powers = goertzel_power(probe, targets)
    goertzel_error = float(np.max(np.abs(powers-direct))/np.max(direct))
    if goertzel_error > 1e-8:
        raise AssertionError(goertzel_error)
    rows = []
    for n in (1024, 2048, 4096, 8192):
        butterflies = n//2*int(np.log2(n))
        rows.append({"n": n, "capture_ms": n/FS*1000, "bin_hz": FS/n,
                     "hann_null_to_null_hz": 4*FS/n,
                     "complex_work_ram_bits_at_16bit": 2*n*16,
                     "radix2_butterflies": butterflies,
                     "current_fsm_compute_ms": (10*butterflies+2048)/50_000})
    return {
        "evidence_kind": "algorithm prototype and source-derived arithmetic, not board measurement",
        "sample_rate_hz": FS, "audio_path_waits_for_fft": False,
        "production": {"transform": "4096 complex radix-2 DIT, real input, symmetric Hann",
                       "published_bins": 512, "last_display_bin_hz": 511*FS/4096,
                       "capture_ms": 4096/FS*1000,
                       "butterfly_ms": 24576*10/50_000,
                       "note": "Separate scope buffer; FFT publication also waits for vertical blank."},
        "size_tradeoff": rows,
        "packed_real_4096_prototype": {
            "complex_fft_n": 2048, "working_ram_bits": 65536,
            "complex_fft_butterflies": 11264,
            "first_512_bins_real_multiplies_upper_bound": 11264*4+512*4,
            "current_4096_real_multiplies_upper_bound": 24576*4,
            "caveat": "Excludes Hann multiplies; general complex multiplication counts, no trivial-twiddle optimization. Extra pair-read/control logic required. No RTL area/timing claim.",
            "golden_equivalence": tests},
        "goertzel": {"8_targets_recurrence_multiplies": 8*4096,
                     "49_targets_recurrence_multiplies": 49*4096,
                     "512_targets_recurrence_multiplies": 512*4096,
                     "8_frequency_power_error_relative_to_largest_dft_power": goertzel_error,
                     "caveat": "Terminal magnitude arithmetic omitted. Suitable for a few fixed test tones, not a wholesale 512-bin spectrum replacement; the observation window still limits separation."},
        "decimated_fft": {"decimation": 4, "n": 1024,
                          "capture_ms": 4096/FS*1000, "bin_hz": FS/4096,
                          "nyquist_hz": FS/8,
                          "caveat": "Needs an anti-alias filter; 6 kHz display leaves only ~103.5 Hz to Nyquist, so it is not a free 4x simplification."},
        "decision": "Retain production FFT for this expression/effects release. Prefer a packed-real FFT as the next RTL optimization; use Goertzel only as an additional narrow test-tone meter."
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report(), indent=2), encoding="utf-8")
    print(f"PASS: packed-real FFT/rFFT on 5 signals and 8-frequency Goertzel/direct DFT energy; report: {args.output}")
