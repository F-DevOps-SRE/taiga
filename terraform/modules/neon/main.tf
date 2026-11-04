terraform {
  required_providers {
    neon = {
      source = "kislerdm/neon"
    }
  }
}

# Proyecto de Neon: PostgreSQL 15 administrado que se suspende solo cuando no hay
# tráfico y guarda los datos aunque se borre la infraestructura de Azure.
# Se creó desde la consola y Terraform lo adopta con el bloque import de ../../main.tf.
# Trae la rama, el endpoint, la base y el rol por defecto (taigadb / taigadb_owner).
resource "neon_project" "taiga" {
  # PostgreSQL 15 como en docker-compose: en 18 falla la migración history.0011 de Taiga.
  # Cambiar la versión o la región obliga a recrear el proyecto (y perder los datos).
  pg_version = 15
  region_id  = "aws-us-east-2"
  org_id     = var.org_id

  # Ventana de restauración (PITR). Sin este valor el provider pide 1 día y el plan
  # gratuito permite como máximo 6 h: la API rechaza el cambio con un 400.
  history_retention_seconds = 0

  lifecycle {
    # Un plan que quiera borrar el proyecto (y la base) falla en vez de aplicarse.
    prevent_destroy = true
  }
}
