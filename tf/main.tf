terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.26.0"
    }
     kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.10.0"
    }
  }
}

provider "azurerm" {
  subscription_id = "afa1a461-3f97-478d-a062-c8db00c98741"
  features {}
}

provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
}

resource "azurerm_resource_group" "rg" {
  name     = "adrwal-rg"
  location = "westeurope"
}


resource "azurerm_container_registry" "acr" {
  name                = "adrwalacr"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = true
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "ad-aks"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "adrwal-aks"

  sku_tier = "Free"

  default_node_pool {
    name       = "default"
    vm_size    = "Standard_B2s"
    node_count = 2
  }

  identity {
    type = "SystemAssigned"
  }
}

resource "kubernetes_secret" "acr_secret" {
  # Ensure the secret is created only after AKS and ACR are ready
  depends_on = [
    azurerm_kubernetes_cluster.aks,
    azurerm_container_registry.acr
  ]

  metadata {
    name      = "acr-auth"
    namespace = "default"
  }

  # IMPORTANT: The data key must be ".dockerconfigjson"
  # The value is the JSON structure Docker expects, as a string.
  # Terraform automatically base64 encodes the *value* part of the data map.
  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "${azurerm_container_registry.acr.login_server}" = {
          username = azurerm_container_registry.acr.admin_username
          # Mark the password as sensitive to prevent it from showing in plain text logs/outputs
          password = sensitive(azurerm_container_registry.acr.admin_password)
          email    = "no-reply@example.com" # Placeholder email, value doesn't usually matter
          # The 'auth' field is the base64 encoding of "username:password"
          auth = base64encode("${azurerm_container_registry.acr.admin_username}:${azurerm_container_registry.acr.admin_password}")
        }
      }
    })
  }

  # Secret type must be "kubernetes.io/dockerconfigjson"
  type = "kubernetes.io/dockerconfigjson"
}




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
