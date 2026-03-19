#!/bin/bash
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
# Collect CloudWatch metrics for all infrastructure nodes covering the
# performance test window and save them as CSVs in the results directory.
# ----------------------------------------------------------------------------

START_TIME="${PERF_TEST_START_TIME:-}"
END_TIME="${PERF_TEST_END_TIME:-}"

# Fallback: if the execute step failed before writing output, use last 3 hours.
if [[ -z "$START_TIME" ]]; then
    START_TIME=$(date -u -d '3 hours ago' +%Y-%m-%dT%H:%M:%SZ)
    echo "WARN: PERF_TEST_START_TIME not set, defaulting to 3 hours ago: $START_TIME"
fi
if [[ -z "$END_TIME" ]]; then
    END_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    echo "WARN: PERF_TEST_END_TIME not set, defaulting to now: $END_TIME"
fi

# Find the results directory created during the test run.
RESULTS_DIR=$(find "$WORKSPACE/perf-scripts/$DEPLOYMENT" -maxdepth 1 -name "results-*" -type d 2>/dev/null | sort | tail -1)
if [[ -z "$RESULTS_DIR" ]]; then
    RESULTS_DIR="$WORKSPACE/perf-scripts/$DEPLOYMENT/cloudwatch-metrics"
    echo "WARN: No results-* directory found, saving metrics to $RESULTS_DIR"
fi

METRICS_DIR="$RESULTS_DIR/cloudwatch"
mkdir -p "$METRICS_DIR"

echo ""
echo "Collecting CloudWatch metrics..."
echo "    Time window : $START_TIME → $END_TIME"
echo "    Output dir  : $METRICS_DIR"
echo "=========================================================="

# --- EC2 instances ---
# Basic monitoring (5-min period) is free; covers CPU, network, and disk I/O.
# Memory is not available without the CloudWatch Agent.
EC2_METRICS=(CPUUtilization NetworkIn NetworkOut DiskReadOps DiskWriteOps DiskReadBytes DiskWriteBytes)

for node_info in \
    "thunder:${THUNDER_INSTANCE_ID:-}" \
    "nginx:${NGINX_INSTANCE_ID:-}" \
    "bastion:${BASTION_INSTANCE_ID:-}"; do

    node_name="${node_info%%:*}"
    instance_id="${node_info##*:}"

    if [[ -z "$instance_id" ]]; then
        echo "Skipping $node_name EC2 metrics: instance ID not set."
        continue
    fi

    output_file="$METRICS_DIR/${node_name}-ec2.csv"
    echo "Timestamp,Metric,Average" > "$output_file"

    for metric in "${EC2_METRICS[@]}"; do
        aws cloudwatch get-metric-statistics \
            --namespace AWS/EC2 \
            --metric-name "$metric" \
            --dimensions Name=InstanceId,Value="$instance_id" \
            --start-time "$START_TIME" \
            --end-time "$END_TIME" \
            --period 300 \
            --statistics Average \
            --query 'sort_by(Datapoints, &Timestamp)[*].[Timestamp, Average]' \
            --output text 2>/dev/null \
        | while IFS=$'\t' read -r ts avg; do
            echo "$ts,$metric,$avg"
        done >> "$output_file"
    done

    echo "Saved $node_name EC2 metrics → $output_file"
done

# --- RDS instance ---
# RDS publishes 1-minute metrics natively at no additional cost, including memory.
if [[ -n "${RDS_INSTANCE_ID:-}" ]]; then
    RDS_METRICS=(CPUUtilization FreeableMemory ReadIOPS WriteIOPS NetworkReceiveThroughput NetworkTransmitThroughput DatabaseConnections)
    output_file="$METRICS_DIR/rds.csv"
    echo "Timestamp,Metric,Average" > "$output_file"

    for metric in "${RDS_METRICS[@]}"; do
        aws cloudwatch get-metric-statistics \
            --namespace AWS/RDS \
            --metric-name "$metric" \
            --dimensions Name=DBInstanceIdentifier,Value="$RDS_INSTANCE_ID" \
            --start-time "$START_TIME" \
            --end-time "$END_TIME" \
            --period 60 \
            --statistics Average \
            --query 'sort_by(Datapoints, &Timestamp)[*].[Timestamp, Average]' \
            --output text 2>/dev/null \
        | while IFS=$'\t' read -r ts avg; do
            echo "$ts,$metric,$avg"
        done >> "$output_file"
    done

    echo "Saved RDS metrics → $output_file"
else
    echo "Skipping RDS metrics: RDS_INSTANCE_ID not set."
fi

echo ""
echo "CloudWatch metrics collection complete."
echo "=========================================================="
