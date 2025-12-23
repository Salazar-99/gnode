# Main Terraform configuration for gnode Azure deployment

# Detect local IP address if not provided
data "http" "local_ip" {
  count = var.local_ip_address == "" ? 1 : 0
  url   = "https://api.ipify.org?format=text"

  request_headers = {
    Accept = "text/plain"
  }
}

# Fetch GitHub Actions IP ranges from GitHub API
data "http" "github_meta" {
  count = var.enable_github_actions_ips ? 1 : 0
  url   = "https://api.github.com/meta"

  request_headers = {
    Accept               = "application/vnd.github+json"
    X-GitHub-Api-Version = "2022-11-28"
  }
}

locals {
  local_ip_cidr = var.local_ip_address != "" ? var.local_ip_address : "${chomp(data.http.local_ip[0].response_body)}/32"

  # GitHub Actions IP ranges fetched from API
  github_actions_ips = var.enable_github_actions_ips ? jsondecode(data.http.github_meta[0].response_body).actions : []

  # Separate IPv4 and IPv6 as they cannot be mixed in the same Azure NSG rule
  github_ipv4 = [for ip in local.github_actions_ips : ip if !can(regex(":", ip))]
  github_ipv6 = [for ip in local.github_actions_ips : ip if can(regex(":", ip))]

  # Azure NSG has a total limit of 4000 source address prefixes per security group.
  # As of late 2025, GitHub Actions has over 5500 IP ranges, exceeding this limit.
  # We filter the list to stay within Azure's 4000 limit by prioritizing IPv4
  # and taking the first 3900 IPv4 ranges, then as many IPv6 as will fit.
  github_ipv4_final = length(local.github_ipv4) > 0 ? slice(local.github_ipv4, 0, min(length(local.github_ipv4), 3900)) : []
  github_ipv6_final = length(local.github_ipv6) > 0 ? slice(local.github_ipv6, 0, min(length(local.github_ipv6), 4000 - length(local.github_ipv4_final) - 20)) : []
}

# Ensure a placeholder kubeconfig exists so the provider doesn't fail validation
# on the very first plan before the VM is even created.
# This file is gitignored and will be overwritten with real data by the VM provisioner.
resource "local_file" "kubeconfig_placeholder" {
  count    = fileexists("${path.module}/../../kubeconfig.yaml") ? 0 : 1
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
  filename = "${path.module}/../../kubeconfig.yaml"
}

