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
# Writes the GitHub Actions job summary to $GITHUB_STEP_SUMMARY:
#   1. Metadata block
#   2. ## Summary table (from summary.csv)
#   3. ## CloudWatch Metrics tables (min / avg / max per metric, per node)
# ----------------------------------------------------------------------------

import csv
import glob
import json
import os
import sys
from collections import defaultdict
from datetime import datetime

WORKSPACE = os.environ.get("GITHUB_WORKSPACE", "")
DEPLOYMENT = os.environ.get("DEPLOYMENT", "")
BUILD_NUMBER = os.environ.get("BUILD_NUMBER", "")
TIMESTAMP = os.environ.get("TIMESTAMP", "")
THUNDER_PACK_URL = os.environ.get("THUNDER_PACK_URL", "")
THUNDER_INSTANCE_TYPE = os.environ.get("THUNDER_INSTANCE_TYPE", "")
NGINX_INSTANCE_TYPE = os.environ.get("NGINX_INSTANCE_TYPE", "")
BASTION_INSTANCE_TYPE = os.environ.get("BASTION_INSTANCE_TYPE", "")
DB_INSTANCE_TYPE = os.environ.get("DB_INSTANCE_TYPE", "")
DB_TYPE = os.environ.get("DB_TYPE", "")
CONCURRENCY = os.environ.get("CONCURRENCY", "")
BASTION_INSTANCE_ID = os.environ.get("BASTION_INSTANCE_ID", "")
NGINX_INSTANCE_ID = os.environ.get("NGINX_INSTANCE_ID", "")
THUNDER_INSTANCE_ID = os.environ.get("THUNDER_INSTANCE_ID", "")
RDS_INSTANCE_ID = os.environ.get("RDS_INSTANCE_ID", "")
GITHUB_SERVER_URL = os.environ.get("GITHUB_SERVER_URL", "")
GITHUB_REPOSITORY = os.environ.get("GITHUB_REPOSITORY", "")
GITHUB_REF_NAME = os.environ.get("GITHUB_REF_NAME", "")
REPO_REF = os.environ.get("REPO_REF", "")

SUMMARY_COLS = [
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

# Metric display config: metric_name -> (display_label, unit, scale_factor)
EC2_METRICS = [
    ("CPUUtilization",  "CPU Utilization",    "%",          1),
    ("NetworkIn",       "Network In",         "MB",         1 / 1_048_576),
    ("NetworkOut",      "Network Out",        "MB",         1 / 1_048_576),
    ("DiskReadOps",     "Disk Read Ops",      "ops/period", 1),
    ("DiskWriteOps",    "Disk Write Ops",     "ops/period", 1),
    ("DiskReadBytes",   "Disk Read",          "MB/period",  1 / 1_048_576),
    ("DiskWriteBytes",  "Disk Write",         "MB/period",  1 / 1_048_576),
]

RDS_METRICS = [
    ("CPUUtilization",              "CPU Utilization",        "%",       1),
    ("FreeableMemory",              "Freeable Memory",        "MB",      1 / 1_048_576),
    ("ReadIOPS",                    "Read IOPS",              "ops/sec", 1),
    ("WriteIOPS",                   "Write IOPS",             "ops/sec", 1),
    ("NetworkReceiveThroughput",    "Network Receive",        "MB/s",    1 / 1_048_576),
    ("NetworkTransmitThroughput",   "Network Transmit",       "MB/s",    1 / 1_048_576),
    ("DatabaseConnections",         "DB Connections",         "count",   1),
]

# EBS metrics are queried against AWS/EBS by VolumeId (5-min period).
# Values are aggregated across all volumes attached to the same instance;
# for single-volume instances this is exact, for multi-volume it's a mix.
EBS_METRICS = [
    ("VolumeReadOps",     "Volume Read Ops",       "ops/period", 1),
    ("VolumeWriteOps",    "Volume Write Ops",      "ops/period", 1),
    ("VolumeReadBytes",   "Volume Read",           "MB/period",  1 / 1_048_576),
    ("VolumeWriteBytes",  "Volume Write",          "MB/period",  1 / 1_048_576),
    ("VolumeQueueLength", "Volume Queue Length",   "requests",   1),
]


def read_csv_metrics(filepath):
    """Return {metric_name: [float, ...]} from a cloudwatch CSV.

    Works for both EC2/RDS CSVs (Timestamp,Metric,Average) and EBS CSVs
    (Timestamp,Metric,VolumeId,Average) — the extra column is ignored.
    """
    data = defaultdict(list)
    try:
        with open(filepath, newline="") as f:
            for row in csv.DictReader(f):
                try:
                    data[row["Metric"]].append(float(row["Average"]))
                except (ValueError, KeyError):
                    continue
    except FileNotFoundError:
        pass
    return data


def metrics_table(data, metric_defs):
    """Build a markdown table with min / avg / max for each metric."""
    lines = []
    lines.append("| Metric | Unit | Min | Avg | Max |\n")
    lines.append("| --- | --- | ---: | ---: | ---: |\n")
    for key, label, unit, scale in metric_defs:
        values = [v * scale for v in data.get(key, [])]
        if not values:
            lines.append(f"| {label} | {unit} | — | — | — |\n")
        else:
            mn  = round(min(values), 3)
            avg = round(sum(values) / len(values), 3)
            mx  = round(max(values), 3)
            lines.append(f"| {label} | {unit} | {mn} | {avg} | {mx} |\n")
    return "".join(lines)


summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
if not summary_path:
    print("WARN: GITHUB_STEP_SUMMARY not set — writing to stdout.", file=sys.stderr)
    summary_path = None

out = []

# ── Metadata block ─────────────────────────────────────────────────────────────
out.append(f"Build Number: {BUILD_NUMBER}\n")
out.append(f"\nBuild Date and Time: {TIMESTAMP}\n")
out.append(f"\nThunder Pack URL: {THUNDER_PACK_URL}\n")
out.append(f"\nDeployment Pattern: {DEPLOYMENT}\n")
out.append(f"\nThunder Instance Type: {THUNDER_INSTANCE_TYPE}\n")
out.append(f"\nNginx Instance Type: {NGINX_INSTANCE_TYPE}\n")
out.append(f"\nBastion Instance Type: {BASTION_INSTANCE_TYPE}\n")
out.append(f"\nDatabase Instance Type: {DB_INSTANCE_TYPE}\n")
out.append(f"\nDatabase Type: {DB_TYPE}\n")
out.append(f"\nConcurrency: {CONCURRENCY}\n")
out.append(f"\nThunder Instance ID: {THUNDER_INSTANCE_ID}\n")
out.append(f"\nNginx Instance ID: {NGINX_INSTANCE_ID}\n")
out.append(f"\nBastion Instance ID: {BASTION_INSTANCE_ID}\n")
out.append(f"\nRDS Instance ID: {RDS_INSTANCE_ID}\n")
out.append(f"\nPerformance Repo: {GITHUB_SERVER_URL}/{GITHUB_REPOSITORY}\n")
out.append(f"\nPipeline Definition Branch: {GITHUB_REF_NAME}\n")
out.append(f"\nCheckout Ref (code under test): {REPO_REF if REPO_REF else GITHUB_REF_NAME}\n")

# ── Performance summary table ──────────────────────────────────────────────────
csvs = glob.glob(f"{WORKSPACE}/perf-scripts/{DEPLOYMENT}/results-*/summary.csv")
if csvs:
    rows = []
    with open(csvs[0]) as f:
        for row in csv.DictReader(f):
            rows.append([row.get(c, "") for c in SUMMARY_COLS])
    if rows:
        out.append("\n## Summary\n\n")
        out.append("| " + " | ".join(SUMMARY_COLS) + " |\n")
        out.append("| " + " | ".join(["---"] * len(SUMMARY_COLS)) + " |\n")
        for row in rows:
            out.append("| " + " | ".join(row) + " |\n")
else:
    print("WARN: No summary.csv found — skipping summary table.", file=sys.stderr)

# ── CloudWatch Metrics tables ──────────────────────────────────────────────────
metrics_dirs = sorted(glob.glob(f"{WORKSPACE}/perf-scripts/{DEPLOYMENT}/results-*/cloudwatch"))
if metrics_dirs:
    metrics_dir = metrics_dirs[-1]
    out.append("\n## CloudWatch Metrics\n")

    ec2_nodes = [
        ("Thunder", "thunder-ec2.csv", "thunder-ebs.csv"),
        ("Nginx",   "nginx-ec2.csv",   "nginx-ebs.csv"),
        ("Bastion", "bastion-ec2.csv", "bastion-ebs.csv"),
    ]

    for label, ec2_file, ebs_file in ec2_nodes:
        ec2_data = read_csv_metrics(os.path.join(metrics_dir, ec2_file))
        ebs_data = read_csv_metrics(os.path.join(metrics_dir, ebs_file))
        if not any(ec2_data.values()) and not any(ebs_data.values()):
            continue
        out.append(f"\n### {label} (EC2)\n\n")
        if any(ec2_data.values()):
            out.append(metrics_table(ec2_data, EC2_METRICS))
        if any(ebs_data.values()):
            out.append(f"\n#### {label} (EBS volumes)\n\n")
            out.append(metrics_table(ebs_data, EBS_METRICS))

    rds_data = read_csv_metrics(os.path.join(metrics_dir, "rds.csv"))
    if any(rds_data.values()):
        out.append("\n### RDS\n\n")
        out.append(metrics_table(rds_data, RDS_METRICS))

# ── Long-run analysis ──────────────────────────────────────────────────────────
# Read the JSON summary produced by generate-long-run-charts.py. Absent if the
# sampler didn't run (older triggers or short tests).
lr_paths = sorted(glob.glob(f"{WORKSPACE}/perf-scripts/{DEPLOYMENT}/results-*/long-run-summary.json"))
if lr_paths:
    try:
        with open(lr_paths[-1]) as f:
            lr = json.load(f)
        out.append(f"\n## Long-run analysis\n\n")
        out.append(f"Duration: **{lr.get('duration_hours', 0)}h** across **{lr.get('samples', 0)}** samples.\n\n")
        out.append("| Metric | Unit | First | Last | Slope/hour | R² |\n")
        out.append("| --- | --- | ---: | ---: | ---: | ---: |\n")
        # Show host + DB series first (fixed shape), then dynamic count_* rows.
        ordered_series = (
            ["thunder_rss_kb", "thunder_vsz_kb", "thunder_disk_used_bytes",
             "thunder_disk_avail_bytes", "thunder_log_bytes", "runtimedb_bytes"]
            + sorted(k for k in lr.get("series", {}) if k.startswith("count_"))
        )
        for key in ordered_series:
            s = lr.get("series", {}).get(key)
            if not s:
                continue
            first = s.get("first"); last = s.get("last")
            slope = s.get("slope_per_hour"); r2 = s.get("r_squared")
            unit = s.get("unit", "")
            # For counts and byte-values, keep raw; the unit column tells the story.
            if first is not None and last is not None:
                # Scale for display: byte-columns to MB/GB via unit label already
                # accounts for it in the CSV; here we just pretty-print.
                first_str = f"{first:.3f}" if isinstance(first, float) else str(first)
                last_str  = f"{last:.3f}" if isinstance(last, float) else str(last)
            else:
                first_str = "—"; last_str = "—"
            slope_str = f"{slope:+.3f}" if slope is not None else "—"
            r2_str = f"{r2:.3f}" if r2 is not None else "—"
            out.append(f"| {key} | {unit} | {first_str} | {last_str} | {slope_str} | {r2_str} |\n")
        out.append("\n> Charts are in the `long-run/` subdirectory of the results artifact.\n")
    except (json.JSONDecodeError, OSError) as e:
        print(f"WARN: could not read long-run-summary.json: {e}", file=sys.stderr)

# ── Latency drift ──────────────────────────────────────────────────────────────
ld_paths = sorted(glob.glob(f"{WORKSPACE}/perf-scripts/{DEPLOYMENT}/results-*/latency-drift.json"))
if ld_paths:
    try:
        with open(ld_paths[-1]) as f:
            ld = json.load(f)
        scenarios = ld.get("scenarios", [])
        if scenarios:
            bs = ld.get("bucket_seconds", 300)
            out.append(f"\n## Latency drift (per {bs // 60}-min bucket)\n\n")
            out.append("| Scenario | Requests | Buckets | p95 first (ms) | p95 last (ms) | p95 slope (ms/hour) | R² |\n")
            out.append("| --- | ---: | ---: | ---: | ---: | ---: | ---: |\n")
            for s in scenarios:
                out.append(
                    f"| {s.get('scenario', '')} "
                    f"| {s.get('total_requests', 0)} "
                    f"| {s.get('buckets', 0)} "
                    f"| {s.get('p95_first_bucket_ms', 0)} "
                    f"| {s.get('p95_last_bucket_ms', 0)} "
                    f"| {s.get('p95_slope_ms_per_hour', 0):+.2f} "
                    f"| {s.get('p95_r_squared', 0):.3f} |\n"
                )
            out.append("\n> Per-scenario charts are in the `latency-drift/` subdirectory of the results artifact.\n")
    except (json.JSONDecodeError, OSError) as e:
        print(f"WARN: could not read latency-drift.json: {e}", file=sys.stderr)

content = "".join(out)
if summary_path:
    with open(summary_path, "a") as f:
        f.write(content)
else:
    print(content)
