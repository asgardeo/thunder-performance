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
# DB cleanup loop for detached (long-running) perf tests.
#
# Runs on the bastion alongside run-performance-tests.sh. Every
# CLEANUP_INTERVAL_SECONDS it invokes the cleanup procedures against the runtime
# databases so they stay bounded over a long run:
#   runtime_transient  -> CALL cleanup_expired_runtime_transient_data()
#   runtime_persistent -> CALL cleanup_expired_runtime_persistent_data()
#   runtime_persistent -> CALL perf_cleanup_expired_sso_sessions()   [see NOTE]
#
# The first two are Thunder's shipped procedures, installed at DB-setup time by
# create_database.sql (\i .../postgres-cleanup.sql). They delete only EXPIRED rows in
# bounded, self-committing batches, so calling them repeatedly is safe and cheap.
#
# Scheduling: Bastion loop with the recommended 60-min cadence by default.
#
# NOTE (temporary): the alpha pack's shipped cleanup_expired_runtime_persistent_data()
# purges only REVOKED_TOKEN — the SSO_SESSION purge was added to Thunder AFTER v1.0.0-alpha
# was cut (commit b583fb0f0, 2026-07-22). Until the harness moves to a release whose shipped
# proc already purges SSO sessions, create_database.sql defines perf_cleanup_expired_sso_sessions()
# as a faithful copy of that logic, and we call it here. REMOVE the perf_cleanup_expired_sso_sessions
# line below (and the procedure in create_database.sql) once the version is updated.
#
# Exits when run-performance-tests.sh is no longer running (60s startup grace),
#
# Env required:
#   RDS_HOST                 - postgres endpoint
#   DB_USER                  - postgres username (default: asgthunder)
#   DB_PASSWORD              - postgres password (default: asgthunder)
#   CLEANUP_INTERVAL_SECONDS - default 3600 (60 min)
# ----------------------------------------------------------------------------

set -uo pipefail

RDS_HOST="${RDS_HOST:?RDS_HOST must be set}"
DB_USER="${DB_USER:-asgthunder}"
DB_PASSWORD="${DB_PASSWORD:-asgthunder}"
CLEANUP_INTERVAL_SECONDS="${CLEANUP_INTERVAL_SECONDS:-3600}"

export PGPASSWORD="$DB_PASSWORD"

log() { echo "[db-cleanup-loop] $(date -u +%Y-%m-%dT%H:%M:%SZ) $*"; }

# Each CALL is a top-level statement: the procedures COMMIT per batch, so they cannot run
# inside a wrapping transaction. Failures are non-fatal — a single failed cleanup must not
# kill the loop for the rest of the run.
run_cleanup() {
    local db="$1" proc="$2"
    if psql -h "$RDS_HOST" -U "$DB_USER" -d "$db" -qAt \
            -c "CALL ${proc}();" >/dev/null 2>&1; then
        log "${db}: ${proc} OK"
    else
        log "WARN: ${db}: ${proc} failed"
    fi
}

run_cleanup_cycle() {
    run_cleanup runtime_transient  cleanup_expired_runtime_transient_data
    run_cleanup runtime_persistent cleanup_expired_runtime_persistent_data
    # Temporary — remove once the shipped persistent proc purges SSO sessions (see NOTE).
    run_cleanup runtime_persistent perf_cleanup_expired_sso_sessions
}

log "Starting DB cleanup loop. Interval=${CLEANUP_INTERVAL_SECONDS}s."
log "Waiting 60s for JMeter to start before the first cleanup..."
sleep 60

while :; do
    # If run-performance-tests.sh has exited, run one final cleanup and quit.
    if ! pgrep -f "[r]un-performance-tests.sh" >/dev/null 2>&1; then
        log "run-performance-tests.sh no longer running. Final cleanup and exit."
        run_cleanup_cycle
        break
    fi

    run_cleanup_cycle
    sleep "$CLEANUP_INTERVAL_SECONDS"
done

log "Done."
