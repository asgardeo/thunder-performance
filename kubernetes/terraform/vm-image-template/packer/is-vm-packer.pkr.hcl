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

packer {
  required_plugins {
    azure = {
      source  = "github.com/hashicorp/azure"
      version = "~> 1"
    }
  }
}

source "azure-arm" "ubuntu-base" {
  tenant_id                              = var.azure_tenant_id
  subscription_id                        = var.azure_subscription_id
  build_resource_group_name              = var.resource_group
  client_id                              = var.azure_client_id
  client_secret                          = var.azure_client_secret
  image_offer                            = "0001-com-ubuntu-server-jammy"
  image_publisher                        = "Canonical"
  image_sku                              = "22_04-lts-gen2"
  os_type                                = "Linux"
  polling_duration_timeout               = "0h30m0s"
  private_virtual_network_with_public_ip = true
  temp_compute_name                      = var.temp_compute_name
  vm_size                                = "Standard_F4s_v2"
  shared_image_gallery_destination {
    subscription          = var.azure_subscription_id
    resource_group        = var.resource_group
    gallery_name          = var.sig_gallery_name
    image_name            = var.sig_image_name
    image_version         = var.sig_image_version
    storage_account_type  = "Standard_LRS"
    target_region {
      name = var.location
    }
  }
}

build {
  sources = ["source.azure-arm.ubuntu-base"]

  # Execute the setup script.
  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E bash '{{ .Path }}'"
    script          = "setupVM.sh"
  }
}
