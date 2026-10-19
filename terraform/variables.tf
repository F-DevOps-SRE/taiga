variable "subscription_id" {
  type    = string
  default = "ce1292bf-e44a-470d-895c-d6f02b239f37"
}

variable "resource_group_name" {
  type    = string
  default = "rg-taiga"
}

variable "postgres_password" {
  type      = string
  sensitive = true
}

variable "rabbitmq_pass" {
  type      = string
  sensitive = true
}

variable "taiga_secret_key" {
  type      = string
  sensitive = true
}

variable "image_registry" {
  type        = string
  default     = "ghcr.io/f-devops-sre"
  description = "Registro y namespace de las imágenes de Taiga (en minúsculas)"
}

# Commits de las imágenes a desplegar. El workflow de build publica cada imagen
# como sha-<commit[0:7]>; el workflow de Terraform resuelve estos valores solo.
variable "taiga_back_commit" {
  type = string
  validation {
    condition     = can(regex("^[0-9a-f]{7,40}$", var.taiga_back_commit))
    error_message = "Debe ser un SHA de commit (7 a 40 caracteres hex)."
  }
}

variable "taiga_front_commit" {
  type = string
  validation {
    condition     = can(regex("^[0-9a-f]{7,40}$", var.taiga_front_commit))
    error_message = "Debe ser un SHA de commit (7 a 40 caracteres hex)."
  }
}

variable "taiga_events_commit" {
  type = string
  validation {
    condition     = can(regex("^[0-9a-f]{7,40}$", var.taiga_events_commit))
    error_message = "Debe ser un SHA de commit (7 a 40 caracteres hex)."
  }
}

variable "taiga_protected_commit" {
  type = string
  validation {
    condition     = can(regex("^[0-9a-f]{7,40}$", var.taiga_protected_commit))
    error_message = "Debe ser un SHA de commit (7 a 40 caracteres hex)."
  }
}
