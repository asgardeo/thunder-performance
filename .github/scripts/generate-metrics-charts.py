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
# Read CloudWatch metrics CSVs and generate charts embedded in the
# GitHub Actions step summary as base64-encoded inline images.
# Reads WORKSPACE and DEPLOYMENT env vars to locate the metrics directory.
# ----------------------------------------------------------------------------

import base64
import csv
import os
import sys
from collections import defaultdict
from datetime import datetime

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.dates as mdates


def find_metrics_dir():
    workspace = os.environ.get('WORKSPACE', os.environ.get('GITHUB_WORKSPACE', '.'))
    deployment = os.environ.get('DEPLOYMENT', 'single-node')
    base = os.path.join(workspace, 'perf-scripts', deployment)
    try:
        results_dirs = sorted(
            d for d in os.listdir(base)
            if d.startswith('results-') and os.path.isdir(os.path.join(base, d))
        )
        if results_dirs:
            return os.path.join(base, results_dirs[-1], 'cloudwatch')
    except FileNotFoundError:
        pass
    return None


def read_csv(filepath):
    data = defaultdict(list)
    try:
        with open(filepath, newline='') as f:
            for row in csv.DictReader(f):
                try:
                    ts = datetime.fromisoformat(row['Timestamp'].replace('Z', '+00:00'))
                    data[row['Metric']].append((ts, float(row['Average'])))
                except (ValueError, KeyError):
                    continue
    except FileNotFoundError:
        pass
    for metric in data:
        data[metric].sort()
    return data


def make_figure(data, groups, title):
    """
    groups: list of (subplot_title, [metric_names], y_label, value_transform_fn_or_None)
    """
    n = len(groups)
    fig, axes = plt.subplots(n, 1, figsize=(10, 2.8 * n), constrained_layout=True)
    if n == 1:
        axes = [axes]

    fig.suptitle(title, fontsize=13, fontweight='bold')

    colors = ['#0969da', '#cf222e', '#1a7f37', '#8250df', '#bf8700']

    for ax, (subtitle, metrics, ylabel, transform) in zip(axes, groups):
        has_data = False
        for i, metric in enumerate(metrics):
            series = data.get(metric, [])
            if series:
                times, values = zip(*series)
                if transform:
                    values = [transform(v) for v in values]
                ax.plot(times, values, marker='o', markersize=4, linewidth=1.5,
                        label=metric, color=colors[i % len(colors)])
                has_data = True

        ax.set_title(subtitle, fontsize=10, pad=4)
        ax.set_ylabel(ylabel, fontsize=8)
        ax.xaxis.set_major_formatter(mdates.DateFormatter('%H:%M'))
        fig.autofmt_xdate(rotation=30, ha='right')
        ax.tick_params(labelsize=8)
        ax.grid(True, alpha=0.25)
        ax.set_facecolor('#f6f8fa')

        if len(metrics) > 1 and has_data:
            ax.legend(fontsize=8, loc='upper right', framealpha=0.8)
        if not has_data:
            ax.text(0.5, 0.5, 'No data available', transform=ax.transAxes,
                    ha='center', va='center', color='#888', fontsize=10)

    return fig


def save_and_encode(fig, path):
    fig.savefig(path, dpi=100, bbox_inches='tight', facecolor='white')
    plt.close(fig)
    with open(path, 'rb') as f:
        return base64.b64encode(f.read()).decode()


def to_mb(v):
    return round(v / 1_048_576, 3)


def main():
    metrics_dir = find_metrics_dir()
    if not metrics_dir or not os.path.isdir(metrics_dir):
        print("No cloudwatch metrics directory found — skipping chart generation.", file=sys.stderr)
        sys.exit(0)

    summary_path = os.environ.get('GITHUB_STEP_SUMMARY')
    lines = ['\n## CloudWatch Infrastructure Metrics\n']

    # EC2 nodes — basic monitoring (5-min intervals)
    ec2_groups = [
        ('CPU Utilization',  ['CPUUtilization'],                        'Percent (%)',  None),
        ('Network Traffic',  ['NetworkIn', 'NetworkOut'],                'MB',           to_mb),
        ('Disk Operations',  ['DiskReadOps', 'DiskWriteOps'],           'Ops / period', None),
        ('Disk Throughput',  ['DiskReadBytes', 'DiskWriteBytes'],       'MB / period',  to_mb),
    ]

    for node in ('thunder', 'nginx', 'bastion'):
        csv_path = os.path.join(metrics_dir, f'{node}-ec2.csv')
        data = read_csv(csv_path)
        if not any(data.values()):
            continue
        fig = make_figure(data, ec2_groups, f'{node.capitalize()} Node — EC2 Metrics')
        b64 = save_and_encode(fig, os.path.join(metrics_dir, f'{node}-ec2.png'))
        lines.append(f'### {node.capitalize()} (EC2)\n')
        lines.append(f'<img src="data:image/png;base64,{b64}" width="800"/>\n\n')

    # RDS — 1-minute intervals, includes memory
    rds_groups = [
        ('CPU Utilization',     ['CPUUtilization'],                                        'Percent (%)', None),
        ('Freeable Memory',     ['FreeableMemory'],                                        'MB',          to_mb),
        ('IOPS',                ['ReadIOPS', 'WriteIOPS'],                                 'Ops / sec',   None),
        ('Network Throughput',  ['NetworkReceiveThroughput', 'NetworkTransmitThroughput'], 'MB / sec',    to_mb),
        ('DB Connections',      ['DatabaseConnections'],                                   'Count',       None),
    ]
    rds_data = read_csv(os.path.join(metrics_dir, 'rds.csv'))
    if any(rds_data.values()):
        fig = make_figure(rds_data, rds_groups, 'RDS — Database Metrics')
        b64 = save_and_encode(fig, os.path.join(metrics_dir, 'rds.png'))
        lines.append('### RDS\n')
        lines.append(f'<img src="data:image/png;base64,{b64}" width="800"/>\n\n')

    output = '\n'.join(lines)
    if summary_path:
        with open(summary_path, 'a') as f:
            f.write(output)
    else:
        print(output)


if __name__ == '__main__':
    main()
