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

provider "azurerm" {
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  features {}
}

module "resource-group" {
  source              = "git::https://github.com/wso2/azure-terraform-modules.git//modules/azurerm/Resource-Group?ref=v2.18.10"
  resource_group_name = join("-", [var.project, var.environment, var.location, var.padding])
  location            = var.location
  tags                = merge(local.default_tags)
}

module "virtual-network" {
  source                        = "git::https://github.com/wso2/azure-terraform-modules.git//modules/azurerm/Virtual-Network?ref=v2.18.10"
  virtual_network_name          = join("-", [var.project, var.environment, var.location, var.padding])
  resource_group_name           = module.resource-group.resource_group_name
  location                      = var.location
  virtual_network_address_space = var.virtual_network_address_space
  tags                          = local.default_tags
  private_dns_zones = [
    {
      name      = join("-", [var.project, "postgres", var.environment, var.padding])
      zone_name = local.private_dns_zone_name_postgres
    }
  ]
  depends_on = [
    module.private-dns-postgres
  ]
}

# Log Analytics Workspace
module "log-analytics-workspace" {
  source                         = "git::https://github.com/wso2/azure-terraform-modules.git//modules/azurerm/Log-Analytics-Workspace?ref=v2.18.10"
  log_analytics_workspace_name   = join("-", [var.project, var.environment, var.location, var.padding])
  resource_group_name            = module.resource-group.resource_group_name
  location                       = var.location
  log_analytics_workspace_sku    = var.log_analytics_workspace_sku
  log_retention_in_days          = var.log_retention_in_days
  internet_ingestion_enabled     = var.log_analytics_workspace_internet_ingestion_enabled
  internet_query_enabled         = var.log_analytics_workspace_internet_query_enabled
  log_analytics_solution_enabled = true
  tags                           = local.default_tags
}

# AKS cluster
module "aks-cluster" {
  source                     = "git::https://github.com/wso2/azure-terraform-modules.git//modules/azurerm/AKS-Generic?ref=v2.19.0"
  aks_cluster_name           = join("-", [var.project, var.environment, var.location, var.padding])
  aks_cluster_dns_prefix     = join("-", [var.project, var.environment, var.location, var.padding])
  location                   = var.location
  aks_resource_group_name    = module.resource-group.resource_group_name
  sku_tier                   = var.aks_sku_tier
  tags                       = local.default_tags
  log_analytics_workspace_id = module.log-analytics-workspace.log_analytics_workspace_id

  # Network configuration
  virtual_network_resource_group_name                  = module.resource-group.resource_group_name
  virtual_network_name                                 = module.virtual-network.virtual_network_name
  aks_node_pool_resource_group_name                    = join("-", [var.project, local.aks_node_pool_workload, var.environment, var.location, var.padding])
  aks_node_pool_subnet_name                            = join("-", [local.aks_node_pool_workload, var.padding])
  aks_node_pool_subnet_address_prefix                  = local.aks_node_pool_subnet_cidr
  aks_node_pool_subnet_route_table_name                = join("-", [var.project, local.aks_node_pool_workload, var.environment, var.location, var.padding])
  aks_node_pool_subnet_network_security_group_name     = join("-", [var.project, local.aks_node_pool_workload, var.environment, var.location, var.padding])
  aks_nodepool_subnet_allowed_service_endpoints        = var.aks_nodepool_subnet_allowed_service_endpoints
  aks_load_balancer_subnet_name                        = join("-", [local.aks_internal_lb_workload, var.padding])
  internal_loadbalancer_subnet_address_prefix          = local.aks_load_balancer_subnet_cidr
  aks_load_balancer_subnet_network_security_group_name = join("-", [var.project, local.aks_internal_lb_workload, var.environment, var.location, var.padding])

  # AKS Cluster configuration
  aks_admin_username              = var.aks_admin_username
  aks_public_ssh_key_path         = var.aks_public_ssh_key_path
  kubernetes_version              = var.kubernetes_version
  service_cidr                    = local.service_cidr
  dns_service_ip                  = local.dns_service_ip
  outbound_type                   = "loadBalancer"
  api_server_authorized_ip_ranges = var.api_server_authorized_ip_ranges
  aks_azure_rbac_enabled          = true
  msi_auth_for_monitoring_enabled = true

  # Default node pool configuration
  default_node_pool_name                         = var.default_node_pool_name
  default_node_pool_vm_size                      = var.default_node_pool_vm_size
  default_node_pool_count                        = var.default_node_pool_count
  default_node_pool_os_disk_size_gb              = var.default_node_pool_os_disk_size
  default_node_pool_max_pods                     = var.default_node_pool_max_pods
  default_node_pool_min_count                    = var.default_node_pool_min_count
  default_node_pool_max_count                    = var.default_node_pool_max_count
  default_node_pool_orchestrator_version         = var.kubernetes_version
  default_node_pool_only_critical_addons_enabled = false
  default_node_pool_os_disk_type                 = "Ephemeral"
  default_node_pool_availability_zones           = null

  azure_policy_enabled = false
}

# Database
module "postgres-vm-subnet" {
  source                      = "git::https://github.com/wso2/azure-terraform-modules.git//modules/azurerm/Subnet?ref=v2.18.10"
  subnet_name                 = join("-", ["postgres", var.padding])
  resource_group_name         = module.resource-group.resource_group_name
  location                    = var.location
  virtual_network_name        = module.virtual-network.virtual_network_name
  network_security_group_name = join("-", [var.project, "postgres", var.environment, var.location, var.padding])
  address_prefix              = local.postgres_subnet_address_prefix
  service_endpoints           = ["Microsoft.Storage"]
  delegation = [
    {
      delegation_name         = "postgre-sql-delegation",
      service_delegation_name = "Microsoft.DBforPostgreSQL/flexibleServers",
      service_delegation_actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action"
      ]
    }
  ]
  tags = local.default_tags
}

module "private-dns-postgres" {
  source                = "git::https://github.com/wso2/azure-terraform-modules.git//modules/azurerm/Private-DNS-Zone?ref=v2.18.10"
  private_dns_zone_name = local.private_dns_zone_name_postgres
  resource_group_name   = module.resource-group.resource_group_name
  tags                  = local.default_tags
}

module "postgres-server" {
  source                           = "git::https://github.com/wso2/azure-terraform-modules.git//modules/azurerm/PostgreSQL-Flexible-Server?ref=v2.18.10"
  server_name                      = join("-", [var.project, var.environment, var.location, var.padding])
  resource_group_name              = module.resource-group.resource_group_name
  subnet_id                        = module.postgres-vm-subnet.subnet_id
  private_dns_zone_id              = module.private-dns-postgres.private_dns_zone_id
  location                         = var.location
  postgresql_server_version        = var.postgres_server_version
  postgresql_server_admin_username = var.postgres_server_admin_username
  postgresql_server_admin_password = var.postgres_server_admin_password
  storage_size                     = var.postgres_server_storage_size
  sku_name                         = var.postgres_server_sku_name
  tags                             = local.default_tags
}

module "postgres-thunder-db" {
  source             = "git::https://github.com/wso2/azure-terraform-modules.git//modules/azurerm/PostgreSQL-Flexible-Server-Database?ref=v2.18.10"
  database_full_name = var.thunder_db_name
  server_id          = module.postgres-server.postgresql_server_id
}

module "postgres-runtime-db" {
  source             = "git::https://github.com/wso2/azure-terraform-modules.git//modules/azurerm/PostgreSQL-Flexible-Server-Database?ref=v2.18.10"
  database_full_name = var.runtime_db_name
  server_id          = module.postgres-server.postgresql_server_id
}

# VM
module "vm-subnet" {
  source                      = "git::https://github.com/wso2/azure-terraform-modules.git//modules/azurerm/Subnet?ref=v2.18.10"
  subnet_name                 = join("-", ["vm", var.padding])
  resource_group_name         = module.resource-group.resource_group_name
  location                    = var.location
  virtual_network_name        = module.virtual-network.virtual_network_name
  network_security_group_name = join("-", [var.project, "vm", var.environment, var.location, var.padding])
  address_prefix              = local.vm_subnet_address_prefix
  tags                        = local.default_tags
}

module "public-ip-vm-perf-runner" {
  source              = "git::https://github.com/wso2/azure-terraform-modules.git//modules/azurerm/Public-IP?ref=v2.18.10"
  public_ip_name      = join("-", [var.project, var.vm_perf_runner_name, var.location, var.padding])
  resource_group_name = module.resource-group.resource_group_name
  location            = var.location
  tags                = local.default_tags
}

module "allow-ssh-vm-subnet-rule" {
  source                     = "git::https://github.com/wso2/azure-terraform-modules.git//modules/azurerm/Network-Security-Rule?ref=v2.18.10"
  network_security_rule_name = join("", ["Allow", "SSH"])
  resource_group_name        = module.resource-group.resource_group_name
  nsg_name                   = module.vm-subnet.subnet_nsg_name
  priority                   = 1000
  direction                  = "Inbound"
  access                     = "Allow"
  protocol                   = "Tcp"
  source_port_range          = "*"
  destination_port_range     = 22
  source_address_prefix      = "*"
  destination_address_prefix = "*"
}

module "vm-perf-runner" {
  source                    = "git::https://github.com/wso2/azure-terraform-modules.git//modules/azurerm/Static-IP-Custom-Virtual-Machine?ref=v2.18.10"
  vm_name                   = join("-", [var.project, var.vm_perf_runner_name, var.location, var.padding])
  computer_name             = join("-", [var.project, var.vm_perf_runner_name, var.location, var.padding])
  os_disk_name              = join("-", [var.project, var.vm_perf_runner_name, var.location, var.padding])
  nic_name                  = join("-", [var.project, var.vm_perf_runner_name, var.location, var.padding])
  nic_ip_configuration_name = join("-", [var.project, var.vm_perf_runner_name, var.location, var.padding])
  resource_group_name       = module.resource-group.resource_group_name
  location                  = var.location
  admin_username            = "azureuser" #Do not change the admin username as it is used in the perf scripts.
  size                      = var.vm_size
  os_disk_size_gb           = var.vm_os_disk_size_gb
  public_key_path           = var.vm_public_ssh_key_path
  subnet_id                 = module.vm-subnet.subnet_id
  private_ip_address        = local.vm_private_ip_address
  public_ip_address_id      = module.public-ip-vm-perf-runner.public_ip_id
  source_image_id           = var.vm_image_id
  tags                      = local.default_tags
  depends_on                = [module.vm-subnet]
}

module "container_insights_data_collection_rule" {
  source                               = "git::https://github.com/wso2/azure-terraform-modules.git//modules/azurerm/Monitor-Data-Collection-Rule?ref=v2.19.0"
  data_collection_rule_name            = join("-", ["MSCI", "aks", var.project, var.environment, var.location, var.padding])
  location                             = var.location
  resource_group_name                  = module.resource-group.resource_group_name
  kind                                 = "Linux"
  tags                                 = local.default_tags
  data_flow_destinations               = ["workspace"]
  data_flow_streams                    = ["Microsoft-ContainerInsights-Group-Default"]
  destination_la_name                  = "workspace"
  destination_la_workspace_resource_id = module.log-analytics-workspace.log_analytics_workspace_id

  # Add extension data source for ContainerInsights
  data_sources_extensions = [{
    name           = "ContainerInsightsExtension"
    extension_name = "ContainerInsights"
    extension_json = jsonencode({
      dataCollectionSettings = {
        enableContainerLogV2   = true
        interval               = "1m"
        namespaceFilteringMode = "Off"
      }
    })
    streams            = ["Microsoft-ContainerInsights-Group-Default"]
    input_data_sources = []
  }]
}

module "container_insights_data_collection_rule_association" {
  source                                = "git::https://github.com/wso2/azure-terraform-modules.git//modules/azurerm/Monitor-Data-Collection-Rule-Association?ref=v2.19.0"
  data_collection_rule_association_name = "containerinsightsextension"
  data_collection_rule_id               = module.container_insights_data_collection_rule.data_collection_rule_id
  target_resource_id                    = module.aks-cluster.aks_cluster_id
}
