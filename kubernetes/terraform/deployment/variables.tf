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
}

variable "environment" {
  description = "The deployment environment (e.g., dev, test, prod)"
  type        = string
}

variable "location" {
  description = "The Azure region where resources will be deployed"
  type        = string
}

variable "padding" {
  description = "A padding string to ensure uniqueness of resource names"
  type        = string
  default     = "001"
}

variable "virtual_network_address_space" {
  description = "The address space for the virtual network"
  type        = string
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
  default     = false
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

variable "aks_node_pool_subnet_cidr" {
  description = "The CIDR for the AKS node pool subnet"
  type        = string
}

variable "aks_load_balancer_subnet_cidr" {
  description = "The CIDR for the AKS load balancer subnet"
  type        = string
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

variable "kubernetes_version" {
  description = "The Kubernetes version for the AKS cluster"
  type        = string
}

variable "service_cidr" {
  description = "The CIDR for Kubernetes services"
  type        = string
}

variable "dns_service_ip" {
  description = "The IP address for Kubernetes DNS service"
  type        = string
}

variable "private_cluster_enabled" {
  description = "Whether to enable private cluster for AKS"
  type        = bool
}

variable "api_server_authorized_ip_ranges" {
  description = "The IP ranges authorized to access the Kubernetes API server"
  type        = list(string)
  default     = null
}

variable "default_node_pool_name" {
  description = "The name of the default node pool"
  type        = string
}

variable "default_node_pool_vm_size" {
  description = "The VM size for the default node pool"
  type        = string
}

variable "default_node_pool_count" {
  description = "The number of nodes in the default node pool"
  type        = number
  default     = 3
}

variable "default_node_pool_os_disk_size" {
  description = "The OS disk size for the default node pool in GB"
  type        = number
  default     = 128
}

variable "default_node_pool_max_pods" {
  description = "The maximum number of pods per node in the default node pool"
  type        = number
  default     = 30
}

variable "default_node_pool_min_count" {
  description = "The minimum number of nodes in the default node pool for auto-scaling"
  type        = number
  default     = 1
}

variable "default_node_pool_max_count" {
  description = "The maximum number of nodes in the default node pool for auto-scaling"
  type        = number
  default     = 5
}

variable "default_node_pool_availability_zones" {
  description = "The availability zones for the default node pool"
  type        = list(string)
  default     = ["1", "2", "3"]
}

# Database variables
variable "postgres_subnet_address_prefix" {
  description = "The address prefix for the PostgreSQL subnet"
  type        = list(string)
}

variable "postgres_vm_subnet_subnet_service_endpoints" {
  description = "The service endpoints allowed for the Postgres VM subnet"
  type        = list(string)
  default     = ["Microsoft.Storage"]
}

variable "postgres_server_version" {
  description = "The version of Postgres to use for the flexible server"
  type        = string
}

variable "postgres_server_admin_username" {
  description = "The administrator username for the Postgres server"
  type        = string
}

variable "postgres_server_admin_password" {
  description = "The administrator password for the Postgres server"
  type        = string
  sensitive   = true
}

variable "postgres_server_storage_size" {
  description = "The storage size in GB for the Postgres server"
  type        = number
}

variable "postgres_server_sku_name" {
  description = "The SKU name for the Postgres server"
  type        = string
}

# VM variables
variable "vm_subnet_address_prefix" {
  description = "The address prefix for the VM subnet"
  type        = list(string)
}

variable "vm_perf_runner_name" {
  description = "The name of the performance runner VM"
  type        = string
}

variable "vm_size" {
  description = "The size of the VM"
  type        = string
}

variable "vm_os_disk_size_gb" {
  description = "The size of the OS disk in GB"
  type        = string
}

variable "vm_private_ip_address" {
  description = "The static private IP address for the VM"
  type        = string
}

variable "vm_image_id" {
  description = "The ID of the VM image to use"
  type        = string
}
