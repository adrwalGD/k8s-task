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

resource "helm_release" "redis_cart" {
  name       = "redis-cart"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "redis"
  version    = "18.6.3"
  namespace  = "default"
  create_namespace = false

  set {
    name  = "auth.existingSecret"
    value = kubernetes_secret.redis_pass.metadata[0].name
  }

  values = [
    file("redis-values.yaml")
    # <<-YAML
    # # Match labels from your original Deployment/Service
    # commonLabels:
    #   app: redis-cart

    # # Use a single replica (standalone mode)
    # architecture: standalone
    # master:
    #   replicaCount: 1

    #   # Configure Pod Security Context (matches spec.template.spec.securityContext)
    #   podSecurityContext:
    #     enabled: true
    #     fsGroup: 1000
    #     runAsUser: 1000
    #     # Bitnami chart usually handles runAsGroup and runAsNonRoot automatically
    #     # when runAsUser is set to non-root (like 1000)

    #   # Configure Container Security Context (matches spec.template.spec.containers[0].securityContext)
    #   containerSecurityContext:
    #     enabled: true
    #     allowPrivilegeEscalation: false
    #     runAsUser: 1000 # Run container as specific user too
    #     runAsNonRoot: true
    #     privileged: false
    #     readOnlyRootFilesystem: true
    #     capabilities:
    #       drop: ["ALL"]

    #   # Configure resource requests and limits
    #   resources:
    #     limits:
    #       memory: 256Mi
    #       cpu: 125m
    #     requests:
    #       cpu: 70m
    #       memory: 200Mi

    #   # Configure probes (matching your settings)
    #   probes:
    #     livenessProbe:
    #       enabled: true
    #       initialDelaySeconds: 5 # Default is often higher, adjust if needed
    #       periodSeconds: 5
    #       timeoutSeconds: 1 # Default
    #       successThreshold: 1 # Default
    #       failureThreshold: 5 # Default
    #       tcpSocket:
    #         port: 6379
    #     readinessProbe:
    #       enabled: true
    #       initialDelaySeconds: 5 # Default is often higher, adjust if needed
    #       periodSeconds: 5
    #       timeoutSeconds: 1 # Default
    #       successThreshold: 1 # Default
    #       failureThreshold: 5 # Default
    #       tcpSocket:
    #         port: 6379

    # # Configure image details
    # image:
    #   registry: docker.io # Default Docker Hub
    #   repository: redis
    #   tag: alpine
    #   # Reference the imagePullSecret you created
    #   pullSecrets:
    #    - ${kubernetes_secret.acr_secret.metadata[0].name}

    # # Configure persistence (disable PVC, use emptyDir like original YAML)
    # persistence:
    #   enabled: false # This is key to match your emptyDir volume
    #   # volumeMounts and volumes related to data are handled internally by the chart
    #   # when persistence is enabled/disabled. Disabling it should achieve the emptyDir behavior.

    # # Service configuration (matches your Service YAML)
    # service:
    #   type: ClusterIP # Default, but explicit
    #   port: 6379
    #   # The service name will be derived from the release name (`redis-cart-master` in standalone)
    #   # The service selector is handled automatically by Helm based on the labels it applies.
    #   # You can override service name if needed:
    #   nameOverride: redis-cart # If you want the service DNS exactly as 'redis-cart'

    # # Disable Sentinel as we're running standalone
    # sentinel:
    #   enabled: false
    # YAML
  ]

  # Ensure the ACR secret exists before trying to pull the image
  depends_on = [
    azurerm_kubernetes_cluster.aks,
    kubernetes_secret.acr_secret,
    # Optional, but good practice: ensure nginx is settled if redis depends on it somehow,
    # although unlikely in this specific case. More importantly, ensures cluster is ready.
    helm_release.nginx_ingress
  ]
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
