variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "storage_account_name" {
  type = string
}

variable "storage_account_key" {
  type      = string
  sensitive = true
}

variable "postgres_password" {
  type      = string
  sensitive = true
}

variable "rabbitmq_password" {
  type      = string
  sensitive = true
}

variable "taiga_secret_key" {
  type      = string
  sensitive = true
}

# --- Usuarios / nombres de PostgreSQL y RabbitMQ ---
variable "postgres_db" {
  type    = string
  default = "taiga"
}

variable "postgres_user" {
  type    = string
  default = "taiga"
}

variable "rabbitmq_user" {
  type    = string
  default = "taiga"
}

variable "rabbitmq_vhost" {
  type    = string
  default = "taiga"
}

# --- Imágenes de Taiga (GHCR, paquetes públicos: no requiere credenciales) ---
variable "image_registry" {
  type        = string
  description = "Registro y namespace de las imágenes, ej. ghcr.io/f-devops-sre"
}

variable "taiga_back_commit" {
  type        = string
  description = "Commit (7+ caracteres) cuya imagen sha-<commit> de taiga-back se despliega"
}

variable "taiga_front_commit" {
  type        = string
  description = "Commit (7+ caracteres) cuya imagen sha-<commit> de taiga-front se despliega"
}

variable "taiga_events_commit" {
  type        = string
  description = "Commit (7+ caracteres) cuya imagen sha-<commit> de taiga-events se despliega"
}

variable "taiga_protected_commit" {
  type        = string
  description = "Commit (7+ caracteres) cuya imagen sha-<commit> de taiga-protected se despliega"
}

variable "gateway_nginx_conf" {
  type        = string
  description = "Contenido de taiga-gateway/nginx.conf (el mismo que usa docker-compose)"
}

variable "storage_share_name" {
  type        = string
  description = "Azure Files share montado en el environment"
}
