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
# Create the AWS CloudFormation stack for performance testing.
# Writes stack IPs and stack_id to $GITHUB_OUTPUT, and writes
# cf-test-metadata.json to $WORKSPACE for use in the test summary report.
# ----------------------------------------------------------------------------

export AWS_DEFAULT_OUTPUT="json"

# Defaults not exposed as workflow inputs
BASTION_INSTANCE_TYPE="t3a.large"
NGINX_INSTANCE_TYPE="t3a.medium"
DB_USERNAME="asgthunder"
DB_PASSWORD="asgthunder"
CERTIFICATE_NAME="is-perf-cert"
KEY_NAME="thunder-perf-test"
NO_OF_NODES_STRING="single"
MINIMUM_STACK_CREATION_WAIT_TIME=10

echo "Creating CloudFormation stack:"
echo "    DEPLOYMENT: $DEPLOYMENT"
echo "    THUNDER_INSTANCE_TYPE: $THUNDER_INSTANCE_TYPE"
echo "    DB_INSTANCE_TYPE: $DB_INSTANCE_TYPE"
echo "    CONCURRENCY: $CONCURRENCY"
echo "    DB_TYPE: $DB_TYPE"
echo "=========================================================="

cd $WORKSPACE/perf-scripts/$DEPLOYMENT

timestamp=$(date +%Y-%m-%d--%H-%M-%S)
random_number=$RANDOM

# Enable high concurrency if concurrency pattern has 4-digit numbers
enable_high_concurrency=false
if [[ $CONCURRENCY =~ ^([0-9]{4}-[0-9]{3}|[0-9]{3}-[0-9]{4}|[0-9]{4}-[0-9]{4})$ ]]; then
    enable_high_concurrency=true
fi

echo ""
echo "Preparing CloudFormation template..."
echo "============================================"
echo "random_number: $random_number"
template_file_name="new-single-node.yml"
cp single-node.yaml "$template_file_name"
sed -i "s/suffix/$random_number/" "$template_file_name"

echo ""
echo "Validating stack..."
echo "============================================"
aws cloudformation validate-template --template-body "file://$template_file_name"

# Write CF metadata for use in the test summary report
jq -n \
    --arg thunder_nodes_ec2_instance_type "$THUNDER_INSTANCE_TYPE" \
    --arg bastion_node_ec2_instance_type "$BASTION_INSTANCE_TYPE" \
    --arg nginx_ec2_instance_type "$NGINX_INSTANCE_TYPE" \
    '. | .["thunder_nodes_ec2_instance_type"]=$thunder_nodes_ec2_instance_type
       | .["bastion_node_ec2_instance_type"]=$bastion_node_ec2_instance_type
       | .["nginx_ec2_instance_type"]=$nginx_ec2_instance_type' \
    > "$WORKSPACE/cf-test-metadata.json"

stack_create_start_time=$(date +%s)
stack_name="thunder-performance-${NO_OF_NODES_STRING}-node--${timestamp}--${random_number}"
create_stack_command="aws cloudformation create-stack --stack-name $stack_name \
    --template-body file://$template_file_name --parameters \
        ParameterKey=CertificateName,ParameterValue=$CERTIFICATE_NAME \
        ParameterKey=KeyPairName,ParameterValue=$KEY_NAME \
        ParameterKey=DBUsername,ParameterValue=$DB_USERNAME \
        ParameterKey=DBPassword,ParameterValue=$DB_PASSWORD \
        ParameterKey=DBInstanceType,ParameterValue=$DB_INSTANCE_TYPE \
        ParameterKey=DBType,ParameterValue=$DB_TYPE \
        ParameterKey=WSO2InstanceType,ParameterValue=$THUNDER_INSTANCE_TYPE \
        ParameterKey=NginxInstanceType,ParameterValue=$NGINX_INSTANCE_TYPE \
        ParameterKey=BastionInstanceType,ParameterValue=$BASTION_INSTANCE_TYPE \
        ParameterKey=EnableHighConcurrencyMode,ParameterValue=$enable_high_concurrency \
        ParameterKey=UserTag,ParameterValue=$BUILD_USER_EMAIL \
    --capabilities CAPABILITY_IAM"

echo ""
echo "Creating stack..."
echo "============================================"
echo "$create_stack_command"
stack_id="$($create_stack_command)"
stack_id=$(echo "$stack_id" | jq -r .StackId)
echo ""
echo "Created stack ID: $stack_id"
rm "$template_file_name"

# Write stack_id immediately so the delete step has it even if the wait below fails
echo "stack_id=$stack_id" >> "$GITHUB_OUTPUT"

echo ""
echo "Waiting ${MINIMUM_STACK_CREATION_WAIT_TIME}m before polling for CloudFormation stack CREATE_COMPLETE status..."
sleep "${MINIMUM_STACK_CREATION_WAIT_TIME}m"

echo ""
echo "Polling till the stack creation completes..."
aws cloudformation wait stack-create-complete --stack-name "$stack_id" || {
    echo "Stack creation failed!"
    aws cloudformation describe-stack-events --stack-name "$stack_id" \
        | jq '.StackEvents[] | select(.ResourceStatus | contains("FAILED")) | {LogicalResourceId: .LogicalResourceId, ResourceStatusReason: .ResourceStatusReason}'
    echo "Exiting due to stack creation failure."
    exit 1
}

stack_create_duration=$(echo "$(date +%s) - $stack_create_start_time" | bc)
printf "Stack creation time: %d minute(s) and %02d second(s)\n" \
    "$((stack_create_duration / 60))" "$((stack_create_duration % 60))"

echo ""
echo "Getting Bastion Node Public IP..."
bastion_instance="$(aws cloudformation describe-stack-resources \
    --stack-name "$stack_id" \
    --logical-resource-id WSO2BastionInstance${random_number} \
    | jq -r '.StackResources[].PhysicalResourceId')"
bastion_node_ip="$(aws ec2 describe-instances \
    --instance-ids "$bastion_instance" \
    | jq -r '.Reservations[].Instances[].PublicIpAddress')"
echo "Bastion Node Public IP: $bastion_node_ip"

echo ""
echo "Getting Nginx Instance Private IP..."
nginx_instance="$(aws cloudformation describe-stack-resources \
    --stack-name "$stack_id" \
    --logical-resource-id WSO2NGinxInstance${random_number} \
    | jq -r '.StackResources[].PhysicalResourceId')"
nginx_instance_ip="$(aws ec2 describe-instances \
    --instance-ids "$nginx_instance" \
    | jq -r '.Reservations[].Instances[].PrivateIpAddress')"
echo "Nginx Instance Private IP: $nginx_instance_ip"

echo ""
echo "Getting WSO2 Thunder Node 1 Private IP..."
wso2thunder_auto_scaling_grp="$(aws cloudformation describe-stack-resources \
    --stack-name "$stack_id" \
    --logical-resource-id WSO2ThunderNode1AutoScalingGroup${random_number} \
    | jq -r '.StackResources[].PhysicalResourceId')"
wso2thunder_instance="$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$wso2thunder_auto_scaling_grp" \
    | jq -r '.AutoScalingGroups[].Instances[].InstanceId')"
wso2_thunder_1_ip="$(aws ec2 describe-instances \
    --instance-ids "$wso2thunder_instance" \
    | jq -r '.Reservations[].Instances[].PrivateIpAddress')"
echo "WSO2 Thunder Node 1 Private IP: $wso2_thunder_1_ip"

echo ""
echo "Getting RDS Hostname..."
rds_instance="$(aws cloudformation describe-stack-resources \
    --stack-name "$stack_id" \
    --logical-resource-id WSO2ThunderDBInstance${random_number} \
    | jq -r '.StackResources[].PhysicalResourceId')"
rds_host="$(aws rds describe-db-instances \
    --db-instance-identifier "$rds_instance" \
    | jq -r '.DBInstances[].Endpoint.Address')"
echo "RDS Hostname: $rds_host"

if [[ -z $bastion_node_ip ]]; then
    echo "Bastion node IP could not be found. Exiting..."
    exit 1
fi
if [[ -z $nginx_instance_ip ]]; then
    echo "Load balancer IP could not be found. Exiting..."
    exit 1
fi
if [[ -z $wso2_thunder_1_ip ]]; then
    echo "WSO2 node 1 IP could not be found. Exiting..."
    exit 1
fi
if [[ -z $rds_host ]]; then
    echo "RDS host could not be found. Exiting..."
    exit 1
fi

echo "bastion_node_ip=$bastion_node_ip" >> "$GITHUB_OUTPUT"
echo "nginx_instance_ip=$nginx_instance_ip" >> "$GITHUB_OUTPUT"
echo "wso2_thunder_1_ip=$wso2_thunder_1_ip" >> "$GITHUB_OUTPUT"
echo "rds_host=$rds_host" >> "$GITHUB_OUTPUT"

echo ""
echo "CloudFormation stack created successfully."
echo "=========================================================="
