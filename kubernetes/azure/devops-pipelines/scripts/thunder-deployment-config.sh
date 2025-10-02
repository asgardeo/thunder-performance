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

# Thunder Deployment Configuration
# This script exports Thunder deployment configuration as environment variables

# Thunder Deployment Configuration
export THUNDER_REPLICAS='2'
export THUNDER_CPU_LIMITS='1.5'
export THUNDER_CPU_REQUESTS='1'
export THUNDER_MEMORY_LIMITS='512Mi'
export THUNDER_MEMORY_REQUESTS='256Mi'

# HPA Configuration
export THUNDER_HPA_ENABLED='true'
export THUNDER_HPA_MAX_REPLICAS='10'
export THUNDER_HPA_CPU_UTILIZATION='65'
export THUNDER_HPA_MEMORY_UTILIZATION='75'
