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
