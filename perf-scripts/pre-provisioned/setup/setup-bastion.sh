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

lb_host=""
rds_host=""
lb_alias=loadbalancer
bastion_user=""

function usage() {
    echo ""
    echo "Usage: "
    echo "$0 -l <lb_host> -r <rds_host>"
    echo ""
    echo "-l: The hostname of Load balancer instance."
    echo "-r: The hostname of RDS instance."
    echo "-u: The user of the bastion node."
    echo "-h: Display this help and exit."
    echo ""
}

while getopts "l:r:u:h" opts; do
    case $opts in
    l)
        lb_host=${OPTARG}
        ;;
    r)
        rds_host=${OPTARG}
        ;;
    u)
        bastion_user=${OPTARG}
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

echo "bastion_user: $bastion_user"

if [[ -z $lb_host ]]; then
    echo "Please provide the private hostname of Load balancer instance."
    exit 1
fi

if [[ -z $rds_host ]]; then
    echo "Please provide the private hostname of the RDS instance."
    exit 1
fi

function get_ssh_hostname() {
    sudo -u $bastion_user ssh -G "$1" | awk '/^hostname / { print $2 }'
}

function cleanup() {
    sudo rm -rf common/ gcviewer.jar jmeter/ payloads/ results/ setup/ workspace/ 
    sudo rm temp.pem results.zip
}

echo ""
echo "Setting up required files..."
echo "============================================"
cd /home/$bastion_user || exit 0

cleanup
mkdir workspace
cd workspace || exit 0

echo ""
echo "Extracting cloud performance distribution..."
echo "============================================"
tar -C /home/$bastion_user/workspace -xzf /home/$bastion_user/thunder-performance-pre-provisioned-*.tar.gz

echo ""
echo "Running JMeter setup script..."
echo "============================================"
cd /home/$bastion_user || exit 0
# Creates a temporary empty key
touch temp.pem
workspace/setup/setup-jmeter-client-is.sh -g -k ./temp.pem \
            -i /home/$bastion_user \
            -c /home/$bastion_user \
            -f /home/$bastion_user/apache-jmeter-*.tgz \
            -a $lb_alias -n "$lb_host"\
            -a rds -n "$rds_host"
sudo chown -R $bastion_user:$bastion_user workspace
sudo chown -R $bastion_user:$bastion_user apache-jmeter-*
sudo chown -R $bastion_user:$bastion_user /tmp/jmeter.log
sudo chown -R $bastion_user:$bastion_user jmeter.log
