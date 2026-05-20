terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=4.73.0"
    }
  }

  backend "azurerm" {}
}

provider "azurerm" {
  # resource_provider_registrations = "none" # This is only required when the User, Service Principal, or Identity running Terraform lacks the permissions to register Azure Resource Providers.
  use_oidc        = var.use_oidc
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  client_id       = var.client_id

  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "workbench" {
  # provider = azurerm
  name     = var.main_rg_name
  location = var.main_rg_location
}

resource "azurerm_key_vault" "workbench" {
  name                        = "workbench-kv"
  location                    = azurerm_resource_group.workbench.location
  resource_group_name         = azurerm_resource_group.workbench.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false
  rbac_authorization_enabled  = true
  sku_name                    = "standard"
}
