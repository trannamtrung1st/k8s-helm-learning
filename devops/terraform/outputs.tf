output "resource_group_name" {
  description = "Name of the main Workbench resource group"
  value       = azurerm_resource_group.workbench.name
}

output "resource_group_id" {
  description = "Azure resource ID of the main Workbench resource group"
  value       = azurerm_resource_group.workbench.id
}
