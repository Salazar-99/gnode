variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
  default     = "gnode"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "westus2"
}

variable "vm_size" {
  description = "Size of the virtual machine"
  type        = string
  default     = "Standard_D4s_v3"
}

variable "admin_username" {
  description = "Admin username for the VM"
  type        = string
  default     = "g"
}

variable "ssh_public_key" {
  description = "SSH public key for VM access"
  type        = string
}

variable "vm_name" {
  description = "Name of the virtual machine"
  type        = string
  default     = "gnode"
}

variable "github_actions_ips" {
  description = "List of GitHub Actions IP CIDR ranges allowed to access port 6443"
  type        = list(string)
  default = [
    "140.82.112.0/20",
    "143.55.64.0/20",
    "185.199.108.0/22",
    "192.30.252.0/22",
    "2620:112:3000::/44"
  ]
}

variable "local_ip_address" {
  description = "Local IP address (CIDR) to allow access to port 6443. If not provided, will attempt to detect from http endpoint."
  type        = string
  default     = ""
}

variable "acr_registry_url" {
  description = "Azure Container Registry URL (e.g., myregistry.azurecr.io)"
  type        = string
  default     = ""
}

variable "acr_username" {
  description = "Azure Container Registry username/token"
  type        = string
  default     = ""
  sensitive   = true
}

variable "acr_password" {
  description = "Azure Container Registry password"
  type        = string
  default     = ""
  sensitive   = true
}

variable "acr_secret_name" {
  description = "Name for the Kubernetes image pull secret"
  type        = string
  default     = "acr-secret"
}

variable "acr_secret_namespace" {
  description = "Namespace where the image pull secret will be created"
  type        = string
  default     = "apps"
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with DNS edit permissions"
  type        = string
  sensitive   = true
}

variable "root_domain" {
  description = "Root domain name (e.g., gerardosalazar.com)"
  type        = string
}

variable "letsencrypt_email" {
  description = "Email address for Let's Encrypt certificate notifications. Defaults to admin@{root_domain}"
  type        = string
  default     = ""
}

variable "grafana_admin_password" {
  description = "Admin password for Grafana dashboard"
  type        = string
  sensitive   = true
}

