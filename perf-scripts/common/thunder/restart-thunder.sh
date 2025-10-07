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

function usage() {
    echo ""
    echo "Usage: "
    echo "$0  [-c <carbon_home>] [-w <waiting_time>]"
    echo ""
    echo "-c: The Thunder path."
    echo "-w: The waiting time in seconds until the server restart.."
    echo "-h: Display this help and exit."
    echo ""
}

while getopts "c:w:h" opts; do
    case $opts in
    c)
        carbon_home=${OPTARG}
        ;;
    w)
        waiting_time=${OPTARG}
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

echo ""
echo "Cleaning up any previous log files..."
rm -rf $carbon_home/repository/logs/*

echo "Restarting Thunder..."
cd "$carbon_home"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="thunder_${TIMESTAMP}.log"
bash start.sh > "$LOG_FILE" 2>&1 &
cd "../"

echo "Waiting $waiting_time seconds..."
sleep $waiting_time

echo "Finished starting Thunder..."
