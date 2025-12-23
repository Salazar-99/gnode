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

