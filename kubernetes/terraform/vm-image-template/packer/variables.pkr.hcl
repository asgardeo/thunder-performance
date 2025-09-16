# -------------------------------------------------------------------------------------
#
# Copyright (c) 2025, WSO2 LLC. (http://www.wso2.com).
#
# This software is the property of WSO2 LLC. and its suppliers, if any.
# Dissemination of any information or reproduction of any material contained
# herein in any form is strictly forbidden, unless permitted by WSO2 expressly.
# You may not alter or remove any copyright or other notice from copies of this content.
#
# --------------------------------------------------------------------------------------

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
