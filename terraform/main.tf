# Main Terraform configuration for gnode Azure deployment

# Detect local IP address if not provided
data "http" "local_ip" {
  count = var.local_ip_address == "" ? 1 : 0
  url   = "https://api.ipify.org?format=text"

  request_headers = {
    Accept = "text/plain"
  }
}

locals {
  local_ip_cidr = var.local_ip_address != "" ? var.local_ip_address : "${chomp(data.http.local_ip[0].response_body)}/32"
}

# Ensure a placeholder kubeconfig exists so the provider doesn't fail validation
# on the very first plan before the VM is even created.
# This file is gitignored and will be overwritten with real data by the VM provisioner.
resource "local_file" "kubeconfig_placeholder" {
  count    = fileexists("${path.module}/../kubeconfig.yaml") ? 0 : 1
  content  = <<-EOF
    apiVersion: v1
    clusters:
    - cluster:
        server: https://localhost:6443
      name: placeholder
    contexts:
    - context:
        cluster: placeholder
        user: placeholder
      name: placeholder
    current-context: placeholder
    kind: Config
    preferences: {}
    users:
    - name: placeholder
      user:
        token: placeholder
  EOF
  filename = "${path.module}/../kubeconfig.yaml"
}

