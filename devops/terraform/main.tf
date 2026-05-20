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

# RBAC Key Vault: Terraform principal must manage secrets (KV has rbac_authorization_enabled).
resource "azurerm_role_assignment" "workbench_kv_secrets_officer" {
  scope                = azurerm_key_vault.workbench.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

locals {
  workbench_kv_secret_values = {
    "workbench-postgres-connection-string" = var.workbench_secrets.postgres_connection_string
    "workbench-postgres-user"              = var.workbench_secrets.postgres_user
    "workbench-postgres-password"          = var.workbench_secrets.postgres_password
    "workbench-postgres-database"          = var.workbench_secrets.postgres_database
    "workbench-rabbitmq-uri"               = var.workbench_secrets.rabbitmq_uri
    "workbench-rabbitmq-password"          = var.workbench_secrets.rabbitmq_password
    "workbench-redis-connection-string"    = var.workbench_secrets.redis_connection_string
    "workbench-redis-user"                 = var.workbench_secrets.redis_user
    "workbench-redis-password"             = var.workbench_secrets.redis_password
  }
}

resource "azurerm_key_vault_secret" "workbench" {
  for_each = var.manage_workbench_kv_secrets ? local.workbench_kv_secret_values : {}

  name         = each.key
  value        = each.value
  key_vault_id = azurerm_key_vault.workbench.id

  depends_on = [azurerm_role_assignment.workbench_kv_secrets_officer]
}

resource "azurerm_container_registry" "workbench" {
  name                = "workbenchacr77"
  resource_group_name = azurerm_resource_group.workbench.name
  location            = azurerm_resource_group.workbench.location
  sku                 = "Basic"
  admin_enabled       = false
}

resource "azurerm_kubernetes_cluster" "workbench" {
  name                              = "workbench-aks"
  location                          = azurerm_resource_group.workbench.location
  resource_group_name               = azurerm_resource_group.workbench.name
  dns_prefix                        = "workbench-aks"
  role_based_access_control_enabled = true
  oidc_issuer_enabled               = true
  workload_identity_enabled         = true
  kubernetes_version                = "1.35.4"

  api_server_access_profile {
    authorized_ip_ranges = var.authorized_ip_ranges
  }

  default_node_pool {
    name                         = "system"
    vm_size                      = "Standard_D2s_v3"
    node_count                   = 1
    only_critical_addons_enabled = true
    temporary_name_for_rotation  = "tempsys"
  }

  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }

  network_profile {
    network_plugin    = "kubenet"
    load_balancer_sku = "standard"
  }

  identity {
    type = "SystemAssigned"
  }

  tags = {
    Environment = "Production"
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "workbench_workers" {
  name                        = "workers"
  kubernetes_cluster_id       = azurerm_kubernetes_cluster.workbench.id
  vm_size                     = "Standard_D2s_v3"
  auto_scaling_enabled        = true
  min_count                   = 2
  max_count                   = 4
  mode                        = "User"
  temporary_name_for_rotation = "tempusr"
}

resource "azurerm_role_assignment" "aks_acr_pull" {
  principal_id                     = azurerm_kubernetes_cluster.workbench.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.workbench.id
  skip_service_principal_aad_check = true
}

moved {
  from = azurerm_container_registry.acr
  to   = azurerm_container_registry.workbench
}
