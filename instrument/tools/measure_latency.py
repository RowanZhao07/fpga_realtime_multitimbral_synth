"""Measure contact-reference -> analog DAC onset from simultaneous scope CSV.

Columns: time_s,trigger_v,audio_v. No synthetic or digital-only trace constitutes
board verification. Run each timbre/key/load separately; record scope metadata.
"""
import argparse
import csv
import json
import math
import statistics
from pathlib import Path


def measure(rows, trigger_v=1.5, threshold_v=0.01, noise_factor=8.0,
            baseline_ms=2.0, window_ms=100.0, persistence_us=20.0):
    if len(rows) < 3 or any(not all(math.isfinite(v) for v in r) for r in rows):
        raise ValueError("Need finite time_s,trigger_v,audio_v samples")
    if any(rows[i][0] <= rows[i-1][0] for i in range(1, len(rows))):
        raise ValueError("time_s must increase strictly; concatenate captures as separate runs")
    if min(threshold_v, baseline_ms, window_ms, persistence_us) <= 0 or noise_factor < 1:
        raise ValueError("Threshold and timing settings must be positive")
    dt = statistics.median(rows[i][0]-rows[i-1][0] for i in range(1, len(rows)))
    if max(rows[i][0]-rows[i-1][0] for i in range(1, len(rows))) > 2*dt:
        raise ValueError("Capture contains gaps larger than two sample intervals")
    edges = [i for i in range(1, len(rows)) if rows[i-1][1] < trigger_v <= rows[i][1]]
    if not edges:
        raise ValueError("No rising contact-reference edges")
    result = []
    for number, start in enumerate(edges):
        t0 = rows[start][0]
        baseline = [r[2] for r in rows[:start] if r[0] >= t0-baseline_ms/1000]
        if len(baseline) < max(5, int(baseline_ms/1000/dt)*0.8):
            raise ValueError("Insufficient pre-trigger baseline")
        dc = statistics.median(baseline)
        noise = math.sqrt(sum((v-dc)**2 for v in baseline)/len(baseline))
        threshold = max(threshold_v, noise_factor*noise)
        if max(abs(v-dc) for v in baseline) >= threshold:
            raise ValueError("Pre-trigger audio is not quiet; release notes/echo and capture again")
        end = min(t0+window_ms/1000, rows[edges[number+1]][0] if number+1 < len(edges) else rows[-1][0])
        consecutive = None
        onset = None
        for t, _, audio in rows[start:]:
            if t > end:
                break
            if abs(audio-dc) >= threshold:
                if consecutive is None:
                    consecutive = t
                if t-consecutive >= persistence_us/1e6:
                    onset = consecutive
                    break
            else:
                consecutive = None
        result.append({"reference_s": t0, "latency_ms": None if onset is None else (onset-t0)*1000,
                       "threshold_v": threshold, "noise_rms_v": noise})
    delays = sorted(x["latency_ms"] for x in result if x["latency_ms"] is not None)
    complete = len(delays) == len(result)
    return {"measurement": "contact-reference to analog voltage threshold", "trials": result,
            "count": len(result), "missing_onsets": len(result)-len(delays),
            "sample_interval_us": dt*1e6,
            "min_ms": min(delays) if delays else None,
            "max_ms": max(delays) if delays else None,
            "p95_ms": delays[max(0, math.ceil(.95*len(delays))-1)] if delays else None,
            "peak_to_peak_ms": max(delays)-min(delays) if delays else None,
            "observed_le_10ms": complete and bool(delays) and max(delays)+dt*1000 <= 10,
            "observed_le_5ms": complete and bool(delays) and max(delays)+dt*1000 <= 5,
            "qualification": "Observed captures only; not proof of all phases, keys, timbres or zero jitter"}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("csv", type=Path)
    p.add_argument("--threshold-v", type=float, default=.01)
    p.add_argument("--trigger-v", type=float, default=1.5)
    p.add_argument("--window-ms", type=float, default=100)
    p.add_argument("--capture-kind", choices=["bench", "fixture"], required=True)
    p.add_argument("--notes", required=True, help="Scope/sample rate, FS hash, key, timbre, volume and load")
    p.add_argument("--output", type=Path)
    args = p.parse_args()
    with args.csv.open(encoding="utf-8-sig", newline="") as f:
        rows = [tuple(float(r[k]) for k in ("time_s", "trigger_v", "audio_v")) for r in csv.DictReader(f)]
    report = measure(rows, trigger_v=args.trigger_v, threshold_v=args.threshold_v, window_ms=args.window_ms)
    report.update(capture_kind=args.capture_kind, notes=args.notes, source=str(args.csv))
    text = json.dumps(report, ensure_ascii=False, indent=2)
    if args.output:
        args.output.write_text(text+"\n", encoding="utf-8")
    print(text)


if __name__ == "__main__":
    main()
