# Generador de sufijo aleatorio para asegurar un nombre globalmente único
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_storage_account" "storage" {
  #checkov:skip=CKV_AZURE_206: "Optimizacion de costos: LRS es suficiente para el entorno de laboratorio/demo de Taiga"
  #checkov:skip=CKV_AZURE_33: "Servicio de Queue no es utilizado, solo se requiere Azure Files Share"
  #checkov:skip=CKV_AZURE_59: "Acceso mediante claves permitido sin endpoint privado para simplicidad de despliegue en laboratorio"

  name                     = "sttaiga${random_string.suffix.result}"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  # Permite autenticación mediante Storage Account Key (exigido por el enunciado)
  shared_access_key_enabled = true

  # Correcciones de Seguridad para Checkov
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
}

# Azure Files share para compartir static y media
resource "azurerm_storage_share" "taiga_data" {
  name                 = "taiga-data"
  storage_account_name = azurerm_storage_account.storage.name
  quota                = 5
}