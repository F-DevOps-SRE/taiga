output "taiga_url" {
  value       = module.container_apps.taiga_url
  description = "URL pública de Taiga"
}

output "app_insights_id" {
  value       = module.container_apps.app_insights_id
  description = "Resource ID de Application Insights (fuente de datos de Grafana)"
}
