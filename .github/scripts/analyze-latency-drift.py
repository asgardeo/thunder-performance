#!/usr/bin/env python3
# Copyright (c) 2026, WSO2 LLC. (https://www.wso2.com).
#
# WSO2 LLC. licenses this file to you under the Apache License,
# Version 2.0 (the "License"); you may not use this file except
# in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied. See the License for the
# specific language governing permissions and limitations
# under the License.
#
# ----------------------------------------------------------------------------
# Analyze latency drift within each scenario of a long-running perf test.
#
# For every jtls.zip found under $RESULTS_DIR/results/, this reads all JMeter
# CSV JTLs inside, buckets requests into fixed-width time windows (default
# 5 min), and writes:
#   - <scenario>/latency-drift.csv  — per-bucket p50/p95/p99/count/error_rate
#   - <scenario>/latency-drift.png  — chart of p50/p95/p99 over time
# Also writes a top-level JSON summary at $RESULTS_DIR/latency-drift.json with
# per-scenario slope (ms/hour) of p95 and its R² — consumed by the job summary.
#
# Env:
#   RESULTS_DIR         - path to results-<n>/ (required)
#   BUCKET_SECONDS      - bucket width (default 300)
# ----------------------------------------------------------------------------

import csv
import glob
import io
import json
import math
import os
import statistics
import sys
import zipfile
from collections import defaultdict
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

RESULTS_DIR = os.environ.get("RESULTS_DIR")
BUCKET_SECONDS = int(os.environ.get("BUCKET_SECONDS", "300"))

if not RESULTS_DIR:
    print("ERROR: RESULTS_DIR must be set.", file=sys.stderr)
    sys.exit(1)


def percentile(sorted_values, p):
    """Nearest-rank percentile on a pre-sorted list."""
    if not sorted_values:
        return 0.0
    k = max(0, min(len(sorted_values) - 1, int(math.ceil(p / 100.0 * len(sorted_values))) - 1))
    return sorted_values[k]


def linear_regression(xs, ys):
    """Return (slope, intercept, r_squared) for y = slope*x + intercept."""
    n = len(xs)
    if n < 2:
        return 0.0, 0.0, 0.0
    mean_x = sum(xs) / n
    mean_y = sum(ys) / n
    num = sum((x - mean_x) * (y - mean_y) for x, y in zip(xs, ys))
    den = sum((x - mean_x) ** 2 for x in xs)
    if den == 0:
        return 0.0, mean_y, 0.0
    slope = num / den
    intercept = mean_y - slope * mean_x
    ss_res = sum((y - (slope * x + intercept)) ** 2 for x, y in zip(xs, ys))
    ss_tot = sum((y - mean_y) ** 2 for y in ys)
    r_squared = 1 - (ss_res / ss_tot) if ss_tot > 0 else 0.0
    return slope, intercept, r_squared


def analyze_jtl_rows(rows):
    """Bucket rows by BUCKET_SECONDS window and compute per-bucket stats.
    Rows: iterable of (timestamp_ms:int, elapsed_ms:int, success:bool).
    Returns list of dicts (one per bucket, chronological)."""
    buckets = defaultdict(lambda: {"elapsed": [], "count": 0, "errors": 0})
    for ts_ms, elapsed_ms, success in rows:
        bucket_key = (ts_ms // 1000) // BUCKET_SECONDS
        buckets[bucket_key]["elapsed"].append(elapsed_ms)
        buckets[bucket_key]["count"] += 1
        if not success:
            buckets[bucket_key]["errors"] += 1

    result = []
    for key in sorted(buckets.keys()):
        b = buckets[key]
        elapsed_sorted = sorted(b["elapsed"])
        bucket_start = key * BUCKET_SECONDS
        result.append({
            "bucket_start_epoch": bucket_start,
            "count": b["count"],
            "error_rate": (b["errors"] / b["count"]) if b["count"] else 0.0,
            "p50": percentile(elapsed_sorted, 50),
            "p95": percentile(elapsed_sorted, 95),
            "p99": percentile(elapsed_sorted, 99),
            "mean": statistics.mean(elapsed_sorted) if elapsed_sorted else 0.0,
        })
    return result


def rows_from_jtl_zip(zip_path):
    """Yield (ts_ms, elapsed_ms, success) tuples from every .jtl file inside a jtls.zip."""
    with zipfile.ZipFile(zip_path, "r") as zf:
        for name in zf.namelist():
            if not name.endswith(".jtl"):
                continue
            with zf.open(name) as f:
                text = io.TextIOWrapper(f, encoding="utf-8", errors="replace")
                yield from _rows_from_csv_reader(csv.DictReader(text))


def rows_from_raw_jtl(jtl_path):
    """Yield (ts_ms, elapsed_ms, success) tuples from a plain JMeter CSV JTL file.

    Fallback used when jtl-splitter didn't run so the post-warmup jtls.zip is
    missing but the raw results.jtl is present.
    """
    with open(jtl_path, "r", encoding="utf-8", errors="replace") as f:
        yield from _rows_from_csv_reader(csv.DictReader(f))


def _rows_from_csv_reader(reader):
    for row in reader:
        try:
            ts_ms = int(row["timeStamp"])
            elapsed_ms = int(row["elapsed"])
            success = row.get("success", "").lower() == "true"
        except (ValueError, KeyError):
            continue
        yield ts_ms, elapsed_ms, success


def find_scenario_sources(results_root):
    """Return list of (scenario_name, source_path, source_type) tuples.

    Prefers jtls.zip (post-splitter, warmup-trimmed). Falls back to raw
    results.jtl for scenarios where jtl-splitter didn't run — the raw JTL
    includes warmup data, so bucketed metrics for the first warmup window
    will be less representative.
    """
    sources = []
    seen_dirs = set()

    zip_paths = sorted(glob.glob(f"{results_root}/results/**/jtls.zip", recursive=True))
    for zp in zip_paths:
        seen_dirs.add(str(Path(zp).parent))
        rel = Path(zp).relative_to(Path(results_root) / "results")
        name = str(rel.parent) if str(rel.parent) not in (".", "") else Path(zp).stem
        sources.append((name, zp, "zip"))

    raw_paths = sorted(glob.glob(f"{results_root}/results/**/results.jtl", recursive=True))
    for rp in raw_paths:
        if str(Path(rp).parent) in seen_dirs:
            continue
        rel = Path(rp).relative_to(Path(results_root) / "results")
        name = str(rel.parent) if str(rel.parent) not in (".", "") else Path(rp).stem
        sources.append((name, rp, "raw"))

    return sources


def write_csv(path, buckets):
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["bucket_start_epoch", "count", "error_rate", "p50_ms", "p95_ms", "p99_ms", "mean_ms"])
        for b in buckets:
            w.writerow([b["bucket_start_epoch"], b["count"], f"{b['error_rate']:.4f}",
                        b["p50"], b["p95"], b["p99"], f"{b['mean']:.2f}"])


def plot_scenario(scenario_name, buckets, png_path):
    if len(buckets) < 2:
        return
    # x-axis: minutes elapsed from first bucket
    x0 = buckets[0]["bucket_start_epoch"]
    xs = [(b["bucket_start_epoch"] - x0) / 60.0 for b in buckets]
    p50s = [b["p50"] for b in buckets]
    p95s = [b["p95"] for b in buckets]
    p99s = [b["p99"] for b in buckets]

    fig, ax = plt.subplots(figsize=(10, 5))
    ax.plot(xs, p50s, label="p50", linewidth=1.2)
    ax.plot(xs, p95s, label="p95", linewidth=1.5)
    ax.plot(xs, p99s, label="p99", linewidth=1.2, alpha=0.7)
    ax.set_xlabel("Elapsed (minutes)")
    ax.set_ylabel("Response time (ms)")
    ax.set_title(f"Latency drift: {scenario_name}")
    ax.legend()
    ax.grid(True, alpha=0.3)
    fig.tight_layout()
    fig.savefig(png_path, dpi=100)
    plt.close(fig)


def slope_for_p95(buckets):
    """Compute p95 slope in ms/hour and R² of the fit."""
    if len(buckets) < 2:
        return 0.0, 0.0
    # Regress p95 against elapsed hours from t0
    x0 = buckets[0]["bucket_start_epoch"]
    xs = [(b["bucket_start_epoch"] - x0) / 3600.0 for b in buckets]  # hours
    ys = [b["p95"] for b in buckets]
    slope, _, r2 = linear_regression(xs, ys)
    return slope, r2


def main():
    sources = find_scenario_sources(RESULTS_DIR)
    if not sources:
        print(f"No jtls.zip or results.jtl found under {RESULTS_DIR}/results/. Nothing to analyze.")
        return

    summary = {"bucket_seconds": BUCKET_SECONDS, "scenarios": []}

    for scenario_name, source_path, source_type in sources:
        print(f"Analyzing {scenario_name} ({source_type}) → {source_path}")
        try:
            if source_type == "zip":
                rows_iter = rows_from_jtl_zip(source_path)
            else:
                rows_iter = rows_from_raw_jtl(source_path)
            buckets = analyze_jtl_rows(rows_iter)
        except (zipfile.BadZipFile, OSError) as e:
            print(f"  WARN: could not read {source_path}: {e}")
            continue

        if not buckets:
            print(f"  WARN: no valid rows in {source_path}")
            continue

        # Write outputs OUTSIDE results/ so they survive the collect script's cleanup.
        out_dir = Path(RESULTS_DIR) / "latency-drift" / scenario_name
        out_dir.mkdir(parents=True, exist_ok=True)
        csv_path = out_dir / "latency-drift.csv"
        png_path = out_dir / "latency-drift.png"
        write_csv(csv_path, buckets)
        try:
            plot_scenario(scenario_name, buckets, png_path)
        except Exception as e:
            print(f"  WARN: could not plot {scenario_name}: {e}")

        slope_ms_per_hour, r_squared = slope_for_p95(buckets)
        summary["scenarios"].append({
            "scenario": scenario_name,
            "source_type": source_type,
            "buckets": len(buckets),
            "total_requests": sum(b["count"] for b in buckets),
            "p95_slope_ms_per_hour": round(slope_ms_per_hour, 3),
            "p95_r_squared": round(r_squared, 4),
            "p95_first_bucket_ms": buckets[0]["p95"],
            "p95_last_bucket_ms": buckets[-1]["p95"],
        })
        print(f"  → {len(buckets)} buckets, p95 slope = {slope_ms_per_hour:+.2f} ms/hour (R²={r_squared:.3f})")

    summary_path = Path(RESULTS_DIR) / "latency-drift.json"
    with open(summary_path, "w") as f:
        json.dump(summary, f, indent=2)
    print(f"Wrote {summary_path}")


if __name__ == "__main__":
    main()
