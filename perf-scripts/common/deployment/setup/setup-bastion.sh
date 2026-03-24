#!/usr/bin/env bash
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
# Setup the bastion node to be used as the JMeter client.
# ----------------------------------------------------------------------------

no_of_nodes=""
wso2_thunder_1_ip=""
lb_host=""
rds_host=""
wso2thunder_1_host_alias=wso2thunder
lb_alias=loadbalancer

function usage() {
    echo ""
    echo "Usage: "
    echo "$0 -w <wso2_thunder_1_ip> -l <lb_host> -r <rds_host>"
    echo ""
    echo "-w: The private IP of WSO2 Thunder node 1."
    echo "-l: The private hostname of Load balancer instance."
    echo "-r: The private hostname of RDS instance."
    echo "-h: Display this help and exit."
    echo ""
}

while getopts "n:w:l:r:h" opts; do
    case $opts in
    n)
        no_of_nodes=${OPTARG}
        ;;
    w)
        wso2_thunder_1_ip=${OPTARG}
        ;;
    l)
        lb_host=${OPTARG}
        ;;
    r)
        rds_host=${OPTARG}
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

if [[ -z $lb_host ]]; then
    echo "Please provide the private hostname of Load balancer instance."
    exit 1
fi

if [[ -z $rds_host ]]; then
    echo "Please provide the private hostname of the RDS instance."
    exit 1
fi

function get_ssh_hostname() {
    sudo -u ubuntu ssh -G "$1" | awk '/^hostname / { print $2 }'
}

echo ""
echo "Setting up required files..."
echo "============================================"
cd /home/ubuntu || exit 0
mkdir workspace
cd workspace || exit 0

echo ""
echo "Extracting is performance distribution..."
echo "============================================"
tar -C /home/ubuntu/workspace -xzf /home/ubuntu/performance-thunder-*.tar.gz

echo ""
echo "Running JMeter setup script..."
echo "============================================"
cd /home/ubuntu || exit 0

echo "[DIAG] Checking JMeter tgz on bastion..."
ls -lh /home/ubuntu/apache-jmeter-*.tgz || echo "[DIAG] WARNING: JMeter tgz not found at /home/ubuntu/"
echo "[DIAG] Checking if JMeter dir already exists (would skip extraction)..."
if [[ -d /home/ubuntu/apache-jmeter-5.6.3 ]]; then
    echo "[DIAG] WARNING: /home/ubuntu/apache-jmeter-5.6.3 already exists — extraction will be skipped by install-jmeter.sh"
    ls /home/ubuntu/apache-jmeter-5.6.3/lib/ext/ | grep -E "ApacheJMeter_core|jmeter-studio" || echo "[DIAG] Neither ApacheJMeter_core.jar nor jmeter-studio jar found in existing dir"
else
    echo "[DIAG] /home/ubuntu/apache-jmeter-5.6.3 does not exist — extraction will proceed"
fi
echo "[DIAG] Verifying ApacheJMeter_core.jar is present in tgz..."
tar -tf /home/ubuntu/apache-jmeter-*.tgz 2>/dev/null | grep ApacheJMeter_core || echo "[DIAG] WARNING: ApacheJMeter_core.jar NOT found in tgz"

if [[ -z $no_of_nodes ]]; then
    echo "Please provide the number of Thunder nodes in the deployment."
    exit 1
elif [[ $no_of_nodes -eq 1 ]]; then
    workspace/setup/setup-jmeter-client-thunder.sh -g -k /home/ubuntu/private_key.pem \
                -i /home/ubuntu \
                -c /home/ubuntu \
                -f /home/ubuntu/apache-jmeter-*.tgz \
                -a $wso2thunder_1_host_alias -n "$wso2_thunder_1_ip" \
                -a $lb_alias -n "$lb_host" \
                -a rds -n "$rds_host"
else
    echo "Invalid value for no_of_nodes. Please provide a valid number."
    exit 1
fi

echo "[DIAG] JMeter setup complete. Checking for ApacheJMeter_core.jar..."
ls /home/ubuntu/apache-jmeter-*/lib/ext/ApacheJMeter_core.jar 2>/dev/null \
    && echo "[DIAG] ApacheJMeter_core.jar is present" \
    || echo "[DIAG] ERROR: ApacheJMeter_core.jar is MISSING after setup"

sudo chown -R ubuntu:ubuntu workspace
sudo chown -R ubuntu:ubuntu apache-jmeter-*
sudo chown -R ubuntu:ubuntu jmeter.log

echo ""
echo "Copying files to Nginx instance..."
echo "============================================"
sudo -u ubuntu scp -r /home/ubuntu/workspace/setup/resources/ $lb_alias:/home/ubuntu/
sudo -u ubuntu scp /home/ubuntu/workspace/setup/setup-nginx.sh $lb_alias:/home/ubuntu/

echo ""
echo "Setting up Nginx..."
echo "============================================"

if [[ $no_of_nodes -eq 1 ]]; then
    sudo -u ubuntu ssh $lb_alias ./setup-nginx.sh -n "$no_of_nodes" -i "$wso2_thunder_1_ip"
fi
