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
# Kick off VM Performance tests on AWS in detached mode.
# Runs setup on the runner then launches JMeter on the bastion via nohup.
# Exits after kickoff; does not wait for the test to complete.
# ----------------------------------------------------------------------------

echo "WORKSPACE Directory: $WORKSPACE"
echo "RESOURCES Directory: $RESOURCES_DIR"

echo ""
echo "Starting detached performance test with params:"
echo "    DEPLOYMENT: $DEPLOYMENT"
echo "    CONCURRENCY: $CONCURRENCY"
echo "    DB_TYPE: $DB_TYPE"
echo "    BUILD_CAUSE: $BUILD_CAUSE"
echo "    Build Triggered By $BUILD_USER_EMAIL"
echo "=========================================================="

cd $WORKSPACE/perf-scripts/$DEPLOYMENT

echo ""
echo "Kicking off performance test in detached mode..."

cmd="./start-performance.sh -k $RESOURCES_DIR/thunder-perf-test.pem \
-c is-perf-cert -j $RESOURCES_DIR/apache-jmeter-5.6.3.tgz -n $WORKSPACE/thunder.zip -q $BUILD_USER_EMAIL -m $DB_TYPE -r $CONCURRENCY -f $DEPLOYMENT -z $USE_DELAYS "

if [[ ! -z $ADDITIONAL_PARAMS_TO_RUN_PERFORMANCE_SCRIPT ]]; then
	cmd+=" -- $ADDITIONAL_PARAMS_TO_RUN_PERFORMANCE_SCRIPT"
fi

echo "$cmd"

echo "perf_test_start_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$GITHUB_OUTPUT"

# Detached mode: start-performance.sh will launch JMeter on the bastion (via setsid --fork) and exit early.
export DETACHED_RUN=1
eval $cmd
kickoff_rc=$?
unset DETACHED_RUN

echo "perf_test_kickoff_end_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$GITHUB_OUTPUT"
echo "=========================================================="

exit $kickoff_rc
