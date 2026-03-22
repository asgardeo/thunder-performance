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


def read_csv_metrics(filepath):
    """Return {metric_name: [float, ...]} from a cloudwatch CSV."""
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
out.append(f"\nPerformance Repo Branch: {GITHUB_REF_NAME}\n")

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
        ("Thunder (EC2)", "thunder-ec2.csv"),
        ("Nginx (EC2)",   "nginx-ec2.csv"),
        ("Bastion (EC2)", "bastion-ec2.csv"),
    ]

    for label, filename in ec2_nodes:
        data = read_csv_metrics(os.path.join(metrics_dir, filename))
        if not any(data.values()):
            continue
        out.append(f"\n### {label}\n\n")
        out.append(metrics_table(data, EC2_METRICS))

    rds_data = read_csv_metrics(os.path.join(metrics_dir, "rds.csv"))
    if any(rds_data.values()):
        out.append("\n### RDS\n\n")
        out.append(metrics_table(rds_data, RDS_METRICS))

content = "".join(out)
if summary_path:
    with open(summary_path, "a") as f:
        f.write(content)
else:
    print(content)
