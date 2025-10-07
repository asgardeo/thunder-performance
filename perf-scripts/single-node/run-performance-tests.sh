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
# Run Ballerina Performance Tests
# ----------------------------------------------------------------------------

script_dir=$(dirname "$0")

wso2thunder_host_alias=thunder1
lb_ssh_host_alias=loadbalancer
rds_ssh_host_alias=rds

# Execute common script
. $script_dir/perf-test-thunder.sh "$@"

# Source test scenarios
source $script_dir/test_scenarios.sh

function before_execute_test_scenario() {

    ssh $wso2thunder_host_alias "./restart-thunder.sh"

    # Skipping Cleaning DBs as that is not required in Thunder
    # echo "Cleaning databases..."
    # rds_host=$(get_ssh_hostname $rds_ssh_host_alias)
    # clean_database "$@" "$rds_host"
}

function after_execute_test_scenario() {

    thunder_home="/home/ubuntu/thunder"
    write_server_metrics $wso2thunder_host_alias $wso2thunder_host_alias
    # Download all thunder*.log files
    ssh $wso2thunder_host_alias "find $thunder_home -name 'thunder*.log'" | while read -r log_file; do
        base_name=$(basename "$log_file")
        download_file "$wso2thunder_host_alias" "$log_file" "$wso2thunder_host_alias-$base_name"
    done
}

test_scenarios
