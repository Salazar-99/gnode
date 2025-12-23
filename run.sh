#!/bin/bash

# Script to prompt for all Terraform variables and set up environment
# Usage: ./run.sh         - Interactive setup and deployment
#        ./run.sh destroy - Destroy all resources
#        ./run.sh cleanup - Delete all .terraform, tfstate, and tfvars files

# Get the absolute path to the root directory
ROOT_DIR=$(cd "$(dirname "$0")" && pwd)

# Handle destroy command
if [ "$1" = "destroy" ]; then
    echo "=== Destroying Terraform Resources ==="
    echo ""
    echo "This will destroy all resources created by Terraform."
    echo "Press Ctrl+C to cancel, or wait 5 seconds to continue..."
    sleep 5
    echo ""

    DESTROY_FAILED=false

    # Destroy apps first (depends on infra)
    echo "Step 1: Destroying Applications..."
    cd "$ROOT_DIR/terraform/apps" || exit 1
    if [ -f "terraform.tfstate" ]; then
        terraform init -input=false
        if terraform destroy -auto-approve -var-file=prod.tfvars; then
            echo "✓ Applications destroyed"
        else
            # If destroy failed, check if the cluster is reachable
            # If not, the apps were destroyed along with the cluster - not an error
            if kubectl get nodes --kubeconfig="$ROOT_DIR/kubeconfig.yaml" &>/dev/null; then
                echo "✗ Applications destroy failed"
                DESTROY_FAILED=true
            else
                echo "⚠ Cluster unreachable - apps were destroyed with the cluster"
                # Remove stale state files since resources are gone with cluster
                rm -f terraform.tfstate terraform.tfstate.backup
            fi
        fi
    else
        echo "⚠ No apps state found, skipping..."
    fi

    # Destroy infrastructure
    echo ""
    echo "Step 2: Destroying Infrastructure..."
    cd "$ROOT_DIR/terraform/infra" || exit 1
    if [ -f "terraform.tfstate" ]; then
        terraform init -input=false
        if terraform destroy -auto-approve -var-file=prod.tfvars; then
            echo "✓ Infrastructure destroyed"
        else
            echo "✗ Infrastructure destroy failed"
            DESTROY_FAILED=true
        fi
    else
        echo "⚠ No infra state found, skipping..."
    fi

    echo ""
    if [ "$DESTROY_FAILED" = true ]; then
        echo "=========================================="
        echo "     DESTROY COMPLETED WITH ERRORS"
        echo "=========================================="
        echo ""
        echo "NOTE: Some Azure resources may not be fully deleted"
        echo "due to Azure quirks. Check your resource group in the"
        echo "Azure Portal and manually delete any remaining resources."
        echo ""
        exit 1
    else
        echo "=========================================="
        echo "        DESTROY COMPLETE"
        echo "=========================================="
        echo ""
        echo "NOTE: Some Azure resources may not be fully deleted"
        echo "due to Azure quirks. Check your resource group in the"
        echo "Azure Portal and manually delete any remaining resources."
        echo ""
        exit 0
    fi
fi

# Handle cleanup command
if [ "$1" = "cleanup" ]; then
    echo "=== Cleaning up Terraform files ==="
    echo ""
    echo "This will delete all .terraform directories, tfstate files, and tfvars files."
    echo "Press Ctrl+C to cancel, or wait 5 seconds to continue..."
    sleep 5
    echo ""

    for module in "$ROOT_DIR/terraform/infra" "$ROOT_DIR/terraform/apps"; do
        if [ -d "$module" ]; then
            echo "Cleaning $module..."
            
            # Remove .terraform directory
            if [ -d "$module/.terraform" ]; then
                rm -rf "$module/.terraform"
                echo "  ✓ Removed .terraform/"
            fi
            
            # Remove .terraform.lock.hcl
            if [ -f "$module/.terraform.lock.hcl" ]; then
                rm -f "$module/.terraform.lock.hcl"
                echo "  ✓ Removed .terraform.lock.hcl"
            fi
            
            # Remove tfstate files
            for f in "$module"/*.tfstate "$module"/*.tfstate.backup; do
                if [ -f "$f" ]; then
                    rm -f "$f"
                    echo "  ✓ Removed $(basename "$f")"
                fi
            done
            
            # Remove tfvars files
            for f in "$module"/*.tfvars "$module"/*.auto.tfvars; do
                if [ -f "$f" ]; then
                    rm -f "$f"
                    echo "  ✓ Removed $(basename "$f")"
                fi
            done
        fi
    done

    echo ""
    echo "=========================================="
    echo "          CLEANUP COMPLETE"
    echo "=========================================="
    exit 0
fi

echo "=== Terraform Variable Setup ==="
echo ""

# Configuration files
TFVARS_INFRA="terraform/infra/prod.tfvars"
SECRETS_INFRA="terraform/infra/secrets.auto.tfvars"
TFVARS_APPS="terraform/apps/prod.tfvars"
SECRETS_APPS="terraform/apps/secrets.auto.tfvars"

mkdir -p terraform/infra terraform/apps
> "$TFVARS_INFRA"  # Clear/create the file
> "$SECRETS_INFRA" # Clear/create the file
> "$TFVARS_APPS"   # Clear/create the file
> "$SECRETS_APPS"  # Clear/create the file

# Helper function for prompting
# Usage: ask_input "Variable Name" "Prompt message" "default_value" [is_secret]
ask_input() {
    local var_name="$1"
    local prompt_msg="$2"
    local default_val="$3"
    local is_secret="$4"
    local input_val

    local full_prompt="$prompt_msg"
    if [ -n "$default_val" ]; then
        full_prompt="$prompt_msg [$default_val]"
    fi

    if [ "$is_secret" = "true" ]; then
        printf "%s: " "$full_prompt"
        # Using stty for maximum compatibility with bash/zsh when not sourcing
        stty -echo
        read -r input_val
        stty echo
        printf "\n"
    else
        printf "%s: " "$full_prompt"
        read -r input_val
    fi

    # Set the variable in the script scope
    local final_val="${input_val:-$default_val}"
    # Expand tilde if present
    final_val="${final_val/#\~/$HOME}"
    eval "$var_name=\"\$final_val\""
}

# Helper function for yes/no questions
# Usage: ask_yes_no "Variable Name" "Prompt message" "default_val" (true/false)
ask_yes_no() {
    local var_name="$1"
    local prompt_msg="$2"
    local default_val="$3"
    local input_val

    local full_prompt="$prompt_msg"
    if [ -n "$default_val" ]; then
        full_prompt="$prompt_msg (y/n) [$default_val]"
    else
        full_prompt="$prompt_msg (y/n)"
    fi

    printf "%s: " "$full_prompt"
    read -r input_val

    local final_val
    case "${input_val:-$default_val}" in
        [Yy]* ) final_val="true" ;;
        [Nn]* ) final_val="false" ;;
        * ) final_val="false" ;;
    esac
    
    eval "$var_name=\"\$final_val\""
}

# Configuration Variables
echo "--- Configuration Variables ---"
echo "Press Enter to use default values shown in brackets"
echo ""

ask_input "resource_group_name" "Azure resource group name" "gnode"
echo "resource_group_name = \"$resource_group_name\"" >> "$TFVARS_INFRA"

ask_input "location" "Azure region" "westus"
echo "location = \"$location\"" >> "$TFVARS_INFRA"

ask_input "vm_size" "VM size" "Standard_D4s_v3"
echo "vm_size = \"$vm_size\"" >> "$TFVARS_INFRA"

ask_input "admin_username" "Admin username" "g"
echo "admin_username = \"$admin_username\"" >> "$TFVARS_INFRA"

ask_input "vm_name" "VM name" "gnode"
echo "vm_name = \"$vm_name\"" >> "$TFVARS_INFRA"

ask_input "ssh_private_key_path" "Local path to SSH private key" "~/.ssh/id_rsa_gnode"
echo "ssh_private_key_path = \"$ssh_private_key_path\"" >> "$TFVARS_INFRA"

ask_yes_no "enable_github_actions_ips" "Enable GitHub Actions IP ranges (for CI/CD access)" "n"
echo "enable_github_actions_ips = $enable_github_actions_ips" >> "$TFVARS_INFRA"

ask_input "acr_registry_url" "ACR registry URL (e.g., myregistry.azurecr.io) [optional]" ""
if [ -n "$acr_registry_url" ]; then
    echo "acr_registry_url = \"$acr_registry_url\"" >> "$TFVARS_APPS"
    
    ask_input "acr_secret_name" "ACR secret name" "acr-secret"
    echo "acr_secret_name = \"$acr_secret_name\"" >> "$TFVARS_APPS"

    ask_input "acr_secret_namespace" "ACR secret namespace" "apps"
    echo "acr_secret_namespace = \"$acr_secret_namespace\"" >> "$TFVARS_APPS"
fi

ask_input "root_domain" "Root domain name (required)" ""
if [ -z "$root_domain" ]; then
    echo "Error: root_domain is required"
    exit 1
fi
echo "root_domain = \"$root_domain\"" >> "$TFVARS_INFRA"
echo "root_domain = \"$root_domain\"" >> "$TFVARS_APPS"

echo ""
echo "--- Secrets (Environment Variables) ---"
echo "These will be written to $SECRETS_INFRA and $SECRETS_APPS"
echo ""

# SSH Key
echo "SSH Key: Azure requires RSA format. If you don't have one, press Enter to automatically generate it."
ask_input "SSH_KEY_FILE" "Enter path to SSH public key file" ""

if [ -n "$SSH_KEY_FILE" ]; then
    if [ -f "$SSH_KEY_FILE" ]; then
        # Check if it's an RSA key
        if grep -q "ssh-rsa" "$SSH_KEY_FILE"; then
            ssh_pub_key=$(cat "$SSH_KEY_FILE")
            echo "ssh_public_key = \"$ssh_pub_key\"" >> "$SECRETS_INFRA"
            echo "✓ SSH public key loaded from $SSH_KEY_FILE"
        else
            echo "Error: The provided key is not in RSA format (required by Azure Terraform provider)."
            exit 1
        fi
    else
        echo "Error: SSH public key file not found at $SSH_KEY_FILE"
        exit 1
    fi
else
    # Automatically try default location or generate
    DEFAULT_KEY="$HOME/.ssh/id_rsa.pub"
    if [ -f "$DEFAULT_KEY" ] && grep -q "ssh-rsa" "$DEFAULT_KEY"; then
        ssh_pub_key=$(cat "$DEFAULT_KEY")
        echo "ssh_public_key = \"$ssh_pub_key\"" >> "$SECRETS_INFRA"
        echo "✓ Using existing RSA key found at $DEFAULT_KEY"
    else
        NEW_KEY="$HOME/.ssh/id_rsa_gnode"
        if [ -f "$NEW_KEY" ]; then
            ssh_pub_key=$(cat "${NEW_KEY}.pub")
            echo "ssh_public_key = \"$ssh_pub_key\"" >> "$SECRETS_INFRA"
            echo "✓ Using existing gnode RSA key found at $NEW_KEY.pub"
        else
            echo "--- Generating new RSA key pair for gnode ---"
            ssh-keygen -t rsa -b 4096 -f "$NEW_KEY" -N ""
            ssh_pub_key=$(cat "${NEW_KEY}.pub")
            echo "ssh_public_key = \"$ssh_pub_key\"" >> "$SECRETS_INFRA"
            echo "NOTE: New RSA key pair generated at $NEW_KEY"
            echo "✓ New RSA key loaded"
        fi
    fi
fi

# Cloudflare Token (needed by both infra and apps modules)
ask_input "cf_token" "Enter Cloudflare API token" "" "true"
if [ -z "$cf_token" ]; then echo "Error: required"; exit 1; fi
echo "cloudflare_api_token = \"$cf_token\"" >> "$SECRETS_INFRA"
echo "cloudflare_api_token = \"$cf_token\"" >> "$SECRETS_APPS"

# Grafana Password
ask_input "graf_pass" "Enter Grafana admin password" "" "true"
if [ -z "$graf_pass" ]; then echo "Error: required"; exit 1; fi
echo "grafana_admin_password = \"$graf_pass\"" >> "$SECRETS_APPS"

# ACR Secrets
if [ -n "$acr_registry_url" ]; then
    ask_input "acr_user" "Enter ACR username" "" "true"
    echo "acr_username = \"$acr_user\"" >> "$SECRETS_APPS"
    
    ask_input "acr_pass" "Enter ACR password" "" "true"
    echo "acr_password = \"$acr_pass\"" >> "$SECRETS_APPS"
fi

# Ensure kubeconfig placeholder exists for Terraform provider validation
KUBECONFIG_FILE="kubeconfig.yaml"
if [ ! -f "$KUBECONFIG_FILE" ]; then
    cat <<EOF > "$KUBECONFIG_FILE"
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
    echo "✓ Created placeholder kubeconfig.yaml (will be updated after VM creation)"
fi

#  Run Terraform
echo ""
echo "--- Starting Deployment ---"

# Check if required binaries are installed
for cmd in terraform kubectl az; do
    if ! command -v $cmd &> /dev/null; then
        echo "Error: $cmd is not installed. Please install it and try again."
        exit 1
    fi
done

# Check if logged into Azure
if ! az account show &> /dev/null; then
    echo "Error: Not logged into Azure. Please run 'az login' and try again."
    exit 1
fi

# Deploy Infrastructure
echo ""
echo "Step 1: Deploying Infrastructure..."
cd terraform/infra || exit 1
terraform init -input=false

if terraform apply -auto-approve -var-file=prod.tfvars; then
    echo "✓ Infrastructure deployed successfully"
    VM_PUBLIC_IP=$(terraform output -raw vm_public_ip)
    
    # Deploy Applications if Infrastructure succeeds
    echo ""
    echo "Step 2: Deploying Applications (Grafana, Cert-Manager, etc.)..."
    cd "$ROOT_DIR/terraform/apps" || exit 1
    terraform init -input=false

    if terraform apply -auto-approve -var-file=prod.tfvars; then
        echo ""
        echo "=========================================="
        echo "        DEPLOYMENT SUCCESSFUL!"
        echo "=========================================="
        echo "Root Domain:  https://$root_domain"
        echo "Grafana:      https://grafana.$root_domain"
        echo "VM Public IP: $VM_PUBLIC_IP"
        echo ""
        echo "Kubeconfig is available at:"
        echo "  $ROOT_DIR/kubeconfig.yaml"
        echo ""
        echo "You can check your cluster with:"
        echo "  export KUBECONFIG=$ROOT_DIR/kubeconfig.yaml"
        echo "  kubectl get nodes"
        echo "=========================================="
    else
        echo "Error: Applications deployment failed"
        exit 1
    fi
else
    echo "Error: Infrastructure deployment failed"
    exit 1
fi
