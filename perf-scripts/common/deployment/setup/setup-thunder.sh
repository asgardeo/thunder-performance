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
# Setup Thunder pack.
# ----------------------------------------------------------------------------

function usage() {
    echo ""
    echo "Usage: "
    echo "$0 -a <HOST_ALIAS> -i <IS_NODE_IP> -w <OTHER_IS_NODE_IP> -r <RDS_IP> "
    echo ""
    echo "-a: Host alias of the Thunder node to be setup."
    echo "-i: The IP of thunder node 1."
    echo "-r: The IP address of RDS."
    echo "-h: Display this help and exit."
    echo "-m: Database type."
    echo ""
}

while getopts "a:n:i:r:m:h" opts; do
    case $opts in
    a)
        is_host_alias=${OPTARG}
        ;;
    n)
        no_of_nodes=${OPTARG}
        ;;
    i)
        wso2_thunder_1_ip=${OPTARG}
        ;;
    r)
        db_instance_ip=${OPTARG}
        ;;
    m)
        db_type=${OPTARG}
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

if [[ -z $is_host_alias ]]; then
    echo "Please provide the host alias for the WSO2 Thunder node."
    exit 1
fi

if [[ -z $db_instance_ip ]]; then
    echo "Please provide the db instance IP address."
    exit 1
fi

if [[ -z $db_type ]]; then
    echo "Please provide the database type."
    exit 1
fi

echo ""
echo "Copying Is server setup files..."
echo "-------------------------------------------"

sudo -u ubuntu scp setup/update-thunder-conf.sh "$is_host_alias":/home/ubuntu/
sudo -u ubuntu scp -r setup/resources/ "$is_host_alias":/home/ubuntu/
sudo -u ubuntu scp thunder.zip "$is_host_alias":/home/ubuntu/

sudo -u ubuntu ssh "$is_host_alias" mkdir sar setup
sudo -u ubuntu scp workspace/setup/setup-common.sh "$is_host_alias":/home/ubuntu/setup/
sudo -u ubuntu scp workspace/sar/install-sar.sh "$is_host_alias":/home/ubuntu/sar/
sudo -u ubuntu scp workspace/thunder/restart-thunder.sh "$is_host_alias":/home/ubuntu/
sudo -u ubuntu ssh "$is_host_alias" sudo ./setup/setup-common.sh -p zip -p jq -p bc

setup_thunder_node_command=""

if [[ $no_of_nodes -eq 1 ]]; then
    setup_thunder_node_command="ssh -i ~/private_key.pem -o "StrictHostKeyChecking=no" -t ubuntu@$wso2_thunder_1_ip \
      ./update-thunder-conf.sh -n $no_of_nodes -r $db_instance_ip -m $db_type"
else
    echo "Invalid value for no_of_nodes. Please provide a valid number."
    exit 1
fi

echo ""
echo "Running update-thunder-conf script: $setup_thunder_node_command"
echo "============================================"
# Handle any error and let the script continue.
$setup_thunder_node_command || echo "Remote ssh command to setup Thunder node failed."
