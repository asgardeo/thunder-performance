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

# Network configuration
virtual_network_address_space   = "10.0.0.0/16"
aks_node_pool_subnet_cidr       = "10.0.1.0/24"
aks_load_balancer_subnet_cidr   = "10.0.2.0/24"
service_cidr                    = "10.0.3.0/24"
postgres_subnet_address_prefix  = ["10.0.4.0/24"]
vm_subnet_address_prefix        = ["10.0.5.0/24"]
vm_private_ip_address           = "10.0.5.4"
dns_service_ip                  = "10.0.3.10"

# Log Analytics Workspace configuration
log_retention_in_days = 30

# AKS configuration
aks_sku_tier                   = "Free"
aks_admin_username             = "aksadmin"
kubernetes_version             = "1.32.6"
private_cluster_enabled        = true
default_node_pool_name         = "default"
default_node_pool_vm_size      = "Standard_F8s_v2"
default_node_pool_count        = 2
default_node_pool_os_disk_size = 64
default_node_pool_max_pods     = 100
default_node_pool_min_count    = 2
default_node_pool_max_count    = 5
default_node_pool_availability_zones = ["1", "2", "3"]

# Postgres configuration
postgres_server_version        = "16"
postgres_server_admin_username = "pgadmin"
postgres_server_storage_size   = 32768
postgres_server_sku_name       = "B_Standard_B2s"

# VM configuration
vm_perf_runner_name = "perf-runner"
vm_size             = "Standard_F8s_v2"
vm_os_disk_size_gb  = "30"
