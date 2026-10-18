# Generador de sufijo aleatorio para asegurar un nombre globalmente único
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_storage_account" "storage" {
  name                     = "sttaiga${random_string.suffix.result}"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  # Permite autenticación mediante Storage Account Key (exigido por el enunciado)
  shared_access_key_enabled = true
}

# Azure Files share para compartir static y media
resource "azurerm_storage_share" "taiga_data" {
  name                 = "taiga-data"
  storage_account_name = azurerm_storage_account.storage.name
  quota                = 5
}