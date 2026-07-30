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
# Ship rotated (compressed) Thunder + Nginx logs to S3 during a detached run. Runs on the
# bastion beside run-performance-tests.sh; every SYNC_INTERVAL_SECONDS it rsyncs the rotated
# *.gz files from each node (over the SSH aliases) into a staging dir, then `aws s3 sync`s to
# S3. Mid-run only rotated files are shipped; the active log is captured at the end by the
# collect job via FINAL_ONCE (below), which runs before teardown. Exits when the test stops.
#
# Env: S3_BUCKET (default performance-thunder), S3_PREFIX (default perf-logs),
#      RUN_ID (default: UTC timestamp), SYNC_INTERVAL_SECONDS (default 900),
#      THUNDER_ALIAS (default wso2thunder), NGINX_ALIAS (default loadbalancer),
#      STAGING (default /home/ubuntu/log-s3-staging), FINAL_ONCE (1 = one-shot final).
# ----------------------------------------------------------------------------

set -uo pipefail

S3_BUCKET="${S3_BUCKET:-performance-thunder}"
S3_PREFIX="${S3_PREFIX:-perf-logs}"
RUN_ID="${RUN_ID:-$(date -u +%Y%m%d-%H%M%S)}"
SYNC_INTERVAL_SECONDS="${SYNC_INTERVAL_SECONDS:-900}"
THUNDER_ALIAS="${THUNDER_ALIAS:-wso2thunder}"
NGINX_ALIAS="${NGINX_ALIAS:-loadbalancer}"

STAGING="${STAGING:-/home/ubuntu/log-s3-staging}"
DEST="s3://${S3_BUCKET}/${S3_PREFIX}/${RUN_ID}"
SSH_OPTS="ssh -o ConnectTimeout=10 -o BatchMode=yes"

mkdir -p "$STAGING/thunder" "$STAGING/nginx"
log() { echo "[log-s3-sync] $(date -u +%Y-%m-%dT%H:%M:%SZ) $*"; }

sync_once() {
    # Returns non-zero if the S3 push fails, or (on the final pass) if a node staged no
    # files — so a final capture can never report success while no logs reached S3.
    local rc=0 mode="${1:-}"
    local -a filter=(--include="*.gz" --exclude="*")
    if [[ "$mode" == "final" ]]; then
        filter=(--include="*.gz" --include="*.log" --exclude="*")
    fi

    # Mirror each node's selected logs into staging with --delete, so staging tracks the
    # node's bounded rotation window (~max_backups files) instead of growing without limit
    # on the bastion. Thunder logs are owned by ubuntu -> pull directly.
    rsync -a --delete -e "$SSH_OPTS" "${filter[@]}" \
        "${THUNDER_ALIAS}:/home/ubuntu/thunder/repository/logs/" "$STAGING/thunder/" 2>/dev/null \
        || log "WARN: rsync from ${THUNDER_ALIAS} failed"

    # Nginx logs are root-owned -> pull with remote sudo (passwordless sudo is configured).
    rsync -a --delete -e "$SSH_OPTS" --rsync-path="sudo rsync" "${filter[@]}" \
        "${NGINX_ALIAS}:/var/log/nginx/" "$STAGING/nginx/" 2>/dev/null \
        || log "WARN: rsync from ${NGINX_ALIAS} failed"

    # On the final pass, refuse to pass unless both nodes actually staged files. An empty
    # stage means the pull failed and we captured nothing — surface it, don't pass silently.
    if [[ "$mode" == "final" ]]; then
        [[ -n "$(ls -A "$STAGING/thunder" 2>/dev/null)" ]] || { log "ERROR: no Thunder logs staged"; rc=1; }
        [[ -n "$(ls -A "$STAGING/nginx"   2>/dev/null)" ]] || { log "ERROR: no Nginx logs staged";   rc=1; }
    fi

    # Push to S3 (credentials from the bastion instance profile). No --delete here, so S3
    # keeps the full history even after a file ages out of the node/staging window.
    if aws s3 sync "$STAGING/" "${DEST}/" --only-show-errors; then
        log "synced -> ${DEST}/"
    else
        log "ERROR: aws s3 sync to ${DEST}/ failed"
        rc=1
    fi
    return "$rc"
}

# awscli is installed at bastion setup time (setup-bastion.sh); rsync ships with the AMI
# (the collect pipeline already rsyncs from the bastion). Warn — don't fail — if missing.
for bin in aws rsync; do
    command -v "$bin" >/dev/null 2>&1 || log "WARN: '$bin' not on PATH; log shipping may not work"
done

# One-shot final mode. The collect job calls this before teardown; it exits non-zero if the
# logs did not reach S3, so the caller can fail collect and block teardown.
if [[ "${FINAL_ONCE:-}" == "1" || "${1:-}" == "--final" ]]; then
    log "Final sync -> ${DEST}/"
    if sync_once final; then
        log "Final sync complete."
        exit 0
    fi
    log "ERROR: final sync failed; logs may not be in S3."
    exit 1
fi

log "Starting log->S3 sync. Dest=${DEST} Interval=${SYNC_INTERVAL_SECONDS}s"
sleep 60

while :; do
    if ! pgrep -f "[r]un-performance-tests.sh" >/dev/null 2>&1; then
        log "run-performance-tests.sh stopped. Exiting, the collect job does the final sync."
        break
    fi
    sync_once
    sleep "$SYNC_INTERVAL_SECONDS"
done

log "Done."
