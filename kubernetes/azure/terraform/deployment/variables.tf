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

variable "subscription_id" {
  description = "The Azure subscription ID"
  type        = string
}

variable "tenant_id" {
  description = "The Azure subscription tenant ID"
  type        = string
}

variable "project" {
  description = "The project name"
  type        = string
  default     = "thunder"
}

variable "environment" {
  description = "The deployment environment (e.g., dev, test, prod)"
  type        = string
  default     = "perf"
}

variable "location" {
  description = "The Azure region where resources will be deployed"
  type        = string
  default     = "eastus2"
}

variable "padding" {
  description = "A padding string to ensure uniqueness of resource names"
  type        = string
  default     = "001"
}

variable "virtual_network_address_space" {
  description = "The address space for the virtual network"
  type        = string
  default     = "10.0.0.0/16"
}

variable "log_analytics_workspace_sku" {
  description = "The SKU of the Log Analytics Workspace"
  type        = string
  default     = "PerGB2018"
}

variable "log_retention_in_days" {
  description = "The number of days to retain logs in the Log Analytics Workspace"
  type        = number
  default     = 30
}

variable "log_analytics_workspace_internet_ingestion_enabled" {
  description = "Whether internet ingestion is enabled for the Log Analytics Workspace"
  type        = bool
  default     = true
}

variable "log_analytics_workspace_internet_query_enabled" {
  description = "Whether internet queries are enabled for the Log Analytics Workspace"
  type        = bool
  default     = true
}

# AKS variables
variable "aks_sku_tier" {
  description = "The SKU tier for the AKS cluster"
  type        = string
  default     = "Free"
}


variable "aks_nodepool_subnet_allowed_service_endpoints" {
  description = "The service endpoints allowed for the AKS node pool subnet"
  type        = list(string)
  default     = ["Microsoft.Sql", "Microsoft.ContainerRegistry", "Microsoft.EventHub", "Microsoft.Storage"]
}

variable "aks_admin_username" {
  description = "The admin username for the AKS cluster"
  type        = string
  default     = "aksadmin"
}

variable "aks_public_ssh_key_path" {
    description = "The path to the public SSH key for the AKS cluster"
    type        = string
    default     = "../public-keys/aks/id_rsa.pub"
}

variable "kubernetes_version" {
  description = "The Kubernetes version for the AKS cluster"
  type        = string
  default     = "1.32.6"
}

variable "api_server_authorized_ip_ranges" {
  description = "The IP ranges authorized to access the Kubernetes API server"
  type        = list(string)
  default     = null
}

variable "default_node_pool_name" {
  description = "The name of the default node pool"
  type        = string
  default     = "default"
}

variable "default_node_pool_vm_size" {
  description = "The VM size for the default node pool"
  type        = string
  default     = "Standard_F8s_v2"
}

variable "default_node_pool_count" {
  description = "The number of nodes in the default node pool"
  type        = number
  default     = 2
}

variable "default_node_pool_os_disk_size" {
  description = "The OS disk size for the default node pool in GB"
  type        = number
  default     = 64
}

variable "default_node_pool_max_pods" {
  description = "The maximum number of pods per node in the default node pool"
  type        = number
  default     = 30
}

variable "default_node_pool_min_count" {
  description = "The minimum number of nodes in the default node pool for auto-scaling"
  type        = number
  default     = 2
}

variable "default_node_pool_max_count" {
  description = "The maximum number of nodes in the default node pool for auto-scaling"
  type        = number
  default     = 5
}

# Database variables
variable "postgres_server_version" {
  description = "The version of Postgres to use for the flexible server"
  type        = string
  default     = "17"
}

variable "postgres_server_admin_username" {
  description = "The administrator username for the Postgres server"
  type        = string
  default     = "pgadmin"
}

variable "postgres_server_admin_password" {
  description = "The administrator password for the Postgres server"
  type        = string
  sensitive   = true
}

variable "postgres_server_storage_size" {
  description = "The storage size in GB for the Postgres server"
  type        = number
  default     = 32768
}

variable "postgres_server_sku_name" {
  description = "The SKU name for the Postgres server"
  type        = string
  default     = "B_Standard_B2s"
}

# Database name variables
variable "thunder_db_name" {
  description = "The name of the Thunder database"
  type        = string
  default     = "thunderdb"
}

variable "runtime_db_name" {
  description = "The name of the Runtime database"
  type        = string
  default     = "runtimedb"
}

# VM variables
variable "vm_perf_runner_name" {
  description = "The name of the performance runner VM"
  type        = string
  default     = "perf-runner"
}

variable "vm_size" {
  description = "The size of the VM"
  type        = string
  default     = "Standard_F8s_v2"
}

variable "vm_os_disk_size_gb" {
  description = "The size of the OS disk in GB"
  type        = string
  default     = "30"
}

variable "vm_public_ssh_key_path" {
    description = "The path to the public SSH key for the VM"
    type        = string
    default     = "../public-keys/vm/id_rsa.pub"
}

variable "vm_image_id" {
  description = "The ID of the VM image to use"
  type        = string
}
