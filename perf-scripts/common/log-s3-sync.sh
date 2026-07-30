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
# Ship rotated (compressed) Thunder + Nginx logs to S3 during a detached run.
# Runs on the bastion beside run-performance-tests.sh. Every SYNC_INTERVAL_SECONDS it
# pulls the rotated *.gz files from each node (over the existing SSH aliases) into a local
# staging dir, then `aws s3 sync`s that to S3. During the run only compressed, already-rotated
# files are shipped, so the constantly-changing active log is never re-uploaded. The final
# pass (once the test stops) additionally ships the active, not-yet-rotated logs so the tail -
# and any stream that never crossed the rotation size threshold - is not lost at teardown.
# sync is idempotent, so a transient failure is retried on the next pass. AWS credentials come
# from the bastion's instance profile. Exits when run-performance-tests.sh stops (final sync first).
#
# Env: S3_BUCKET (default performance-thunder), S3_PREFIX (default perf-logs),
#      RUN_ID (default: UTC timestamp), SYNC_INTERVAL_SECONDS (default 900),
#      THUNDER_ALIAS (default wso2thunder), NGINX_ALIAS (default loadbalancer).
# ----------------------------------------------------------------------------

set -uo pipefail

S3_BUCKET="${S3_BUCKET:-performance-thunder}"
S3_PREFIX="${S3_PREFIX:-perf-logs}"
RUN_ID="${RUN_ID:-$(date -u +%Y%m%d-%H%M%S)}"
SYNC_INTERVAL_SECONDS="${SYNC_INTERVAL_SECONDS:-900}"
THUNDER_ALIAS="${THUNDER_ALIAS:-wso2thunder}"
NGINX_ALIAS="${NGINX_ALIAS:-loadbalancer}"

STAGING="/home/ubuntu/log-s3-staging"
DEST="s3://${S3_BUCKET}/${S3_PREFIX}/${RUN_ID}"
SSH_OPTS="ssh -o ConnectTimeout=10 -o BatchMode=yes"

mkdir -p "$STAGING/thunder" "$STAGING/nginx"
log() { echo "[log-s3-sync] $(date -u +%Y-%m-%dT%H:%M:%SZ) $*"; }

sync_once() {
    # On the final pass also pull the active, not-yet-rotated logs.
    local -a filter=(--include="*.gz" --exclude="*")
    if [[ "${1:-}" == "final" ]]; then
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

    # Push to S3 (credentials from the bastion instance profile). No --delete here, so S3
    # keeps the full history even after a file ages out of the node/staging window. sync
    # uploads only what is not already in S3, so repeated passes are cheap and self-healing.
    if aws s3 sync "$STAGING/" "${DEST}/" --only-show-errors; then
        log "synced -> ${DEST}/"
    else
        log "WARN: aws s3 sync to ${DEST}/ failed"
    fi
}

# awscli is installed at bastion setup time (setup-bastion.sh); rsync ships with the AMI
# (the collect pipeline already rsyncs from the bastion). Warn — don't fail — if missing.
for bin in aws rsync; do
    command -v "$bin" >/dev/null 2>&1 || log "WARN: '$bin' not on PATH; log shipping may not work"
done

log "Starting log->S3 sync. Dest=${DEST} Interval=${SYNC_INTERVAL_SECONDS}s"
sleep 60

while :; do
    if ! pgrep -f "[r]un-performance-tests.sh" >/dev/null 2>&1; then
        log "run-performance-tests.sh stopped. Final sync and exit."
        sync_once final
        break
    fi
    sync_once
    sleep "$SYNC_INTERVAL_SECONDS"
done

log "Done."
