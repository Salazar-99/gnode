# gnode

IaC for a single-node Kubernetes cluster running on Azure.

This Terraform module deploys:
- A single Azure VM
- Installs k3s in server configuration
- Installs the `kube-prometheus-stack` Helm chart and exposes Grafana at `grafana.${root-domain}` for monitoring the system
- Installs `cert-manager` and configures certs and Ingress for your `${root-domain}`
- Optionally installs `ImagePullSecrets` for your Azure Container Registry in your chosen namespace (defaults to `apps`)

## Requirements
- Terraform installed
- Azure CLI installed and logged in (`az login`)
- An active Azure account with permissions to create VMs and networking resources
- A domain registered with Cloudflare (with API token that has DNS edit permissions)
- SSH keypair for VM access (**RSA format required by Azure**, e.g., `ssh-keygen -t rsa -b 4096`)
- (Optional) An existing Azure Container Registry for deploying your applications

Make sure you have your API keys and credentials ready!

## Usage
Login to Azure with

```az login```

Configure environment variables and secrets by running the setup script (see [Configuration](#configuration) below for details)

```source setup.sh```

Run Terraform (from the terraform directory)
```bash
cd terraform
terraform init
terraform plan -var-file=prod.tfvars
terraform apply -var-file=prod.tfvars
```

The whole process should take approximately 10-15 minutes end to end. Terraform will output the public IP of the instance and a properly configured kubeconfig to connect to the cluster.

## Connecting To The System

After Terraform completes, you have two ways to interact with your cluster:

### SSH Access

SSH into the VM using the admin username you configured and the VM's public IP (output by Terraform):

```bash
ssh <admin_username>@<vm_public_ip>
```

For example, with the default username:

```bash
ssh g@$(terraform output -raw vm_public_ip)
```

The node will have `kubectl` properly configured to interact with the cluster.

### Local Kubernetes Access

First make sure you have `kubectl` installed locally.

Terraform generates a `kubeconfig.yaml` file in the repository root, pre-configured with the cluster's public IP. A placeholder is created automatically during setup to ensure the Terraform providers can initialize correctly.

**Option 1: Use the KUBECONFIG environment variable**

```bash
export KUBECONFIG=$(pwd)/kubeconfig.yaml
kubectl get nodes
```

**Option 2: Copy to your default kubeconfig location**

To avoid setting the environment variable each time, move the kubeconfig to the default location:

```bash
# Back up your existing kubeconfig if you have one
cp ~/.kube/config ~/.kube/config.backup

# Copy the new kubeconfig
mkdir -p ~/.kube
cp kubeconfig.yaml ~/.kube/config

# Verify access
kubectl get nodes
```

You can now use `kubectl` without setting any environment variables:

```bash
kubectl apply -f my-app.yaml
kubectl get pods -n apps
```

## Deploying An Application

After Terraform completes, an Ingress is created for your root domain (`${root_domain}` and `www.${root_domain}`) with TLS certificates automatically provisioned via Let's Encrypt. However, this Ingress points to a service that **does not exist yet**.

To serve traffic on your root domain, you need to deploy:

1. **A Deployment (or Pod)** - Your application workload
2. **A Service** - Named `${domain_name_sanitized}-service` (e.g., for `example.com`, the service should be named `example-com-service`)

Example deployment in the `apps` namespace:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: apps
spec:
  replicas: 1
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: app
        image: "" # you put your image here, it can be from your ACR!
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: example-com-service  # Replace with your sanitized domain name
  namespace: apps
spec:
  selector:
    app: my-app
  ports:
  - port: 80
    targetPort: 80
```

Deploy using `kubectl`:

```bash
kubectl apply -f my-app.yaml
```

Until you deploy this service, requests to your root domain will return 503 errors.

## Monitoring The System

Once the deployment is complete you can monitor your system via Grafana by visiting `grafana.${root_domain}` and logging in as the `admin` user with the password you configured.

## Configuration

The `setup.sh` script prompts for all configuration variables and secrets. Variables are written to `terraform/prod.tfvars`, while secrets are set as environment variables.

### Variables

| Name | Required | Description |
|------|----------|-------------|
| `resource_group_name` | No | Azure resource group name (default: `gnode`) |
| `location` | No | Azure region (default: `westus2`) |
| `vm_size` | No | Azure VM size (default: `Standard_D4s_v3`, ~$140/mo) |
| `admin_username` | No | SSH admin username for the VM (default: `g`) |
| `vm_name` | No | Name of the Azure VM (default: `gnode`) |
| `enable_github_actions_ips` | No | Whether to allow access to the Kubernetes API from GitHub Actions IP ranges (default: `false`) |
| `github_actions_ips` | No | CIDR ranges to allow Kubernetes API access for GitHub Actions (has sensible defaults) |
| `local_ip_address` | No | Your local IP address (CIDR) to allow Kubernetes API access; auto-detected if not provided |
| `root_domain` | **Yes** | Your root domain name (e.g., `gerardosalazar.com`) |
| `acr_registry_url` | No | Azure Container Registry URL (e.g., `myregistry.azurecr.io`) |
| `acr_secret_name` | No | Name of the Kubernetes image pull secret (default: `acr-secret`; only prompted if ACR URL provided) |
| `acr_secret_namespace` | No | Namespace for the image pull secret (default: `apps`; only prompted if ACR URL provided) |

### Secrets

| Name | Required | Description |
|------|----------|-------------|
| `ssh_public_key` | **Yes** | Path to your SSH public key file for VM access |
| `ssh_private_key_path` | No | Path to the private key matching `ssh_public_key` (defaults to `~/.ssh/id_rsa`) |
| `cloudflare_api_token` | **Yes** | Cloudflare API token with DNS edit permissions for your domain |
| `grafana_admin_password` | **Yes** | Password for the Grafana `admin` user |
| `acr_username` | Conditional | ACR username/token (required only if `acr_registry_url` is provided) |
| `acr_password` | Conditional | ACR password (required only if `acr_registry_url` is provided) |

## Deployment Process

The deployment is split into two phases for better stability and provider isolation:

### Phase 1: Infrastructure (`terraform/infra`)
This phase handles the Azure resources and the k3s installation.
1.  Navigate to the directory: `cd terraform/infra`
2.  Initialize: `terraform init`
3.  Apply: `terraform apply -var-file=prod.tfvars`

**Outputs**: This will generate a `kubeconfig.yaml` in the project root.

### Phase 2: Applications (`terraform/apps`)
This phase handles Helm charts and Kubernetes manifests.
1.  Navigate to the directory: `cd terraform/apps`
2.  Initialize: `terraform init`
3.  Apply: `terraform apply -var-file=prod.tfvars`

---

## Installation Flow and Dependencies

#### Phase 1: Infrastructure Setup (Networking)
1. **Resource Group** (`azurerm_resource_group.gnode_rg`)
   - Creates the Azure resource group which groups all other resources

2. **Virtual Network & Subnet** (`azurerm_virtual_network.gnode_vnet`, `azurerm_subnet.gnode_subnet`)
   - Creates VNet (10.0.0.0/16) and subnet (10.0.1.0/24)

3. **Public IP** (`azurerm_public_ip.gnode_ip`)
   - Allocates static public IP for VM

4. **Network Security Group** (`azurerm_network_security_group.gnode_nsg`)
  - Configures firewall rules:
    - SSH (port 22) - open to all
    - Kubernetes API (port 6443) - restricted to GitHub Actions IPs (if enabled) + local IP
    - HTTP (port 80) - open to all
    - HTTPS (port 443) - open to all
   - Uses local IP detection from `main.tf` (via ipify.org if not provided)

5. **Network Interface** (`azurerm_network_interface.gnode_nic`)
   - Attaches VM to subnet and public IP

6. **NSG Association** (`azurerm_network_interface_security_group_association.gnode_nic_nsg`)
   - Applies security rules to network interface

#### Phase 2: VM Creation & K3s Installation
7. **Virtual Machine** (`azurerm_linux_virtual_machine.gnode_vm`)
   - Creates Ubuntu 22.04 LTS VM
   - Executes `manifests/cloud-init.yaml` on first boot which:
     - Updates packages
     - Installs curl, wget, vim, git
     - Downloads and installs k3s via `curl -sfL https://get.k3s.io | sh -`
     - Enables and starts k3s service

8. **Wait for K3s** (`null_resource.wait_for_k3s`)
   - Polls via SSH to check if k3s is ready using two conditions:
     - `systemctl is-active k3s` - verifies the k3s service is active
     - `test -f /etc/rancher/k3s/k3s.yaml` - verifies the kubeconfig file exists

9. **Copy Kubeconfig** (`null_resource.copy_kubeconfig`)
   - SSHes into VM and copies `/etc/rancher/k3s/k3s.yaml`
   - Replaces `127.0.0.1:6443` with VM's public IP
   - Saves as `kubeconfig.yaml` in this modules directory

#### Phase 3: Infrastructure Helm Charts
10. **Wait for K8s API** (`data.kubernetes_nodes.cluster`)
    - Uses Kubernetes provider to check that the cluster is ready

11. **Install kube-prometheus-stack** (`helm_release.kube_prometheus_stack`)
    - Creates `monitoring` namespace
    - Installs Prometheus, Grafana, and Alertmanager
    - Configures storage and retention settings for a small node
    - Waits for all resources to be ready (300s timeout)

12. **Install cert-manager** (`helm_release.cert_manager`)
    - Creates `cert-manager` namespace
    - Installs cert-manager for TLS certificate management
    - Waits for all resources to be ready (300s timeout)

#### Phase 4: Infrastructure Configuration
13. **Wait for cert-manager to be ready**
    - The `helm_release.cert_manager` resource is configured with `wait = true`, which ensures the deployment and its webhook are ready before proceeding.

14. **Apply cert-manager Manifests** (`kubernetes_manifest` resources)
    - Manifests are templated from `manifests/certs.yaml` using `var.root_domain` and applied in order:
    - **ClusterIssuer** (`kubernetes_manifest.letsencrypt_cluster_issuer`): Creates Let's Encrypt ClusterIssuer with email `admin@${root_domain}`. Depends on `helm_release.cert_manager`.
    - **Certificate** (`kubernetes_manifest.root_domain_certificate`): Creates TLS certificate for `${root_domain}` and `www.${root_domain}`
    - **Ingress** (`kubernetes_manifest.root_domain_ingress`): Creates ingress for `${root_domain}` and `www.${root_domain}` pointing to `${domain_name_sanitized}-service`

15. **Wait for Grafana**
    - The `helm_release.kube_prometheus_stack` resource is configured with `wait = true`, which ensures the Grafana deployment is ready before proceeding.

16. **Apply Grafana Ingress** (`kubernetes_manifest.grafana_ingress`)
    - Manifest is templated from `manifests/grafana-ingress.yaml` using `var.root_domain`
    - Creates ingress for `grafana.${root_domain}`
    - Points to `kube-prometheus-stack-grafana` service in `monitoring` namespace (port 80)
    - Uses cert-manager ClusterIssuer `letsencrypt-prod` for automatic TLS certificate provisioning
    - Uses Traefik ingress class with `web` and `websecure` entrypoints
    - Depends on `helm_release.kube_prometheus_stack` and the ClusterIssuer.

17. **Create apps Namespace** (`kubernetes_namespace.apps`)
    - Creates the `apps` namespace for application deployments

18. **Create ACR Image Pull Secret** (`kubernetes_secret.acr_image_pull_secret`)
    - Creates a Kubernetes image pull secret for Azure Container Registry
    - Default name: `acr-secret` in `apps` namespace (configurable)

### Resource Dependency Graph

```
Resource Group
    ├── Virtual Network
    │   └── Subnet
    ├── Public IP
    ├── NSG
    │
    └── Network Interface
        └── NSG Association
            └── VM
                └── Wait for K3s
                    └── Copy Kubeconfig
                        └── Wait for K8s API
                            ├── Install kube-prometheus-stack
                            │   └── Wait for Grafana
                            │       └── Apply Grafana Ingress
                            ├── Install cert-manager
                            │   └── Wait for cert-manager to be ready
                            │       └── Apply ClusterIssuer
                            │           └── Apply Certificate
                            │               └── Apply root domain Ingress
                            └── Create apps Namespace
                                └── Create ACR Image Pull Secret
```



