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
# Download results.zip from the bastion via rsync (resumable + verified) and
# generate summary artifacts. Rsync is resumable and end-to-end verified via
# --partial + --append-verify, wrapped in a 3-attempt retry with backoff so
# multi-GB transfers survive transient network issues.
#
# Required env:
#   WORKSPACE, DEPLOYMENT, BASTION_IP, KEY_FILE, MANIFEST_DIR, RESULTS_DIR_NAME
# ----------------------------------------------------------------------------

set -euo pipefail

: "${WORKSPACE:?WORKSPACE must be set}"
: "${DEPLOYMENT:?DEPLOYMENT must be set}"
: "${BASTION_IP:?BASTION_IP must be set}"
: "${KEY_FILE:?KEY_FILE must be set}"
: "${MANIFEST_DIR:?MANIFEST_DIR must be set}"
: "${RESULTS_DIR_NAME:?RESULTS_DIR_NAME must be set}"

DEPLOYMENT_DIR="$WORKSPACE/perf-scripts/$DEPLOYMENT"
RESULTS_DIR="$DEPLOYMENT_DIR/$RESULTS_DIR_NAME"

echo "Preparing results directory: $RESULTS_DIR"
mkdir -p "$RESULTS_DIR"

echo ""
echo "Copying CF test metadata into results directory..."
if [[ ! -f "$MANIFEST_DIR/cf-test-metadata.json" ]]; then
    echo "ERROR: cf-test-metadata.json not present in manifest artifact." >&2
    exit 1
fi
cp "$MANIFEST_DIR/cf-test-metadata.json" "$RESULTS_DIR/cf-test-metadata.json"

echo ""
echo "Extracting Thunder Performance Distribution into $RESULTS_DIR"
tar -xf "$DEPLOYMENT_DIR"/target/performance-thunder-singlenode-*.tar.gz -C "$RESULTS_DIR"

echo ""
echo "Downloading results.zip from bastion via rsync..."
echo "  source: ubuntu@${BASTION_IP}:/home/ubuntu/results.zip"
echo "  target: ${RESULTS_DIR}/results.zip"

ssh_transport="ssh -i \"$KEY_FILE\" -o StrictHostKeyChecking=no -o ServerAliveInterval=15 -o ServerAliveCountMax=8 -o ConnectTimeout=30"

download_ok=0
for attempt in 1 2 3; do
    echo ""
    echo "rsync attempt $attempt/3..."
    if rsync -avP --partial --append-verify --timeout=180 \
        -e "$ssh_transport" \
        "ubuntu@${BASTION_IP}:/home/ubuntu/results.zip" \
        "$RESULTS_DIR/results.zip"; then
        echo "rsync succeeded on attempt $attempt."
        download_ok=1
        break
    fi
    echo "rsync attempt $attempt failed (exit $?)."
    if [[ $attempt -lt 3 ]]; then
        backoff=$((attempt * 30))
        echo "Backing off ${backoff}s before retry..."
        sleep "$backoff"
    fi
done

if [[ $download_ok -ne 1 ]]; then
    echo "ERROR: rsync failed after 3 attempts." >&2
    exit 1
fi

if [[ ! -f "$RESULTS_DIR/results.zip" ]]; then
    echo "ERROR: results.zip not present after rsync (unexpected)." >&2
    exit 1
fi

result_size=$(stat -c %s "$RESULTS_DIR/results.zip")
echo "Downloaded results.zip: $result_size bytes"

# ---- Long-run metrics CSV (produced by long-run-sampler.sh on the bastion) ----
# Best-effort: absent for older triggers or when the sampler never wrote a row.
echo ""
echo "Downloading long-run-metrics.csv from bastion (best-effort)..."
if rsync -av --timeout=60 \
    -e "$ssh_transport" \
    "ubuntu@${BASTION_IP}:/home/ubuntu/long-run-metrics.csv" \
    "$RESULTS_DIR/long-run-metrics.csv" 2>&1; then
    echo "long-run-metrics.csv downloaded ($(stat -c %s "$RESULTS_DIR/long-run-metrics.csv") bytes)."
else
    echo "WARN: long-run-metrics.csv not present on bastion (older trigger or sampler failure) — skipping long-run analysis."
fi

echo ""
echo "Creating summary.csv..."
echo "============================================"
cd "$RESULTS_DIR"
unzip -q results.zip
wget -q http://sourceforge.net/projects/gcviewer/files/gcviewer-1.35.jar/download -O gcviewer.jar

"$RESULTS_DIR"/jmeter/create-summary-csv.sh -d results -n "WSO2 Thunder" -p wso2thunder -c "Heap Size" \
    -c "Concurrent Users" -r "([0-9]+[a-zA-Z])_heap" -r "([0-9]+)_users" -i -l -k 1 -g gcviewer.jar

echo ""
echo "Creating summary results markdown file..."
# Non-fatal: the shared Jinja template errors out when summary.csv has no data rows
# (e.g. when jtl-splitter didn't run so no results-measurement-summary.json exists).
# The rest of the collect flow (CloudWatch, latency drift, long-run analysis, teardown)
# should still complete.
./jmeter/create-summary-markdown.py --json-files cf-test-metadata.json results/test-metadata.json --column-names \
    "Concurrent Users" "95th Percentile of Response Time (ms)" \
    || echo "WARN: create-summary-markdown.py failed — summary.md will not be produced. summary.csv is unaffected."

# ---- Latency drift analysis (uses per-scenario jtls.zip under results/) ----
# Writes to $RESULTS_DIR/latency-drift/<scenario>/ so outputs survive the cleanup below.
# matplotlib is required for the plots; install if not already present.
echo ""
echo "Ensuring matplotlib is installed for analysis scripts..."
pip install -q matplotlib || echo "WARN: pip install matplotlib failed — charts may not render."

echo ""
echo "Analyzing latency drift..."
RESULTS_DIR="$RESULTS_DIR" python3 "$WORKSPACE"/.github/scripts/analyze-latency-drift.py \
    || echo "WARN: latency drift analysis failed."

# ---- Long-run trend charts (uses long-run-metrics.csv from bastion) ----
# No-op if the CSV wasn't downloaded (older trigger).
echo ""
echo "Generating long-run trend charts..."
RESULTS_DIR="$RESULTS_DIR" python3 "$WORKSPACE"/.github/scripts/generate-long-run-charts.py \
    || echo "WARN: long-run chart generation failed."

# Cleanup — mirrors start-performance.sh's post-run cleanup for artifact parity.
# latency-drift/ and long-run/ live at $RESULTS_DIR (not inside results/) so they survive.
rm -rf cf-test-metadata.json cloudformation/ common/ gcviewer.jar is/ jmeter/ jtl-splitter/ netty-service/ payloads/ sar/ setup/ results/ thunder/restart-thunder.sh summary/

echo ""
echo "Collect script complete."
echo "============================================"
