# Se usa el host del pooler (PgBouncer en modo transacción): Neon admite muchas más
# conexiones así. Por eso taiga-back desactiva los cursores del lado del servidor.
output "host" {
  value = neon_project.taiga.database_host_pooler
}

output "database" {
  value = neon_project.taiga.database_name
}

output "user" {
  value = neon_project.taiga.database_user
}

output "password" {
  value     = neon_project.taiga.database_password
  sensitive = true
}
