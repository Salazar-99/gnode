# Provider configurations for Kubernetes and Helm
# These assume that the infrastructure module has already been applied
# and the kubeconfig.yaml file exists in the project root.

provider "kubernetes" {
  config_path = "${path.module}/../../kubeconfig.yaml"
}

provider "helm" {
  kubernetes {
    config_path = "${path.module}/../../kubeconfig.yaml"
  }
}
