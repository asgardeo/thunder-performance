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
# Runs on the bastion alongside run-performance-tests.sh. Every SAMPLE_INTERVAL_SECONDS samples:
#   Thunder host           — RSS / VSZ of thunderid, disk used/avail (/), log-dir size
#   RDS runtime_transient  — pg_database_size + row counts for the runtime tables it holds
#   RDS runtime_persistent — pg_database_size + row counts for the runtime tables it holds
# Appends one CSV row per iteration to /home/ubuntu/long-run-metrics.csv.
#
# Per-table counts (count_<table>) are exact COUNT(*)s. Runtime tables live across two DBs
# (runtime_transient + runtime_persistent), so per DB we first ask which of RUNTIME_TABLES it has
# (via to_regclass) then COUNT(*) only those — a static reference to a table not in that DB is a
# parse-time error. A table in neither DB yields an empty cell.
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

# ----- Runtime tables of interest (v1.0.0-alpha schema) -----
# runtime_transient has both standalone tables AND a partitioned RUNTIME_STORE 
# runtime_persistent holds sessions/tokens/consent.
RUNTIME_TABLES=(
    # runtime_transient - standalone tables
    AUTHORIZATION_CODE
    AUTHORIZATION_REQUEST
    CIBA_AUTH_REQUEST
    WEBAUTHN_SESSION
    PAR_REQUEST
    JTI_RECORD
    # runtime_transient - RUNTIME_STORE partitions
    RUNTIME_STORE_ATTRIBUTE_CACHE
    RUNTIME_STORE_FLOW_STATE
    RUNTIME_STORE_AUTHZ_CODE
    RUNTIME_STORE_AUTHZ_REQ
    RUNTIME_STORE_LOGOUT_REQ
    RUNTIME_STORE_PAR_REQ
    RUNTIME_STORE_CIBA_REQ
    RUNTIME_STORE_JTI_TOKEN
    RUNTIME_STORE_VCI_NONCE
    RUNTIME_STORE_VCI_OFFER
    RUNTIME_STORE_VP_STATE
    # runtime_persistent
    SSO_SESSION
    SSO_SESSION_CONTEXT
    SSO_SESSION_PARTICIPANT
    REVOKED_TOKEN
    CONSENT
    CONSENT_AUTHORIZATION
    CONSENT_AUDIT
)

# ----- CSV header (written once) -----
if [[ ! -f "$OUTPUT_CSV" ]]; then
    header="timestamp,thunder_rss_kb,thunder_vsz_kb,thunder_disk_used_bytes,thunder_disk_avail_bytes,thunder_log_bytes,runtime_transient_bytes,runtime_persistent_bytes"
    for t in "${RUNTIME_TABLES[@]}"; do
        header+=",count_$(echo "$t" | tr '[:upper:]' '[:lower:]')"
    done
    echo "$header" > "$OUTPUT_CSV"
fi

echo "[long-run-sampler] Starting sampler. Interval=${SAMPLE_INTERVAL_SECONDS}s. Output=${OUTPUT_CSV}"
echo "[long-run-sampler] Waiting 60s for JMeter to start before entering the main loop..."
sleep 60

sample_once() {
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Thunder host stats via the ssh alias. All values default to empty on failure.
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
# Sum the stdout redirect log and the native rolling logs under repository/logs.
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

    # RDS: per-DB size + exact COUNT(*) per table. Per DB, discover which of RUNTIME_TABLES resolve
    # there (to_regclass, same search_path an unqualified COUNT(*) uses) then COUNT(*) only those;
    # a static ref to a table not in that DB would be a parse-time error. Any psql failure -> WARN
    # + empty cells for this one sample, never an abort.
    local rt_bytes="" rp_bytes=""
    declare -A counts
    for t in "${RUNTIME_TABLES[@]}"; do counts[$t]=""; done

    # Postgres array literal of the table names.
    local tbl_array; tbl_array="{$(IFS=,; echo "${RUNTIME_TABLES[*]}")}"

    local db size present cnt_out
    local -a present_arr cnts
    for db in runtime_transient runtime_persistent; do
        # DB size (doubles as the connectivity check).
        if ! size=$(psql -h "$RDS_HOST" -U "$DB_USER" -d "$db" -qAt \
                    -c "SELECT pg_database_size('$db');" 2>/dev/null); then
            echo "[long-run-sampler] WARN: psql size query to $db failed at $ts"
            continue
        fi
        if [[ "$db" == "runtime_transient" ]]; then rt_bytes="$size"; else rp_bytes="$size"; fi

        # Which tables actually exist in this DB.
        if ! present=$(psql -h "$RDS_HOST" -U "$DB_USER" -d "$db" -qAt \
                       -c "SELECT t FROM unnest('$tbl_array'::text[]) AS t WHERE to_regclass(format('%I', t)) IS NOT NULL;" 2>/dev/null); then
            echo "[long-run-sampler] WARN: table discovery on $db failed at $ts"
            continue
        fi
        [[ -z "$present" ]] && continue
        mapfile -t present_arr <<< "$present"

        # Exact COUNT(*) for just the present tables, one batched call; results map back by index.
        local count_sql=""
        for t in "${present_arr[@]}"; do count_sql+="SELECT COUNT(*) FROM \"$t\"; "; done
        if cnt_out=$(psql -h "$RDS_HOST" -U "$DB_USER" -d "$db" -qAt -c "$count_sql" 2>/dev/null); then
            mapfile -t cnts <<< "$cnt_out"
            for i in "${!present_arr[@]}"; do counts[${present_arr[$i]}]="${cnts[$i]:-}"; done
        else
            echo "[long-run-sampler] WARN: count query on $db failed at $ts"
        fi
    done

    # Emit one CSV row (base columns + per-table counts in RUNTIME_TABLES order).
    local row="$ts,$rss_kb,$vsz_kb,$disk_used,$disk_avail,$log_bytes,$rt_bytes,$rp_bytes"
    for t in "${RUNTIME_TABLES[@]}"; do
        row+=",${counts[$t]}"
    done
    echo "$row" >> "$OUTPUT_CSV"
    echo "[long-run-sampler] Sampled: $row"
}

while :; do
    if ! pgrep -f "[r]un-performance-tests.sh" >/dev/null 2>&1; then
        echo "[long-run-sampler] run-performance-tests.sh stopped. Taking final sample and exiting."
        sample_once
        break
    fi
    sample_once
    sleep "$SAMPLE_INTERVAL_SECONDS"
done

echo "[long-run-sampler] Done."
