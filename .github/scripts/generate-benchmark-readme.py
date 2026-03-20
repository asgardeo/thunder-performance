#!/usr/bin/env python3
"""Appends a summary table to the benchmark readme from the results summary.csv."""

import csv
import glob
import os
import sys

RESULTS_DIR = os.environ.get("GITHUB_WORKSPACE", "")
DEPLOYMENT = os.environ.get("DEPLOYMENT", "")
BENCHMARK_DIR_PATH = os.environ.get("BENCHMARK_DIR_PATH", "")

COLS = [
    "Scenario Name",
    "Heap Size",
    "Concurrent Users",
    "Label",
    "# Samples",
    "Error %",
    "Throughput (Requests/sec)",
    "Average Response Time (ms)",
    "95th Percentile of Response Time (ms)",
]

csvs = glob.glob(f"{RESULTS_DIR}/perf-scripts/{DEPLOYMENT}/results-*/summary.csv")
if not csvs:
    print("WARN: No summary.csv found — skipping summary table.")
    sys.exit(0)

rows = []
with open(csvs[0]) as f:
    for row in csv.DictReader(f):
        rows.append([row.get(c, "") for c in COLS])

if not rows:
    sys.exit(0)

md = "\n## Summary\n\n"
md += "| " + " | ".join(COLS) + " |\n"
md += "| " + " | ".join(["---"] * len(COLS)) + " |\n"
for row in rows:
    md += "| " + " | ".join(row) + " |\n"

with open(os.path.join(BENCHMARK_DIR_PATH, "readme.md"), "a") as f:
    f.write(md)
