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