#!/bin/bash +x
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

# Create workspace
BUILD_DIR=$(pwd)
RESOURCES_DIR=$BUILD_DIR/resources
cd $BUILD_DIR
mkdir -p resources
echo "Build Dir:$BUILD_DIR | Resources_Dir: $RESOURCES_DIR | Workspace: $WORKSPACE"
MODE=$RUN_MODE

echo ""
echo "Starting performance test with params:"
echo "    CONCURRENT_USERS: $CONCURRENT_USERS"
echo "    MODE: $MODE"
echo "    PURPOSE: $BUILD_PURPOSE"
echo "=========================================================="
echo "Thunder Perf Environment - Status: "
curl -s -i https://thunder.local/health/liveness | head -1

echo "Changing Directory to Thunder Product Repository | Branch: $BRANCH"
cd $WORKSPACE

cd pre-provisioned

# Build and run perf-tests.
echo ""
echo "Building project..."
echo "=========================================================="
mvn clean install

echo ""
echo "Starting test..."
echo "=========================================================="
  
# Define and execute start-performance command.
echo "Bastion IP init: $BASTION_NODE_IP"
cmd="./start-performance.sh -b $BASTION_NODE_IP -n $DATABASE_HOST_NAME -d $THUNDER_HOST_NAME -t $MODE -- -d 15 -w 2 -q $POPULATE_TEST_DATA -c $CONCURRENCY"

$cmd

# Copy results directory to build path to be saved as a build artifact.
cp -r results-* $BUILD_PATH/

rm -rf ~/.ssh/
