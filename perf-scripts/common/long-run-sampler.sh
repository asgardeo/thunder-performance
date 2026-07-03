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
# Long-run sampler for detached perf tests.
#
# Runs on the bastion alongside run-performance-tests.sh. Every 300s samples:
#   Thunder host  — RSS / VSZ of thunderid, disk used/avail (/), log-dir size
#   RDS runtimedb — pg_database_size + row counts for runtime tables
# Appends one CSV row per iteration to /home/ubuntu/long-run-metrics.csv.
#
# Exits when run-performance-tests.sh is no longer running (60s startup grace).
# Failed samples log a WARN and continue with empty values in that row.
#
# Env required:
#   RDS_HOST       - postgres endpoint
#   DB_USER        - postgres username (default: asgthunder)
#   DB_PASSWORD    - postgres password (default: asgthunder)
#   SAMPLE_INTERVAL_SECONDS - default 300
# ----------------------------------------------------------------------------

set -uo pipefail

RDS_HOST="${RDS_HOST:?RDS_HOST must be set}"
DB_USER="${DB_USER:-asgthunder}"
DB_PASSWORD="${DB_PASSWORD:-asgthunder}"
SAMPLE_INTERVAL_SECONDS="${SAMPLE_INTERVAL_SECONDS:-300}"

OUTPUT_CSV="/home/ubuntu/long-run-metrics.csv"
THUNDER_ALIAS="wso2thunder"
THUNDER_HOME="/home/ubuntu/thunder"

export PGPASSWORD="$DB_PASSWORD"

# ----- Runtime tables of interest (schema: backend/dbscripts/runtimedb/postgres.sql) -----
RUNTIME_TABLES=(
    AUTHORIZATION_CODE
    AUTHORIZATION_REQUEST
    CIBA_AUTH_REQUEST
    FLOW_CONTEXT
    WEBAUTHN_SESSION
    ATTRIBUTE_CACHE
    PAR_REQUEST
    JTI_RECORD
    OPENID4VP_REQUEST_STATE
    OPENID4VCI_NONCE
    OPENID4VCI_CREDENTIAL_OFFER
)

# ----- CSV header -----
if [[ ! -f "$OUTPUT_CSV" ]]; then
    header="timestamp,thunder_rss_kb,thunder_vsz_kb,thunder_disk_used_bytes,thunder_disk_avail_bytes,thunder_log_bytes,runtimedb_bytes"
    for t in "${RUNTIME_TABLES[@]}"; do
        header+=",count_$(echo "$t" | tr '[:upper:]' '[:lower:]')"
    done
    echo "$header" > "$OUTPUT_CSV"
fi

echo "[long-run-sampler] Starting sampler. Interval=${SAMPLE_INTERVAL_SECONDS}s. Output=${OUTPUT_CSV}"
echo "[long-run-sampler] Waiting 60s for JMeter to start before entering the main loop..."
sleep 60

# ----- Sample one iteration -----
sample_once() {
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Thunder host stats via ssh alias. All values default empty on failure.
    local rss_kb="" vsz_kb="" disk_used="" disk_avail="" log_bytes=""
    local host_out
    if host_out=$(ssh -o ConnectTimeout=10 -o BatchMode=yes "$THUNDER_ALIAS" bash -s <<'REMOTE_EOF' 2>/dev/null
set -uo pipefail
pid=$(pgrep -f "[t]hunderid" | head -1)
if [[ -n "$pid" ]]; then
    ps -o rss= -o vsz= -p "$pid" 2>/dev/null | awk '{print "RSS_KB="$1"\nVSZ_KB="$2}'
else
    echo "RSS_KB="
    echo "VSZ_KB="
fi
df -B1 --output=used,avail / 2>/dev/null | tail -1 | awk '{print "DISK_USED="$1"\nDISK_AVAIL="$2}'
# Sum sizes of the stdout redirect log and the internal repository/logs directory.
log_total=$( (du -bs /home/ubuntu/thunder/thunder_*.log 2>/dev/null; du -bs /home/ubuntu/thunder/repository/logs/ 2>/dev/null) \
    | awk '{s+=$1} END {print s+0}' )
echo "LOG_BYTES=$log_total"
REMOTE_EOF
    ); then
        rss_kb=$(echo "$host_out" | awk -F= '/^RSS_KB=/{print $2}')
        vsz_kb=$(echo "$host_out" | awk -F= '/^VSZ_KB=/{print $2}')
        disk_used=$(echo "$host_out" | awk -F= '/^DISK_USED=/{print $2}')
        disk_avail=$(echo "$host_out" | awk -F= '/^DISK_AVAIL=/{print $2}')
        log_bytes=$(echo "$host_out" | awk -F= '/^LOG_BYTES=/{print $2}')
    else
        echo "[long-run-sampler] WARN: ssh to $THUNDER_ALIAS failed at $ts"
    fi

    # RDS: db size + row counts. Single psql call with all queries.
    local runtimedb_bytes=""
    declare -A counts
    for t in "${RUNTIME_TABLES[@]}"; do counts[$t]=""; done

    # Build the psql query. Each SELECT is on its own line, terminated with a semicolon,
    # and produces one tuple-only line; we read them in order.
    local sql="SELECT pg_database_size('runtimedb');"
    for t in "${RUNTIME_TABLES[@]}"; do
        # Table names in schema are quoted (upper-case) — must use identifier-quoted form.
        sql+=" SELECT COUNT(*) FROM \"$t\";"
    done

    local psql_out
    if psql_out=$(psql -h "$RDS_HOST" -U "$DB_USER" -d runtimedb \
                       --set=ON_ERROR_STOP=1 -qAt -c "$sql" 2>/dev/null); then
        # First line is db size, following lines are row counts in table order.
        mapfile -t lines <<< "$psql_out"
        runtimedb_bytes="${lines[0]:-}"
        for i in "${!RUNTIME_TABLES[@]}"; do
            counts[${RUNTIME_TABLES[$i]}]="${lines[$((i+1))]:-}"
        done
    else
        echo "[long-run-sampler] WARN: psql to $RDS_HOST failed at $ts"
    fi

    # Emit one CSV row.
    local row="$ts,$rss_kb,$vsz_kb,$disk_used,$disk_avail,$log_bytes,$runtimedb_bytes"
    for t in "${RUNTIME_TABLES[@]}"; do
        row+=",${counts[$t]}"
    done
    echo "$row" >> "$OUTPUT_CSV"
    echo "[long-run-sampler] Sampled: $row"
}

# ----- Main loop -----
while :; do
    # If run-performance-tests.sh has exited, sample once more and quit.
    if ! pgrep -f "[r]un-performance-tests.sh" >/dev/null 2>&1; then
        echo "[long-run-sampler] run-performance-tests.sh no longer running. Taking final sample and exiting."
        sample_once
        break
    fi

    sample_once
    sleep "$SAMPLE_INTERVAL_SECONDS"
done

echo "[long-run-sampler] Done."
