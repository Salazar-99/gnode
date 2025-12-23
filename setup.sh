#!/bin/bash

# Script to prompt for all Terraform variables and set up environment
# Usage: ./setup.sh

echo "=== Terraform Variable Setup ==="
echo ""

# Configuration files
TFVARS_FILE="terraform/prod.tfvars"
SECRETS_FILE="terraform/secrets.auto.tfvars"

mkdir -p terraform
> "$TFVARS_FILE"  # Clear/create the file
> "$SECRETS_FILE" # Clear/create the file

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
    eval "$var_name=\"\$final_val\""
}

# Part 1: Configuration Variables
echo "--- Configuration Variables ---"
echo "Press Enter to use default values shown in brackets"
echo ""

ask_input "resource_group_name" "Azure resource group name" "gnode"
echo "resource_group_name = \"$resource_group_name\"" >> "$TFVARS_FILE"

ask_input "location" "Azure region" "westus2"
echo "location = \"$location\"" >> "$TFVARS_FILE"

ask_input "vm_size" "VM size" "Standard_D4s_v3"
echo "vm_size = \"$vm_size\"" >> "$TFVARS_FILE"

ask_input "admin_username" "Admin username" "g"
echo "admin_username = \"$admin_username\"" >> "$TFVARS_FILE"

ask_input "vm_name" "VM name" "gnode"
echo "vm_name = \"$vm_name\"" >> "$TFVARS_FILE"

ask_input "gh_input" "GitHub Actions IPs (comma-separated, or Enter for default)" ""
if [ -z "$gh_input" ]; then
    github_actions_ips='["140.82.112.0/20", "143.55.64.0/20", "185.199.108.0/22", "192.30.252.0/22", "2620:112:3000::/44"]'
else
    github_actions_ips="["
    first=true
    SAVE_IFS=$IFS
    IFS=','
    for ip in $gh_input; do
        if [ "$first" = true ]; then first=false; else github_actions_ips+=", "; fi
        clean_ip=$(echo "$ip" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        github_actions_ips+="\"$clean_ip\""
    done
    IFS=$SAVE_IFS
    github_actions_ips+="]"
fi
echo "github_actions_ips = $github_actions_ips" >> "$TFVARS_FILE"

ask_input "local_ip_address" "Local IP address (CIDR) [empty]" ""
if [ -n "$local_ip_address" ]; then
    echo "local_ip_address = \"$local_ip_address\"" >> "$TFVARS_FILE"
fi

ask_input "acr_registry_url" "ACR registry URL (e.g., myregistry.azurecr.io) [optional]" ""
if [ -n "$acr_registry_url" ]; then
    echo "acr_registry_url = \"$acr_registry_url\"" >> "$TFVARS_FILE"
    
    ask_input "acr_secret_name" "ACR secret name" "acr-secret"
    echo "acr_secret_name = \"$acr_secret_name\"" >> "$TFVARS_FILE"

    ask_input "acr_secret_namespace" "ACR secret namespace" "apps"
    echo "acr_secret_namespace = \"$acr_secret_namespace\"" >> "$TFVARS_FILE"
fi

ask_input "root_domain" "Root domain name (required)" ""
if [ -z "$root_domain" ]; then
    echo "Error: root_domain is required"
    exit 1
fi
echo "root_domain = \"$root_domain\"" >> "$TFVARS_FILE"

echo ""
echo "--- Secrets (Environment Variables) ---"
echo "These will be written to $SECRETS_FILE"
echo ""

# SSH Key
echo "SSH Key: Azure requires RSA format. If you don't have one, press Enter to automatically generate it."
ask_input "SSH_KEY_FILE" "Enter path to SSH public key file" ""
if [ -n "$SSH_KEY_FILE" ]; then
    if [ -f "$SSH_KEY_FILE" ]; then
        # Check if it's an RSA key
        if grep -q "ssh-rsa" "$SSH_KEY_FILE"; then
            ssh_pub_key=$(cat "$SSH_KEY_FILE")
            echo "ssh_public_key = \"$ssh_pub_key\"" >> "$SECRETS_FILE"
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
        echo "ssh_public_key = \"$ssh_pub_key\"" >> "$SECRETS_FILE"
        echo "✓ Using existing RSA key found at $DEFAULT_KEY"
    else
        NEW_KEY="$HOME/.ssh/id_rsa_gnode"
        if [ -f "$NEW_KEY" ]; then
            ssh_pub_key=$(cat "${NEW_KEY}.pub")
            echo "ssh_public_key = \"$ssh_pub_key\"" >> "$SECRETS_FILE"
            echo "✓ Using existing gnode RSA key found at $NEW_KEY.pub"
        else
            echo "--- Generating new RSA key pair for gnode ---"
            ssh-keygen -t rsa -b 4096 -f "$NEW_KEY" -N ""
            ssh_pub_key=$(cat "${NEW_KEY}.pub")
            echo "ssh_public_key = \"$ssh_pub_key\"" >> "$SECRETS_FILE"
            echo "NOTE: New RSA key pair generated at $NEW_KEY"
            echo "✓ New RSA key loaded"
        fi
    fi
fi

# Cloudflare Token
ask_input "cf_token" "Enter Cloudflare API token" "" "true"
if [ -z "$cf_token" ]; then echo "Error: required"; exit 1; fi
echo "cloudflare_api_token = \"$cf_token\"" >> "$SECRETS_FILE"

# Grafana Password
ask_input "graf_pass" "Enter Grafana admin password" "" "true"
if [ -z "$graf_pass" ]; then echo "Error: required"; exit 1; fi
echo "grafana_admin_password = \"$graf_pass\"" >> "$SECRETS_FILE"

# ACR Secrets
if [ -n "$acr_registry_url" ]; then
    ask_input "acr_user" "Enter ACR username" "" "true"
    echo "acr_username = \"$acr_user\"" >> "$SECRETS_FILE"
    
    ask_input "acr_pass" "Enter ACR password" "" "true"
    echo "acr_password = \"$acr_pass\"" >> "$SECRETS_FILE"
    
    echo "acr_registry_url = \"$acr_registry_url\"" >> "$SECRETS_FILE"
fi

# Set permissions
chmod 600 "$SECRETS_FILE"

# Part 3: Ensure kubeconfig placeholder exists for Terraform provider validation
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

echo ""
echo "=== Setup Complete ==="
echo "1. Configuration: $TFVARS_FILE"
echo "2. Secrets:      $SECRETS_FILE (Automatically loaded by Terraform)"
echo ""
echo "You can now run:"
echo "  cd terraform"
echo "  terraform init"
echo "  terraform plan -var-file=prod.tfvars"
echo ""
