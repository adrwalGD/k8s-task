terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.27.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.10.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.9"
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

provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
  }
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

  network_profile {
    network_plugin      = "azure"
    network_policy      = "azure"
    network_plugin_mode = "overlay"
  }

  default_node_pool {
    name       = "default"
    vm_size    = "Standard_B2s"
    node_count = 2
  }

  identity {
    type = "SystemAssigned"
  }
}

resource "kubernetes_secret" "redis_pass" {
  metadata {
    name      = "redis-password"
    namespace = "default"
  }

  data = {
    redis-password = var.redis_password
  }

  type = "Opaque"
}

resource "kubernetes_secret" "acr_secret" {
  depends_on = [
    azurerm_kubernetes_cluster.aks,
    azurerm_container_registry.acr
  ]

  metadata {
    name      = "acr-auth"
    namespace = "default"
  }

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "${azurerm_container_registry.acr.login_server}" = {
          username = azurerm_container_registry.acr.admin_username
          password = sensitive(azurerm_container_registry.acr.admin_password)
          email    = "no-reply@example.com"
          auth     = base64encode("${azurerm_container_registry.acr.admin_username}:${azurerm_container_registry.acr.admin_password}")
        }
      }
    })
  }

  type = "kubernetes.io/dockerconfigjson"
}

resource "helm_release" "nginx_ingress" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = "4.10.1"
  namespace        = "ingress-nginx"
  create_namespace = true

  set {
    name  = "controller.service.annotations.\"service\\.beta\\.kubernetes\\.io/azure-load-balancer-health-probe-request-path\""
    value = "/healthz"
  }

  depends_on = [
    azurerm_kubernetes_cluster.aks
  ]
}
