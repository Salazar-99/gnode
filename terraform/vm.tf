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

  custom_data = base64encode(file("${path.module}/../manifests/cloud-init.yaml"))

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
      MAX_ATTEMPTS=60
      ATTEMPT=0
      
      echo "Waiting for k3s to be ready..."
      
      while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
        # Check if k3s service is active and kubeconfig exists
        if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 \
          $ADMIN_USER@$VM_IP \
          'sudo systemctl is-active k3s > /dev/null 2>&1 && sudo test -f /etc/rancher/k3s/k3s.yaml' 2>/dev/null; then
          echo "k3s is ready!"
          exit 0
        fi
        
        ATTEMPT=$((ATTEMPT + 1))
        echo "Attempt $ATTEMPT/$MAX_ATTEMPTS: k3s not ready yet, waiting 2 seconds..."
        sleep 2
      done
      
      echo "ERROR: k3s did not become ready within $((MAX_ATTEMPTS * 2)) seconds"
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
      
      # Copy kubeconfig from VM
      ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        $ADMIN_USER@$VM_IP \
        'sudo cat /etc/rancher/k3s/k3s.yaml' > ${path.module}/../kubeconfig.yaml.tmp
      
      # Replace server IP with VM's public IP
      sed "s|server: https://127.0.0.1:6443|server: https://$VM_IP:6443|g" \
        ${path.module}/../kubeconfig.yaml.tmp > ${path.module}/../kubeconfig.yaml
      
      # Clean up temp file
      rm -f ${path.module}/../kubeconfig.yaml.tmp
      
      echo "Kubeconfig copied to ${path.module}/../kubeconfig.yaml"
    EOT
  }

  # Re-run if VM IP changes
  provisioner "local-exec" {
    when    = destroy
    command = "rm -f ${path.module}/../kubeconfig.yaml"
  }
}
