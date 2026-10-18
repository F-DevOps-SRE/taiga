# 1. Log Analytics Workspace (Recomendado para el entorno)
resource "azurerm_log_analytics_workspace" "logs" {
  name                = "log-taiga"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# 2. Container Apps Environment (cae-taiga)
resource "azurerm_container_app_environment" "cae" {
  name                       = "cae-taiga"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  infrastructure_subnet_id   = var.subnet_id
  internal_load_balancer_enabled = false
  log_analytics_workspace_id = azurerm_log_analytics_workspace.logs.id
}

# 3. Montaje del Azure Files Share en el Environment
resource "azurerm_container_app_environment_storage" "storage_mount" {
  name                         = "taiga-storage-mount"
  container_app_environment_id = azurerm_container_app_environment.cae.id
  account_name                 = var.storage_account_name
  access_key                   = var.storage_account_key
  access_mode                  = "ReadWrite"
  share_name                   = "taiga-data"
}

# 4. Container App: Postgres (Base de Datos)
resource "azurerm_container_app" "postgres" {
  name                         = "ca-postgres"
  container_app_environment_id = azurerm_container_app_environment.cae.id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"

  template {
    min_replicas = 0
    max_replicas = 1

    container {
      name   = "postgres"
      image  = "postgres:15-alpine"
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name        = "POSTGRES_PASSWORD"
        secret_name = "postgres-password"
      }
    }
  }

  secret {
    name  = "postgres-password"
    value = var.postgres_password
  }

  ingress {
    external_enabled = false
    target_port      = 5432
    transport        = "tcp"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }
}

# 5. Container App: RabbitMQ (Cola de Mensajes)
resource "azurerm_container_app" "rabbitmq" {
  name                         = "ca-rabbitmq"
  container_app_environment_id = azurerm_container_app_environment.cae.id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"

  template {
    min_replicas = 0
    max_replicas = 1

    container {
      name   = "rabbitmq"
      image  = "rabbitmq:3.13-management-alpine"
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name        = "RABBITMQ_DEFAULT_PASS"
        secret_name = "rabbitmq-password"
      }
    }
  }

  secret {
    name  = "rabbitmq-password"
    value = var.rabbitmq_password
  }

  ingress {
    external_enabled = false
    target_port      = 5672
    transport        = "tcp"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }
}