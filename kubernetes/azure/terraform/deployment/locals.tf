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

locals {
  default_tags = {
    project     = var.project
    environment = var.environment
    terraform   = "true"
  }

  aks_node_pool_subnet_cidr       = cidrsubnet(var.virtual_network_address_space, 8, 1)
  aks_load_balancer_subnet_cidr   = cidrsubnet(var.virtual_network_address_space, 8, 2)
  service_cidr                    = cidrsubnet(var.virtual_network_address_space, 8, 3)
  dns_service_ip                  = cidrhost(local.service_cidr, 10)
  postgres_subnet_address_prefix  = [cidrsubnet(var.virtual_network_address_space, 8, 4)]
  vm_subnet_address_prefix        = [cidrsubnet(var.virtual_network_address_space, 8, 5)]
  vm_private_ip_address           = cidrhost(local.vm_subnet_address_prefix[0], 4)

  ## AKS Cluster
  aks_node_pool_workload   = join("", ["aksnodepool", var.project])
  aks_internal_lb_workload = join("", ["aksinternallb", var.project])

  # Database
  private_dns_zone_name_postgres = "privatelink.postgres.database.azure.com"
}
