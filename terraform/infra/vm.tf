# Virtual Machine configuration for gnode

resource "azurerm_linux_virtual_machine" "gnode_vm" {
  name                = var.vm_name
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = var.vm_size
  admin_username      = var.admin_username

  network_interface_ids = [
    azurerm_network_interface.gnode_nic.id,
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  custom_data = base64encode(file("${path.module}/../../manifests/cloud-init.yaml"))

  tags = {
    environment = "gnode"
  }
}

# Wait for k3s to be ready before copying kubeconfig
# Polls via SSH to check if k3s service is active and kubeconfig exists
resource "null_resource" "wait_for_k3s" {
  depends_on = [azurerm_linux_virtual_machine.gnode_vm]

  triggers = {
    vm_id      = azurerm_linux_virtual_machine.gnode_vm.id
    vm_ip      = azurerm_public_ip.gnode_ip.ip_address
    admin_user = var.admin_username
  }

  provisioner "local-exec" {
    command = <<-EOT
      VM_IP="${azurerm_public_ip.gnode_ip.ip_address}"
      ADMIN_USER="${var.admin_username}"
      SSH_KEY="${var.ssh_private_key_path}"
      MAX_ATTEMPTS=150
      ATTEMPT=0
      
      echo "Waiting for k3s to be ready (this can take up to 5 minutes)..."
      
      while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
        # Build SSH command with optional private key
        SSH_CMD="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5"
        if [ -n "$SSH_KEY" ]; then
          # Handle tilde expansion if necessary
          EXPANDED_KEY=$(eval echo $SSH_KEY)
          if [ -f "$EXPANDED_KEY" ]; then
            SSH_CMD="$SSH_CMD -i $EXPANDED_KEY"
          fi
        fi

        # Check if k3s service is active and kubeconfig exists
        # We don't redirect stderr to /dev/null here so we can see SSH errors
        if $SSH_CMD $ADMIN_USER@$VM_IP \
          'sudo systemctl is-active k3s > /dev/null 2>&1 && sudo test -f /etc/rancher/k3s/k3s.yaml'; then
          echo "k3s is ready!"
          exit 0
        fi
        
        ATTEMPT=$((ATTEMPT + 1))
        echo "Attempt $ATTEMPT/$MAX_ATTEMPTS: k3s not ready yet, waiting 2 seconds..."
        sleep 2
      done
      
      echo "ERROR: k3s did not become ready within 5 minutes"
      exit 1
    EOT
  }
}

# Copy kubeconfig from VM and replace server IP with VM's public IP
resource "null_resource" "copy_kubeconfig" {
  depends_on = [
    azurerm_linux_virtual_machine.gnode_vm,
    null_resource.wait_for_k3s,
  ]

  triggers = {
    vm_id      = azurerm_linux_virtual_machine.gnode_vm.id
    vm_ip      = azurerm_public_ip.gnode_ip.ip_address
    admin_user = var.admin_username
  }

  provisioner "local-exec" {
    command = <<-EOT
      VM_IP="${azurerm_public_ip.gnode_ip.ip_address}"
      ADMIN_USER="${var.admin_username}"
      SSH_KEY="${var.ssh_private_key_path}"
      
      echo "Copying kubeconfig from VM..."
      
      # Build SSH command with optional private key
      SSH_CMD="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
      if [ -n "$SSH_KEY" ]; then
        # Handle tilde expansion if necessary
        EXPANDED_KEY=$(eval echo $SSH_KEY)
        if [ -f "$EXPANDED_KEY" ]; then
          SSH_CMD="$SSH_CMD -i $EXPANDED_KEY"
        fi
      fi

      # Copy kubeconfig from VM
      $SSH_CMD $ADMIN_USER@$VM_IP \
        'sudo cat /etc/rancher/k3s/k3s.yaml' > ${path.module}/../../kubeconfig.yaml.tmp
      
      # Replace server IP with VM's public IP
      sed "s|server: https://127.0.0.1:6443|server: https://$VM_IP:6443|g" \
        ${path.module}/../../kubeconfig.yaml.tmp > ${path.module}/../../kubeconfig.yaml
      
      # Clean up temp file
      rm -f ${path.module}/../../kubeconfig.yaml.tmp
      
      echo "Kubeconfig copied to ${path.module}/../../kubeconfig.yaml"
    EOT
  }

  # Re-run if VM IP changes
  provisioner "local-exec" {
    when    = destroy
    command = "rm -f ${path.module}/../../kubeconfig.yaml"
  }
}
