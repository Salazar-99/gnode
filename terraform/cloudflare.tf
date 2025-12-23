# Cloudflare DNS configuration

# Look up the zone ID for the root domain
data "cloudflare_zone" "main" {
  name = var.root_domain
}

# A record for root domain pointing to VM public IP
resource "cloudflare_record" "root_domain" {
  zone_id         = data.cloudflare_zone.main.id
  name            = "@"
  type            = "A"
  content         = azurerm_public_ip.gnode_ip.ip_address
  ttl             = 300
  proxied         = false
  allow_overwrite = true

  depends_on = [azurerm_public_ip.gnode_ip]
}

# CNAME record for www subdomain pointing to root domain
resource "cloudflare_record" "www_subdomain" {
  zone_id         = data.cloudflare_zone.main.id
  name            = "www"
  type            = "CNAME"
  content         = var.root_domain
  ttl             = 300
  proxied         = false
  allow_overwrite = true

  depends_on = [cloudflare_record.root_domain]
}

# CNAME record for grafana subdomain pointing to root domain
resource "cloudflare_record" "grafana_subdomain" {
  zone_id         = data.cloudflare_zone.main.id
  name            = "grafana"
  type            = "CNAME"
  content         = var.root_domain
  ttl             = 300
  proxied         = false
  allow_overwrite = true

  depends_on = [cloudflare_record.root_domain]
}

