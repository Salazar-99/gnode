# Networking configuration for gnode VM

resource "azurerm_resource_group" "gnode_rg" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_virtual_network" "gnode_vnet" {
  name                = "${var.vm_name}-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.gnode_rg.location
  resource_group_name = azurerm_resource_group.gnode_rg.name
}

resource "azurerm_subnet" "gnode_subnet" {
  name                 = "${var.vm_name}-subnet"
  resource_group_name  = azurerm_resource_group.gnode_rg.name
  virtual_network_name = azurerm_virtual_network.gnode_vnet.name
  address_prefixes     = ["10.0.1.0/24"]

  depends_on = [azurerm_virtual_network.gnode_vnet]
}

resource "azurerm_public_ip" "gnode_ip" {
  name                = "${var.vm_name}-public-ip"
  resource_group_name = azurerm_resource_group.gnode_rg.name
  location            = azurerm_resource_group.gnode_rg.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_security_group" "gnode_nsg" {
  name                = "${var.vm_name}-nsg"
  location            = azurerm_resource_group.gnode_rg.location
  resource_group_name = azurerm_resource_group.gnode_rg.name

  # SSH access - restricted to local IP only for security
  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = local.local_ip_cidr
    destination_address_prefix = "*"
  }

  # Kubernetes API port - GitHub Actions IPv4 (Optional, filtered to stay under 4000 total NSG limit)
  dynamic "security_rule" {
    for_each = chunklist(local.github_ipv4_final, 4000)
    content {
      name                       = "K8sAPI-GH-IPv4-${security_rule.key}"
      priority                   = 1002 + security_rule.key
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "6443"
      source_address_prefixes    = security_rule.value
      destination_address_prefix = "*"
    }
  }

  # Kubernetes API port - GitHub Actions IPv6 (Optional, filtered to stay under 4000 total NSG limit)
  dynamic "security_rule" {
    for_each = chunklist(local.github_ipv6_final, 4000)
    content {
      name                       = "K8sAPI-GH-IPv6-${security_rule.key}"
      priority                   = 1102 + security_rule.key
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "6443"
      source_address_prefixes    = security_rule.value
      destination_address_prefix = "*"
    }
  }

  # Kubernetes API port - allow access from local IP address
  security_rule {
    name                       = "KubernetesAPI-LocalIP"
    priority                   = 2000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "6443"
    source_address_prefix      = local.local_ip_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTP"
    priority                   = 1100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTPS"
    priority                   = 1101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "gnode_nic" {
  name                = "${var.vm_name}-nic"
  location            = azurerm_resource_group.gnode_rg.location
  resource_group_name = azurerm_resource_group.gnode_rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.gnode_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.gnode_ip.id
  }
}

resource "azurerm_network_interface_security_group_association" "gnode_nic_nsg" {
  network_interface_id      = azurerm_network_interface.gnode_nic.id
  network_security_group_id = azurerm_network_security_group.gnode_nsg.id
}

