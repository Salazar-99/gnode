output "vm_public_ip" {
  description = "Public IP address of the gnode VM"
  value       = azurerm_public_ip.gnode_ip.ip_address
}

output "vm_private_ip" {
  description = "Private IP address of the gnode VM"
  value       = azurerm_network_interface.gnode_nic.private_ip_address
}

output "gnode_kubeconfig" {
  description = "Path to the kubeconfig file (copied locally with server IP updated)"
  value       = "${path.module}/../kubeconfig.yaml"
}

output "dns_root_record" {
  description = "Cloudflare DNS A record for root domain"
  value       = cloudflare_record.root_domain.hostname
}

output "dns_www_record" {
  description = "Cloudflare DNS CNAME record for www.{root domain}"
  value       = cloudflare_record.www_subdomain.hostname
}

output "dns_grafana_record" {
  description = "Cloudflare DNS CNAME record for grafana.{root domain}"
  value       = cloudflare_record.grafana_subdomain.hostname
}

