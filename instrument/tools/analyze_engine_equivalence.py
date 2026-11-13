"""Summarize the fixed-seed RTL equivalence traces; keep raw CSVs alongside them."""

import argparse
import csv
import hashlib
import json
from pathlib import Path


SCENARIOS = {0: "idle", 1: "solo", 2: "dense_retrigger", 3: "random_controls",
             4: "release_to_silence", 5: "reset_restart"}
ROOT = Path(__file__).resolve().parents[2]


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def summarize(path):
    with path.open(newline="", encoding="utf-8") as handle:
        rows = [{key: int(value) for key, value in row.items()} for row in csv.DictReader(handle)]
    if len(rows) != 13496 or [r["frame"] for r in rows] != list(range(len(rows))):
        raise ValueError(f"Incomplete or unordered trace: {path}")
    if any(r["optimized_pcm"] != r["baseline_pcm"] for r in rows):
        raise ValueError(f"PCM mismatch: {path}")
    if any(not 0 < r["optimized_clocks"] <= min(600, r["baseline_clocks"]) for r in rows):
        raise ValueError(f"Deadline regression: {path}")
    if max(r["voices"] for r in rows) != 32 or max(r["baseline_clocks"] for r in rows) != 829:
        raise ValueError(f"Missing dense workload: {path}")
    groups = []
    for number, name in SCENARIOS.items():
        group = [row for row in rows if row["scenario"] == number]
        if not group:
            raise ValueError(f"Missing scenario {name}: {path}")
        groups.append({"scenario": name, "frames": len(group),
                       "optimized_clocks_min": min(r["optimized_clocks"] for r in group),
                       "optimized_clocks_max": max(r["optimized_clocks"] for r in group),
                       "baseline_clocks_min": min(r["baseline_clocks"] for r in group),
                       "baseline_clocks_max": max(r["baseline_clocks"] for r in group)})
    return {"trace": path.name, "sha256": sha256(path), "frames": len(rows),
            "pcm_mismatches": 0, "full_pool_frames": sum(r["voices"] == 32 for r in rows),
            "scenarios": groups}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, default=ROOT / "instrument/sim/output")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    runs = [summarize(args.directory / f"engine_equivalence_{mode}.csv")
            for mode in ("legacy", "expression")]
    inputs = ["instrument/src/polyphonic_engine.v", "instrument/src/envelope_adsr.v",
              "instrument/src/timbre_lut.v", "instrument/src/note_frequency.v",
              "instrument/sim/reference/polyphonic_engine_reference.v",
              "instrument/sim/tb_engine_equivalence.sv"]
    report = {"baseline_commit": "72ef46a", "frame_budget_clocks": 1024,
              "simulation_clock_hz": 50000000, "seed": "0x71e0cafe",
              "hardware_validated": False, "total_compared_frames": sum(r["frames"] for r in runs),
              "runs": runs, "inputs": {p: sha256(ROOT / p) for p in inputs}}
    output = args.output or args.directory / "engine_equivalence_summary.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"PASS: {report['total_compared_frames']} matching PCM frames; summary: {output}")


if __name__ == "__main__":
    main()
