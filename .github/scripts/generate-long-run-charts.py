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
# Read $RESULTS_DIR/long-run-metrics.csv (produced by long-run-sampler.sh on
# the bastion during the test) and emit PNGs + a JSON summary of trends.
#
# Charts written to $RESULTS_DIR/long-run/*.png. Summary written to
# $RESULTS_DIR/long-run-summary.json. Slopes are per-hour, over the full
# run duration.
# ----------------------------------------------------------------------------

import csv
import json
import os
import sys
from datetime import datetime
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

RESULTS_DIR = os.environ.get("RESULTS_DIR")
if not RESULTS_DIR:
    print("ERROR: RESULTS_DIR must be set.", file=sys.stderr)
    sys.exit(1)

CSV_PATH = Path(RESULTS_DIR) / "long-run-metrics.csv"
OUT_DIR = Path(RESULTS_DIR) / "long-run"
SUMMARY_PATH = Path(RESULTS_DIR) / "long-run-summary.json"

if not CSV_PATH.is_file():
    print(f"No {CSV_PATH} — sampler didn't run for this trigger. Skipping long-run analysis.")
    sys.exit(0)

OUT_DIR.mkdir(parents=True, exist_ok=True)


def parse_int(s):
    s = (s or "").strip()
    if not s:
        return None
    try:
        return int(s)
    except ValueError:
        return None


def linear_regression(xs, ys):
    """Return (slope, intercept, r_squared) for y = slope*x + intercept."""
    xs = [x for x, y in zip(xs, ys) if y is not None]
    ys = [y for y in ys if y is not None]
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


# ---- Load rows ----
timestamps = []
data = {}   # column name -> [values (int or None)]
header = None

with open(CSV_PATH, newline="") as f:
    reader = csv.reader(f)
    header = next(reader)
    for col in header:
        data[col] = []
    for row in reader:
        if len(row) != len(header):
            continue
        # Parse timestamp
        try:
            ts = datetime.strptime(row[0], "%Y-%m-%dT%H:%M:%SZ")
        except ValueError:
            continue
        timestamps.append(ts)
        for col, val in zip(header[1:], row[1:]):
            data.setdefault(col, []).append(parse_int(val))

n_rows = len(timestamps)
if n_rows < 2:
    print(f"Not enough sample rows in {CSV_PATH} ({n_rows}) — need at least 2. Skipping charts.")
    sys.exit(0)

# Elapsed hours from first sample (for slope units of "per hour")
t0 = timestamps[0]
xs_hours = [(t - t0).total_seconds() / 3600.0 for t in timestamps]


def plot_series(col, ylabel, title, unit_scale=1.0, unit_label=""):
    ys_raw = data.get(col, [])
    ys = [y * unit_scale if y is not None else None for y in ys_raw]
    if all(y is None for y in ys):
        return None
    ys_clean = [y if y is not None else float("nan") for y in ys]

    fig, ax = plt.subplots(figsize=(10, 4))
    ax.plot(xs_hours, ys_clean, linewidth=1.4)
    ax.set_xlabel("Elapsed (hours)")
    ax.set_ylabel(ylabel)
    ax.set_title(title)
    ax.grid(True, alpha=0.3)
    fig.tight_layout()
    out_path = OUT_DIR / f"{col}.png"
    fig.savefig(out_path, dpi=100)
    plt.close(fig)

    slope, _, r2 = linear_regression(xs_hours, ys)
    first_val = next((y for y in ys if y is not None), None)
    last_val = next((y for y in reversed(ys) if y is not None), None)
    return {
        "column": col,
        "unit": unit_label,
        "first": first_val,
        "last": last_val,
        "min": min((y for y in ys if y is not None), default=None),
        "max": max((y for y in ys if y is not None), default=None),
        "slope_per_hour": round(slope, 4),
        "r_squared": round(r2, 4),
        "png": str(out_path.relative_to(RESULTS_DIR)),
    }


summary = {
    "samples": n_rows,
    "duration_hours": round(xs_hours[-1], 3),
    "series": {},
}

# ---- Plot known-shape series ----
series_defs = [
    # column,                    ylabel,                        title,                              scale,       unit
    ("thunder_rss_kb",           "RSS (MB)",                    "Thunder process RSS over time",    1 / 1024.0,  "MB"),
    ("thunder_vsz_kb",           "VSZ (MB)",                    "Thunder process VSZ over time",    1 / 1024.0,  "MB"),
    ("thunder_disk_used_bytes",  "Disk used (GB)",              "Thunder host disk used over time", 1 / (1024**3), "GB"),
    ("thunder_disk_avail_bytes", "Disk available (GB)",         "Thunder host disk available",      1 / (1024**3), "GB"),
    ("thunder_log_bytes",        "Log size (MB)",               "Thunder log directory size",       1 / (1024**2), "MB"),
    ("runtimedb_bytes",          "runtimedb size (MB)",         "runtimedb size over time",         1 / (1024**2), "MB"),
]

for col, ylabel, title, scale, unit in series_defs:
    if col not in data:
        continue
    result = plot_series(col, ylabel, title, scale, unit)
    if result:
        summary["series"][col] = result

# ---- Row-count columns (variable set, all have "count_" prefix) ----
count_cols = [c for c in header if c.startswith("count_")]
for col in count_cols:
    result = plot_series(col, "Row count", f"{col.replace('count_', '')} row count over time",
                         unit_scale=1.0, unit_label="rows")
    if result:
        summary["series"][col] = result

with open(SUMMARY_PATH, "w") as f:
    json.dump(summary, f, indent=2)
print(f"Wrote {SUMMARY_PATH} with {len(summary['series'])} series over {summary['duration_hours']}h")
