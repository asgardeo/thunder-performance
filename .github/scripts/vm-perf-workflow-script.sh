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
# Run VM Performance tests on AWS
# ----------------------------------------------------------------------------

RESOURCES_DIR=$WORKSPACE/resources

echo "WORKSPACE Directory: $WORKSPACE"

echo ""
echo "Starting performance test with params:"
echo "    DEPLOYMENT: $DEPLOYMENT"
echo "    THUNDER_INSTANCE_TYPE: $THUNDER_INSTANCE_TYPE"
echo "    DB_INSTANCE_TYPE: $DB_INSTANCE_TYPE"
echo "    CONCURRENCY: $CONCURRENCY"
echo "    PERFORMANCE_REPO: $GITHUB_SERVER_URL/$GITHUB_REPOSITORY"
echo "    BRANCH: $GITHUB_REF_NAME"
echo "    DB_TYPE: $DB_TYPE"
echo "    BUILD_CAUSE: $BUILD_CAUSE"
echo "    Build Triggered By $BUILD_USER_EMAIL"
echo "=========================================================="

cd $WORKSPACE/perf-scripts/$DEPLOYMENT

echo ""
echo "Starting performance test..."

cmd="./start-performance.sh -k $RESOURCES_DIR/thunder-perf-test.pem \
-c is-perf-cert -j $RESOURCES_DIR/apache-jmeter-5.6.3.tgz -n $WORKSPACE/thunder.zip -q $BUILD_USER_EMAIL -m $DB_TYPE -r $CONCURRENCY -v $MODE -f $DEPLOYMENT -z $USE_DELAYS "

if [[ ! -z $ADDITIONAL_PARAMS_TO_RUN_PERFORMANCE_SCRIPT ]]; then
	cmd+=" $ADDITIONAL_PARAMS_TO_RUN_PERFORMANCE_SCRIPT"
fi

echo "$cmd"

eval $cmd

echo "=========================================================="
