# Kubernetes manifests applied after Helm chart installations

# Parse YAML files to extract individual resources
locals {
  # Sanitize domain name for use in Kubernetes resource names (replace dots and dashes with hyphens)
  domain_name_sanitized = replace(replace(var.root_domain, ".", "-"), "--", "-")

  # Use provided email or default to admin@root_domain
  letsencrypt_email = var.letsencrypt_email != "" ? var.letsencrypt_email : "admin@${var.root_domain}"

  # Template variables for YAML files
  template_vars = {
    root_domain           = var.root_domain
    domain_name_sanitized = local.domain_name_sanitized
    letsencrypt_email     = local.letsencrypt_email
  }

  # Parse certs.yaml - split by document separator and decode each
  # Handle both "---\n" and "---" separators, filter out empty strings
  certs_raw       = templatefile("${path.module}/../../manifests/certs.yaml", local.template_vars)
  certs_split     = [for s in split("---", local.certs_raw) : trimspace(s) if s != "" && trimspace(s) != ""]
  certs_documents = [for doc in local.certs_split : yamldecode(doc) if doc != ""]

  # Extract individual resources from certs.yaml
  cluster_issuer_manifest      = local.certs_documents[0]
  certificate_manifest         = local.certs_documents[1]
  root_domain_ingress_manifest = local.certs_documents[2]

  # Parse grafana-ingress.yaml (single document)
  grafana_ingress_manifest = yamldecode(templatefile("${path.module}/../../manifests/grafana-ingress.yaml", local.template_vars))
}

# ClusterIssuer for Let's Encrypt
resource "null_resource" "letsencrypt_cluster_issuer" {
  depends_on = [helm_release.cert_manager]

  triggers = {
    manifest_hash = sha256(jsonencode(local.cluster_issuer_manifest))
  }

  provisioner "local-exec" {
    command = "kubectl --kubeconfig=${path.module}/../../kubeconfig.yaml apply -f - <<EOF\n${yamlencode(local.cluster_issuer_manifest)}\nEOF"
  }
}

# Certificate for root domain
resource "null_resource" "root_domain_certificate" {
  depends_on = [null_resource.letsencrypt_cluster_issuer]

  triggers = {
    manifest_hash = sha256(jsonencode(local.certificate_manifest))
  }

  provisioner "local-exec" {
    command = "kubectl --kubeconfig=${path.module}/../../kubeconfig.yaml apply -f - <<EOF\n${yamlencode(local.certificate_manifest)}\nEOF"
  }
}

# Ingress for root domain
resource "null_resource" "root_domain_ingress" {
  depends_on = [null_resource.root_domain_certificate]

  triggers = {
    manifest_hash = sha256(jsonencode(local.root_domain_ingress_manifest))
  }

  provisioner "local-exec" {
    command = "kubectl --kubeconfig=${path.module}/../../kubeconfig.yaml apply -f - <<EOF\n${yamlencode(local.root_domain_ingress_manifest)}\nEOF"
  }
}

# Ingress for Grafana
resource "null_resource" "grafana_ingress" {
  depends_on = [
    helm_release.kube_prometheus_stack,
    null_resource.letsencrypt_cluster_issuer,
  ]

  triggers = {
    manifest_hash = sha256(jsonencode(local.grafana_ingress_manifest))
  }

  provisioner "local-exec" {
    command = "kubectl --kubeconfig=${path.module}/../../kubeconfig.yaml apply -f - <<EOF\n${yamlencode(local.grafana_ingress_manifest)}\nEOF"
  }
}

# Create apps namespace for application deployments
# Only create if ACR credentials are provided (since we'll put the secret there)
resource "kubernetes_namespace" "apps" {
  count = var.acr_registry_url != "" && var.acr_username != "" && var.acr_password != "" ? 1 : 0

  depends_on = [
    data.kubernetes_nodes.cluster,
  ]

  metadata {
    name = var.acr_secret_namespace
  }
}

# Azure Container Registry image pull secret
# Only create if ACR credentials are provided
resource "kubernetes_secret" "acr_image_pull_secret" {
  count = var.acr_registry_url != "" && var.acr_username != "" && var.acr_password != "" ? 1 : 0

  depends_on = [
    data.kubernetes_nodes.cluster,
    kubernetes_namespace.apps,
  ]

  metadata {
    name      = var.acr_secret_name
    namespace = var.acr_secret_namespace
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "${var.acr_registry_url}" = {
          username = var.acr_username
          password = var.acr_password
          auth     = base64encode("${var.acr_username}:${var.acr_password}")
        }
      }
    })
  }
}

