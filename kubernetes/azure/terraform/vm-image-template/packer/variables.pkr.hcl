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

variable "azure_subscription_id" {
  type        = string
  description = "Azure subscription ID"
}

variable "azure_client_id" {
  type        = string
  description = "Azure client ID"
}

variable "azure_client_secret" {
  type        = string
  description = "Azure client secret"
}

variable "azure_tenant_id" {
  type        = string
  description = "Azure tenant ID"
}

variable "resource_group" {
  type        = string
  description = "Resource group"
}

variable "sig_gallery_name" {
  type        = string
  description = "Name of the Shared Image Gallery"
}

variable "sig_image_name" {
  type        = string
  description = "Name of the image in the Shared Image Gallery"
}

variable "sig_image_version" {
  type        = string
  description = "Version of the image in the Shared Image Gallery"
}

variable "temp_compute_name" {
  type        = string
  description = "Name of the temp VM"
}

variable "location" {
  type        = string
  description = "Azure region for the resources"
}
