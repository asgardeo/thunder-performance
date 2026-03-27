#!/bin/bash -e
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
# Contains common shell script functions.
# ----------------------------------------------------------------------------

function check_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Please install $1"
        exit 1
    fi
}

function format_time() {
    # Duration in seconds
    local duration="$1"
    local minutes=$(echo "$duration/60" | bc)
    local seconds=$(echo "$duration-$minutes*60" | bc)
    if [[ $minutes -ge 60 ]]; then
        local hours=$(echo "$minutes/60" | bc)
        minutes=$(echo "$minutes-$hours*60" | bc)
        printf "%d hour(s), %02d minute(s) and %02d second(s)\n" "$hours" "$minutes" "$seconds"
    elif [[ $minutes -gt 0 ]]; then
        printf "%d minute(s) and %02d second(s)\n" "$minutes" "$seconds"
    else
        printf "%d second(s)\n" "$seconds"
    fi
}

function measure_time() {
    local end_time=$(date +%s)
    local start_time=$1
    local duration=$(echo "$end_time - $start_time" | bc)
    echo "$duration"
}

function ssh_bastion_cmd() {

    local ssh_command="ssh -i $key_file -o "StrictHostKeyChecking=no" -t ubuntu@$bastion_node_ip $1"
    echo "$ssh_command"
    $ssh_command || echo "Remote ssh command failed."
}

function scp_bastion_cmd() {

    local scp_command="scp -i $key_file -o "StrictHostKeyChecking=no" $1 ubuntu@$bastion_node_ip:$2"
    echo "$scp_command"
    $scp_command || echo "Remote scp command failed."
}

function scp_r_bastion_cmd() {

    local scp_command="scp -r -i $key_file -o "StrictHostKeyChecking=no" $1 ubuntu@$bastion_node_ip:$2"
    echo "$scp_command"
    $scp_command || echo "Remote scp command failed."
}


