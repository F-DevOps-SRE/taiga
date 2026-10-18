resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-taiga"
  address_space       = ["10.0.0.0/16"]
  location            = var.location
  resource_group_name = var.resource_group_name
}

# 1. Grupo de Seguridad de Red (NSG) para la subred
resource "azurerm_network_security_group" "nsg_aca" {
  name                = "nsg-aca"
  location            = var.location
  resource_group_name = var.resource_group_name
}

# 2. Subred delegada a Azure Container Apps
resource "azurerm_subnet" "snet_aca" {
  name                 = "snet-aca"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.0.0/23"]

  delegation {
    name = "delegation-container-apps"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# 3. Asociación entre Subred y NSG (Resuelve CKV2_AZURE_31)
resource "azurerm_subnet_network_security_group_association" "nsg_assoc" {
  subnet_id                 = azurerm_subnet.snet_aca.id
  network_security_group_id = azurerm_network_security_group.nsg_aca.id
}