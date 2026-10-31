output "taiga_url" {
  value       = local.taiga_url
  description = "URL pública de Taiga"
}

output "app_insights_id" {
  value       = azurerm_application_insights.appi.id
  description = "Resource ID de Application Insights (fuente de datos de Grafana)"
}
