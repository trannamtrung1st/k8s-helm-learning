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

output "acr_name" {
  description = "Name of the Workbench ACR"
  value       = azurerm_container_registry.acr.name
}

output "acr_id" {
  description = "Azure resource ID of the Workbench ACR"
  value       = azurerm_container_registry.acr.id
}

output "aks_get_credentials_command" {
  description = "Azure CLI command to merge AKS credentials into your local kubeconfig"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.workbench.name} --name ${azurerm_kubernetes_cluster.workbench.name}"
}
