# Helm chart installations for gnode cluster

# Wait for Kubernetes API to be fully ready before installing Helm charts
# Uses Kubernetes provider data source to verify API is responding and nodes are available
data "kubernetes_nodes" "cluster" {
  # Validate that the API is responding and at least one node is available
  lifecycle {
    postcondition {
      condition     = length(self.nodes) > 0
      error_message = "Kubernetes API is not ready or no nodes are available"
    }
  }
}

# Install kube-prometheus-stack
resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "55.0.0"
  namespace        = "monitoring"
  create_namespace = true

  depends_on = [
    data.kubernetes_nodes.cluster,
  ]

  # Wait for all resources to be ready
  wait    = true
  timeout = 300

  # Set some basic values to reduce resource usage for a single node cluster
  values = [
    <<-EOT
    prometheus:
      prometheusSpec:
        retention: 7d
        storageSpec:
          volumeClaimTemplate:
            spec:
              accessModes: ["ReadWriteOnce"]
              resources:
                requests:
                  storage: 10Gi
    grafana:
      enabled: true
      adminPassword: "${var.grafana_admin_password}"
      persistence:
        enabled: true
        size: 5Gi
      resources:
        requests:
          memory: 128Mi
          cpu: 50m
        limits:
          memory: 256Mi
          cpu: 200m
    alertmanager:
      enabled: true
      alertmanagerSpec:
        storage:
          volumeClaimTemplate:
            spec:
              accessModes: ["ReadWriteOnce"]
              resources:
                requests:
                  storage: 2Gi
    EOT
  ]

  set {
    name  = "prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues"
    value = "false"
  }
}

# Install cert-manager
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "v1.13.3"
  namespace        = "cert-manager"
  create_namespace = true

  depends_on = [
    data.kubernetes_nodes.cluster,
  ]

  # Wait for all resources to be ready
  wait    = true
  timeout = 300

  # Install CRDs
  set {
    name  = "installCRDs"
    value = "true"
  }
}

