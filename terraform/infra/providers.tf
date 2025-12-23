# Provider configurations for Infrastructure
# Only includes providers needed for VM and Networking

provider "azurerm" {
  features {}
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "http" {
  # HTTP provider doesn't require configuration, but explicitly declaring it
  # ensures it's properly initialized for data sources
}
