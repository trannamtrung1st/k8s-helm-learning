output "resource_group_name" {
  description = "Name of the main Workbench resource group"
  value       = azurerm_resource_group.workbench.name
}

output "resource_group_id" {
  description = "Azure resource ID of the main Workbench resource group"
  value       = azurerm_resource_group.workbench.id
}

output "key_vault_name" {
  description = "Name of the Workbench key vault"
  value       = azurerm_key_vault.workbench.name
}

output "key_vault_id" {
  description = "Azure resource ID of the Workbench key vault"
  value       = azurerm_key_vault.workbench.id
}
