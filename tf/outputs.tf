output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "acr_login_server" {
  description = "The FQDN of the Azure Container Registry."
  value       = azurerm_container_registry.acr.login_server
}

output "acr_id" {
  description = "The ID of the Azure Container Registry."
  value       = azurerm_container_registry.acr.id
}

output "aks_cluster_name" {
  description = "The name of the AKS cluster."
  value       = azurerm_kubernetes_cluster.aks.name
}

output "aks_cluster_id" {
  description = "The ID of the AKS cluster."
  value       = azurerm_kubernetes_cluster.aks.id
}

output "aks_kube_config_raw" {
  description = "Raw Kubernetes configuration for the AKS cluster. Use with caution."
  value       = azurerm_kubernetes_cluster.aks.kube_config_raw
  sensitive   = true
}

output "aks_get_credentials_command" {
  description = "Command to run using Azure CLI to configure kubectl."
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.rg.name} --name ${azurerm_kubernetes_cluster.aks.name}"
}
