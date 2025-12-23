# Provider configurations
# Required providers and versions are defined in versions.tf

provider "azurerm" {
  features {}
}

provider "kubernetes" {
  config_path = "${path.module}/../kubeconfig.yaml"
}

provider "helm" {
  kubernetes {
    config_path = "${path.module}/../kubeconfig.yaml"
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

