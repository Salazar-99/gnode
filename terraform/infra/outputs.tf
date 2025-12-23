output "vm_public_ip" {
  description = "The public IP address of the VM"
  value       = azurerm_public_ip.gnode_ip.ip_address
}

output "vm_private_ip" {
  description = "The private IP address of the VM"
  value       = azurerm_linux_virtual_machine.gnode_vm.private_ip_address
}

output "kubeconfig_path" {
  description = "The path to the generated kubeconfig file"
  value       = abspath("${path.module}/../../kubeconfig.yaml")
}
