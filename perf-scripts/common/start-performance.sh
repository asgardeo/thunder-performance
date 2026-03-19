#!/bin/bash -e
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
# Contains common code from start-performance.sh scripts.
# ----------------------------------------------------------------------------

script_start_time=$(date +%s)
timestamp=$(date +%Y-%m-%d--%H-%M-%S)

key_file=""
certificate_name=""
jmeter_setup=""
thunder_setup=""
concurrency=""
default_db_username="asgthunder"
db_username="$default_db_username"
default_db_password="asgthunder"
db_password="$default_db_password"
db_type="postgres"

results_dir="$PWD/results-$timestamp"

function usage() {
    echo ""
    echo "Usage: "
    echo "$0 -k <key_file> -c <certificate_name> -j <jmeter_setup_path> -n <IS_zip_file_path>"
    echo "   [-u <db_username>] [-p <db_password>] [-r <concurrency>] [-m <db_type>]"
    echo "   [-q <user_tag>] [-g <number_of_nodes>] [-v <testing_mode>] [-h]"
    echo ""
    echo "-k: The Amazon EC2 key file to be used to access the instances."
    echo "-c: The name of the IAM certificate."
    echo "-y: The token issuer type."
    echo "-q: User tag who triggered the build."
    echo "-r: Concurrency (50-500, 500-3000, 50-3000)"
    echo "-j: The path to JMeter setup."
    echo "-n: The Thunder server zip."
    echo "-u: The database username. Default: $default_db_username."
    echo "-p: The database password. Default: $default_db_password."
    echo "-g: Number of Thunder nodes."
    echo "-m: Database type. Default: $db_type."
    echo "-h: Display this help and exit."
    echo ""
}

function execute_db_command() {

    local db_host="$1"
    local sql_file="$2"
    # Construct the database-specific command
    local db_command=""
    if [[ $db_type == "postgres" ]]; then
        db_command="psql -h $db_host -U asgthunder -d postgres -f $sql_file"
    else
        echo "Unsupported database type: $db_type"
        return 1
    fi
    ssh_bastion_cmd "$db_command"
}

while getopts "q:k:c:j:n:u:p:g:m:r:h" opts; do
    case $opts in
    q)
        user_tag=${OPTARG}
        ;;
    k)
        key_file=${OPTARG}
        ;;
    c)
        certificate_name=${OPTARG}
        ;;
    j)
        jmeter_setup=${OPTARG}
        ;;
    n)
        thunder_setup=${OPTARG}
        ;;
    u)
        db_username=${OPTARG}
        ;;
    p)
        db_password=${OPTARG}
        ;;
    g)
        no_of_nodes=${OPTARG}
        ;;
    m)
        db_type=${OPTARG}
        ;;
    r)
        concurrency=${OPTARG}
        ;;
    h)
        usage
        exit 0
        ;;
    \?)
        echo "Invalid option: -$OPTARG"
        echo "May be needed for the perf-test script."
        ;;
    esac
done
shift "$((OPTIND - 1))"

# All remaining positional args are forwarded to run-performance-tests.sh
run_performance_tests_options=("-b ${db_type} -g ${no_of_nodes} -r ${concurrency} -v $@")

if [[ -z $user_tag ]]; then
    echo "Please provide the user tag."
    exit 1
fi

if [[ ! -f $key_file ]]; then
    echo "Please provide the key file."
    exit 1
fi

if [[ ${key_file: -4} != ".pem" ]]; then
    echo "AWS EC2 Key file must have .pem extension"
    exit 1
fi

if [[ -z $jmeter_setup ]]; then
    echo "Please provide the path to JMeter setup."
    exit 1
fi

if [[ -z $certificate_name ]]; then
    echo "Please provide the name of the IAM certificate."
    exit 1
fi

if [[ -z $thunder_setup ]]; then
    echo "Please provide is zip file path."
    exit 1
fi

if [[ $no_of_nodes -ne 1 ]]; then
    echo "Invalid value for no_of_nodes. Please provide a valid number."
    exit 1
fi

# Checking for the availability of commands in jenkins.
check_command bc
check_command unzip
check_command jq
check_command python

mkdir "$results_dir"
echo ""
echo "Results will be downloaded to $results_dir"

echo ""
echo "Copying CF test metadata to results directory..."
cp "${WORKSPACE}/cf-test-metadata.json" "$results_dir/cf-test-metadata.json"

echo ""
echo "Extracting Thunder Performance Distribution to $results_dir"
tar -xf target/performance-thunder-singlenode-*.tar.gz -C "$results_dir"

cp run-performance-tests.sh "$results_dir"/jmeter/
estimate_command="$results_dir/jmeter/run-performance-tests.sh -t ${run_performance_tests_options[*]}"
echo ""
echo "Estimating time for performance tests: $estimate_command"
$estimate_command

# Get absolute paths
key_file=$(realpath "$key_file")

# IPs are provided by the Create CloudFormation Stack workflow step
bastion_node_ip="${BASTION_NODE_IP:?'BASTION_NODE_IP environment variable is not set'}"
nginx_instance_ip="${NGINX_INSTANCE_IP:?'NGINX_INSTANCE_IP environment variable is not set'}"
wso2_thunder_1_ip="${WSO2_THUNDER_1_IP:?'WSO2_THUNDER_1_IP environment variable is not set'}"
rds_host="${RDS_HOST:?'RDS_HOST environment variable is not set'}"

echo "Bastion Node IP: $bastion_node_ip"
echo "Nginx Instance IP: $nginx_instance_ip"
echo "WSO2 Thunder Node 1 IP: $wso2_thunder_1_ip"
echo "RDS Host: $rds_host"

echo ""
echo "Copying files to Bastion node..."
echo "============================================"
scp_r_bastion_cmd "$results_dir/setup" "/home/ubuntu/"
scp_bastion_cmd "target/performance-thunder-*.tar.gz" "/home/ubuntu"

scp_bastion_cmd "$jmeter_setup" "/home/ubuntu/"
scp_bastion_cmd "$thunder_setup" "/home/ubuntu/thunder.zip"
scp_bastion_cmd "$key_file" "/home/ubuntu/private_key.pem"

echo ""
echo "Running Bastion Node setup script..."
echo "============================================"
ssh_bastion_cmd "sudo ./setup/setup-bastion.sh -n $no_of_nodes -w $wso2_thunder_1_ip -r $rds_host -l $nginx_instance_ip"

echo ""
echo "Creating databases in RDS..."
echo "============================================"
ssh_bastion_cmd "cd /home/ubuntu/ ; unzip -q thunder.zip ; mv thunder-* thunder"
execute_db_command "$rds_host" "/home/ubuntu/workspace/setup/resources/$db_type/create_database.sql"

echo ""
echo "Running Thunder node 1 setup script..."
echo "============================================"
ssh_bastion_cmd "./setup/setup-thunder.sh -n $no_of_nodes -m $db_type -a wso2thunder -i $wso2_thunder_1_ip -r $rds_host"

echo ""
echo "Running performance tests..."
echo "============================================"
scp_bastion_cmd "run-performance-tests.sh" "/home/ubuntu/workspace/jmeter"
ssh_bastion_cmd "./workspace/jmeter/run-performance-tests.sh -p 443 ${run_performance_tests_options[*]}"

echo ""
echo "Downloading results..."
echo "============================================"
download="scp -i $key_file -o StrictHostKeyChecking=no ubuntu@$bastion_node_ip:/home/ubuntu/results.zip $results_dir/"
echo "$download"
$download || echo "Remote download failed"

if [[ ! -f $results_dir/results.zip ]]; then
    echo ""
    echo "Failed to download the results.zip"
    exit 0
fi

echo ""
echo "Creating summary.csv..."
echo "============================================"
cd "$results_dir"
unzip -q results.zip
wget -q http://sourceforge.net/projects/gcviewer/files/gcviewer-1.35.jar/download -O gcviewer.jar
"$results_dir"/jmeter/create-summary-csv.sh -d results -n "WSO2 Thunder" -p wso2thunder -c "Heap Size" \
    -c "Concurrent Users" -r "([0-9]+[a-zA-Z])_heap" -r "([0-9]+)_users" -i -l -k 1 -g gcviewer.jar

echo "Creating summary results markdown file..."

./summary/summary-modifier.py
./jmeter/create-summary-markdown.py --json-files cf-test-metadata.json results/test-metadata.json --column-names \
    "Concurrent Users" "95th Percentile of Response Time (ms)"

rm -rf cf-test-metadata.json cloudformation/ common/ gcviewer.jar is/ jmeter/ jtl-splitter/ netty-service/ payloads/ sar/ setup/ results/ thunder/restart-thunder.sh summary/

echo ""
echo "Done."
