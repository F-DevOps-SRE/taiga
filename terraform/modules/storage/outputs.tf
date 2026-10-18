output "account_name" {
  value       = azurerm_storage_account.storage.name
  description = "Nombre de la Storage Account"
}

output "primary_access_key" {
  value       = azurerm_storage_account.storage.primary_access_key
  sensitive   = true
  description = "Llave primaria de acceso a la Storage Account"
}