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
WORKSPACE_DIR=$WORKSPACE/workspace

echo "WORKSPACE Directory: $WORKSPACE"

echo ""
echo "Starting performance test with params:"
echo "    THUNDER_PACK_URL: $THUNDER_PACK_URL"
echo "    DEPLOYMENT: $DEPLOYMENT"
echo "    CPU_CORES: $CPU_CORES"
echo "    PERFORMANCE_REPO: $PERFORMANCE_REPO"
echo "    BRANCH: $BRANCH"
echo "    DB_TYPE: $DB_TYPE"
echo "    BUILD_CAUSE: $BUILD_CAUSE"
echo "    Build Triggered By $BUILD_USER_EMAIL"
echo "=========================================================="
cd $WORKSPACE
rm -rf workspace
mkdir workspace
rm -rf resources
mkdir resources
cd workspace

echo ""
echo "Downloading Thunder Pack..."
echo "=========================================================="
wget -q -O "$WORKSPACE"/thunder.zip "$THUNDER_PACK_URL"

sudo rm -rf thunder-performance
echo ""
echo "Cloning thunder-performance repo..."
echo "=========================================================="
git clone $PERFORMANCE_REPO
cd thunder-performance
git checkout $BRANCH
cd perf-scripts

aws s3 cp s3://performance-thunder/keys/thunder-perf-test.pem thunder-perf-test.pem
chmod 400 thunder-perf-test.pem
mv thunder-perf-test.pem $RESOURCES_DIR

aws s3 cp s3://performance-thunder-resources/apache-jmeter-5.6.3.tgz apache-jmeter-5.6.3.tgz
mv apache-jmeter-5.6.3.tgz $RESOURCES_DIR

# Script to resolve cpu cores
instance_type=""
if [ "$CPU_CORES" = "2" ]; then
	instance_type="c6i.large"
elif [ "$CPU_CORES" = "4" ]; then
	instance_type="c6i.xlarge"
elif [ "$CPU_CORES" = "8" ]; then
	instance_type="c6i.2xlarge"
else
	echo ""
	echo "Provided CPU cores [$CPU_CORES] is not supported with the deployment: $DEPLOYMENT."
	echo "Exiting..."
	exit 1
fi

cd $DEPLOYMENT

echo ""
echo "Building project..."
echo "=========================================================="

CMD_MVN="mvn clean install"

$CMD_MVN

echo ""
echo "Starting test..."
echo "=========================================================="

echo "CPU Instance type: $instance_type"

cmd="./start-performance.sh -k $RESOURCES_DIR/thunder-perf-test.pem \
-c is-perf-cert -j $RESOURCES_DIR/apache-jmeter-5.6.3.tgz -n $WORKSPACE/thunder.zip -q $BUILD_USER_EMAIL -i $instance_type -m $DB_TYPE -r $CONCURRENCY -v $MODE -f $DEPLOYMENT -z $USE_DELAYS "

if [[ ! -z $ADDITIONAL_PARAMS_TO_RUN_PERFORMANCE_SCRIPT ]]; then
	cmd+=" $ADDITIONAL_PARAMS_TO_RUN_PERFORMANCE_SCRIPT"
fi

echo "$cmd"

eval $cmd

cp -r results-* "$WORKSPACE_DIR"

aws s3 cp --recursive results-* s3://performance-thunder/results/"GitHub-$BUILD_NUMBER"
