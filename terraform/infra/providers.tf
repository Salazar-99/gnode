# Provider configurations for Infrastructure
# Only includes providers needed for VM and Networking

provider "azurerm" {
  features {}
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
