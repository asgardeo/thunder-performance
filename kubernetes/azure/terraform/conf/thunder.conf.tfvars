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

# Project and environment settings
project              = "thunder"
environment          = "perf"
location             = "eastus2"
padding              = "001"

# AKS configuration

kubernetes_version             = "1.32.6"
default_node_pool_vm_size      = "Standard_F8s_v2"
default_node_pool_count        = 2
default_node_pool_os_disk_size = 64
default_node_pool_max_pods     = 30
default_node_pool_min_count    = 2
default_node_pool_max_count    = 5

# Postgres configuration
postgres_server_version        = "16"
postgres_server_storage_size   = 32768
postgres_server_sku_name       = "B_Standard_B2s"

# VM configuration
vm_size             = "Standard_F8s_v2"
vm_os_disk_size_gb  = "30"
