#!/bin/bash
# Copyright (c) 2025, WSO2 LLC. (https://www.wso2.com).
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
# Restart Thunder
# ----------------------------------------------------------------------------

default_carbon_home=$(realpath ~/thunder)
carbon_home=$default_carbon_home
default_waiting_time=30
waiting_time=$default_waiting_time
default_port=8090
port=$default_port
# Grace period for a TERM'd server to exit before it is killed outright.
stop_timeout=20
# Settle time after the port starts listening, before the caller drives traffic.
settle_time=5

function usage() {
    echo ""
    echo "Usage: "
    echo "$0  [-c <carbon_home>] [-w <waiting_time>] [-p <port>]"
    echo ""
    echo "-c: The Thunder path."
    echo "-w: The time in seconds to wait for the server to start listening."
    echo "-p: The port Thunder listens on. Default $default_port."
    echo "-h: Display this help and exit."
    echo ""
}

while getopts "c:w:p:h" opts; do
    case $opts in
    c)
        carbon_home=${OPTARG}
        ;;
    w)
        waiting_time=${OPTARG}
        ;;
    p)
        port=${OPTARG}
        ;;
    h)
        usage
        exit 0
        ;;
    \?)
        usage
        exit 1
        ;;
    esac
done

if [ ! -d $carbon_home ]; then
    echo "Please provide the Thunder path."
    exit 1
fi

if [[ -z $waiting_time ]]; then
    echo "Please provide the waiting time."
    exit 1
fi

# PIDs holding the listen socket on $port. ss is preferred (iproute2 is always present on the
# perf AMIs); lsof and a name match are fallbacks. Only the current user's processes are
# visible without root, which is enough since Thunder runs as the same user as this script.
function listening_pids() {
    local pids=""
    if command -v ss >/dev/null 2>&1; then
        pids=$(ss -lptnH "sport = :$port" 2>/dev/null | grep -oE 'pid=[0-9]+' | cut -d= -f2)
    fi
    if [[ -z $pids ]] && command -v lsof >/dev/null 2>&1; then
        pids=$(lsof -ti "tcp:$port" -sTCP:LISTEN 2>/dev/null)
    fi
    if [[ -z $pids ]]; then
        pids=$(pgrep -f "$carbon_home/thunderid" 2>/dev/null | grep -v "^$$\$")
    fi
    # grep keeps this empty when nothing matched, so callers can test with -z.
    printf '%s\n' $pids | grep -E '^[0-9]+$' | sort -u | tr '\n' ' '
}

function port_is_free() {
    local pids
    pids=$(listening_pids)
    [[ -z "${pids// /}" ]]
}

# Stop whatever is on the port. Without this the per-phase restart is a no-op: start.sh exits
# with "Port 8090 is already in use", and because it is backgrounded nothing notices, so a
# single server ends up serving every phase of the run.
function stop_thunder() {
    local pids
    pids=$(listening_pids)
    if [[ -z $pids ]]; then
        echo "No process is listening on port $port."
        return 0
    fi

    echo "Stopping Thunder (PIDs: $pids)..."
    kill -TERM $pids 2>/dev/null

    local waited=0
    while ((waited < stop_timeout)); do
        if port_is_free; then
            echo "Thunder stopped after ${waited}s."
            return 0
        fi
        sleep 1
        ((waited++))
    done

    pids=$(listening_pids)
    if [[ -n $pids ]]; then
        echo "Thunder did not exit within ${stop_timeout}s; sending KILL to $pids."
        kill -KILL $pids 2>/dev/null
        sleep 2
    fi

    if ! port_is_free; then
        echo "ERROR: port $port is still held by '$(listening_pids)' after KILL."
        return 1
    fi
    echo "Thunder stopped."
}

echo ""
if ! stop_thunder; then
    exit 1
fi

# Drop the previous phase's logs. The old cleanup targeted repository/logs, which Thunder does
# not use, so thunder_<timestamp>.log was never removed and grew across the whole run. Logs are
# scp'd off the node in after_execute_test_scenario, so each phase's log is already preserved
# in that phase's report directory before this runs. The setup log is kept for the whole run.
echo "Cleaning up any previous log files..."
rm -rf "$carbon_home"/repository/logs/* 2>/dev/null
find "$carbon_home" -maxdepth 1 -name 'thunder_*.log' ! -name 'thunder_setup_*.log' -delete 2>/dev/null

echo "Restarting Thunder..."
cd "$carbon_home"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="thunder_${TIMESTAMP}.log"
bash start.sh > "$LOG_FILE" 2>&1 &
start_pid=$!
cd "../"

echo "Waiting up to $waiting_time seconds for Thunder to listen on port $port..."
waited=0
while ((waited < waiting_time)); do
    if ! port_is_free; then
        break
    fi
    # start.sh exiting early means the server failed to come up at all.
    if ! kill -0 "$start_pid" 2>/dev/null && port_is_free; then
        break
    fi
    sleep 1
    ((waited++))
done

if port_is_free; then
    echo "ERROR: Thunder is not listening on port $port after ${waited}s."
    echo "--- tail of $carbon_home/$LOG_FILE ---"
    tail -n 30 "$carbon_home/$LOG_FILE" 2>/dev/null || echo "(no log file)"
    exit 1
fi

echo "Thunder is listening on port $port after ${waited}s; settling for ${settle_time}s..."
sleep $settle_time

echo "Finished starting Thunder..."
