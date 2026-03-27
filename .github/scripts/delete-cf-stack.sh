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
# Delete the AWS CloudFormation stack created for performance testing.
# Required env var: STACK_ID
# ----------------------------------------------------------------------------

export AWS_DEFAULT_OUTPUT="json"

if [[ -z $STACK_ID ]]; then
    echo "STACK_ID is not set. Skipping stack deletion."
    exit 0
fi

echo ""
echo "Deleting CloudFormation stack: $STACK_ID"
stack_delete_start_time=$(date +%s)

aws cloudformation delete-stack --stack-name "$STACK_ID"

echo ""
echo "Polling till the stack deletion completes..."
aws cloudformation wait stack-delete-complete --stack-name "$STACK_ID"

stack_delete_duration=$(echo "$(date +%s) - $stack_delete_start_time" | bc)
printf "Stack deletion time: %d minute(s) and %02d second(s)\n" \
    "$((stack_delete_duration / 60))" "$((stack_delete_duration % 60))"

echo ""
echo "CloudFormation stack deleted successfully."
