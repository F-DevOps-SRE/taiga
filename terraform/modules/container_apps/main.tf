locals {
  # URL pública de Taiga. Se arma con el dominio del environment (y no con
  # ingress[0].fqdn) para poder usarla dentro de la misma Container App sin ciclo.
  taiga_app_name = "ca-taiga"
  taiga_fqdn     = "${local.taiga_app_name}.${azurerm_container_app_environment.cae.default_domain}"
  taiga_url      = "https://${local.taiga_fqdn}"

  # Imágenes publicadas por el workflow de build: ghcr.io/<owner>/<componente>:sha-<commit[0:7]>
  images = {
    back      = "${var.image_registry}/taiga-back:sha-${substr(var.taiga_back_commit, 0, 7)}"
    front     = "${var.image_registry}/taiga-front:sha-${substr(var.taiga_front_commit, 0, 7)}"
    events    = "${var.image_registry}/taiga-events:sha-${substr(var.taiga_events_commit, 0, 7)}"
    protected = "${var.image_registry}/taiga-protected:sha-${substr(var.taiga_protected_commit, 0, 7)}"
  }

  # Todos los contenedores de una Container App comparten red (localhost), así que
  # el nginx.conf de docker-compose se adapta:
  #   - los nombres de servicio (taiga-back, taiga-front...) pasan a 127.0.0.1
  #   - el gateway escucha en 8080 porque taiga-front (también nginx) ya usa el 80
  gateway_port = 8080
  gateway_conf = replace(
    replace(var.gateway_nginx_conf, "listen 80;", "listen ${local.gateway_port};"),
    "/http://taiga-(front|back|events|protected):/",
    "http://127.0.0.1:"
  )

  # Volumen Azure Files: un solo share con static/ y media/. Se monta en /taiga
  # (las rutas que ya espera nginx.conf) y el backend se apunta ahí con MEDIA_ROOT/STATIC_ROOT.
  data_volume_name = "taiga-data"
  data_mount_path  = "/taiga"

  postgres_host = azurerm_container_app.postgres.name
  rabbitmq_host = azurerm_container_app.rabbitmq.name
}

# 1. Log Analytics Workspace (Recomendado para el entorno)
resource "azurerm_log_analytics_workspace" "logs" {
  name                = "log-taiga"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# 1b. Application Insights (telemetría OpenTelemetry de taiga-back).
#     Basado en workspace: los datos quedan en log-taiga, con su misma retención.
resource "azurerm_application_insights" "appi" {
  name                = "appi-taiga"
  location            = var.location
  resource_group_name = var.resource_group_name
  workspace_id        = azurerm_log_analytics_workspace.logs.id
  application_type    = "other"
}

# 2. Container Apps Environment (cae-taiga)
resource "azurerm_container_app_environment" "cae" {
  name                           = "cae-taiga"
  location                       = var.location
  resource_group_name            = var.resource_group_name
  infrastructure_subnet_id       = var.subnet_id
  internal_load_balancer_enabled = false
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.logs.id

  # Azure crea y nombra solo el grupo de recursos de infraestructura
  # (ME_cae-taiga_rg-taiga_eastus). Como no está en la configuración, el provider
  # ve "valor -> null" y fuerza reemplazar el environment (y todas las apps) en cada plan.
  lifecycle {
    ignore_changes = [infrastructure_resource_group_name]
  }
}

# 3. Montaje del Azure Files Share en el Environment
resource "azurerm_container_app_environment_storage" "storage_mount" {
  name                         = "taiga-storage-mount"
  container_app_environment_id = azurerm_container_app_environment.cae.id
  account_name                 = var.storage_account_name
  access_key                   = var.storage_account_key
  access_mode                  = "ReadWrite"
  share_name                   = var.storage_share_name
}

# 4. Container App: Postgres (Base de Datos)
resource "azurerm_container_app" "postgres" {
  name                         = "ca-postgres"
  container_app_environment_id = azurerm_container_app_environment.cae.id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"

  template {
    # Siempre encendido: no tiene volumen, si escala a cero vuelve con la base
    # vacía (o la cola sin vhost) y taiga-back, ya migrado, falla con
    # "relation ... does not exist". Además una app TCP no despierta sola.
    min_replicas = 0
    max_replicas = 1

    container {
      name = "postgres"
      # La misma versión que docker-compose. En PostgreSQL 18 los NOT NULL pasan a
      # pg_constraint y la migración history.0011 de Taiga (que borra y recrea
      # todas las constraints de una tabla) falla con "is an identity column".
      image  = "postgres:15-alpine"
      cpu    = 0.25
      memory = "0.5Gi"

      # Logs con proceso, usuario, base y aplicación en cada línea (el STATEMENT
      # de un error sale en otra fila: se une por el [pid]), consultas > 1 s y
      # esperas por locks.
      args = [
        "postgres",
        "-c", "log_line_prefix=%m [%p] %q%u@%d app=%a ",
        "-c", "log_min_duration_statement=1000",
        "-c", "log_lock_waits=on",
      ]

      startup_probe {
        transport               = "TCP"
        port                    = 5432
        interval_seconds        = 10
        failure_count_threshold = 10
      }

      readiness_probe {
        transport        = "TCP"
        port             = 5432
        interval_seconds = 10
      }

      liveness_probe {
        transport        = "TCP"
        port             = 5432
        interval_seconds = 30
      }

      env {
        name  = "POSTGRES_DB"
        value = var.postgres_db
      }

      env {
        name  = "POSTGRES_USER"
        value = var.postgres_user
      }

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
    exposed_port     = 5432
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
    # Siempre encendido: no tiene volumen, si escala a cero vuelve con la base
    # vacía (o la cola sin vhost) y taiga-back, ya migrado, falla con
    # "relation ... does not exist". Además una app TCP no despierta sola.
    min_replicas = 0
    max_replicas = 1

    container {
      name   = "rabbitmq"
      image  = "rabbitmq:3.13-management-alpine"
      cpu    = 0.25
      memory = "0.5Gi"

      # Logs de consola en JSON: sin colores ANSI y un error por línea (antes los
      # errores de Erlang llegaban partidos y con el mensaje vacío). Incluyen las
      # aperturas y cierres de conexiones AMQP con su motivo.
      command = ["/bin/sh", "-c"]
      args = [
        "printf '%s\\n' 'log.console = true' 'log.console.level = info' 'log.console.formatter = json' > /etc/rabbitmq/conf.d/90-json-logs.conf && exec docker-entrypoint.sh rabbitmq-server"
      ]

      startup_probe {
        transport               = "TCP"
        port                    = 5672
        interval_seconds        = 10
        failure_count_threshold = 10
      }

      readiness_probe {
        transport        = "TCP"
        port             = 5672
        interval_seconds = 10
      }

      liveness_probe {
        transport        = "TCP"
        port             = 5672
        interval_seconds = 30
      }

      # El usuario por defecto "guest" solo acepta conexiones desde localhost,
      # por eso se define un usuario propio y el vhost que espera Taiga.
      env {
        name  = "RABBITMQ_DEFAULT_USER"
        value = var.rabbitmq_user
      }

      env {
        name        = "RABBITMQ_DEFAULT_PASS"
        secret_name = "rabbitmq-password"
      }

      env {
        name  = "RABBITMQ_DEFAULT_VHOST"
        value = var.rabbitmq_vhost
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
    exposed_port     = 5672
    transport        = "tcp"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }
}

# 6. Container App: Taiga (gateway nginx + 4 sidecars: back, front, events, protected)
#    Es el único punto de entrada público. Total de recursos: 2 vCPU / 4Gi.
resource "azurerm_container_app" "taiga" {
  name                         = local.taiga_app_name
  container_app_environment_id = azurerm_container_app_environment.cae.id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"

  template {
    # Una sola réplica: el backend corre migraciones al arrancar.
    min_replicas = 0
    max_replicas = 1

    volume {
      name         = local.data_volume_name
      storage_type = "AzureFile"
      storage_name = azurerm_container_app_environment_storage.storage_mount.name
    }

    # --- Gateway (nginx): recibe todo el tráfico y lo enruta a los sidecars ---
    container {
      name   = "taiga-gateway"
      image  = "nginx:1.30-alpine"
      cpu    = 0.25
      memory = "0.5Gi"

      # La configuración viaja en base64 por variable de entorno y se escribe al arrancar.
      command = ["/bin/sh", "-c"]
      args = [
        "echo \"$NGINX_CONF_B64\" | base64 -d > /etc/nginx/conf.d/default.conf && exec nginx -g 'daemon off;'"
      ]

      env {
        name  = "NGINX_CONF_B64"
        value = base64encode(local.gateway_conf)
      }

      readiness_probe {
        transport        = "TCP"
        port             = local.gateway_port
        interval_seconds = 10
      }

      liveness_probe {
        transport        = "TCP"
        port             = local.gateway_port
        interval_seconds = 30
      }

      volume_mounts {
        name = local.data_volume_name
        path = local.data_mount_path
      }
    }

    # --- taiga-back: API Django (8000) ---
    container {
      name   = "taiga-back"
      image  = local.images.back
      cpu    = 1.0
      memory = "2Gi"

      env {
        name        = "TAIGA_SECRET_KEY"
        secret_name = "taiga-secret-key"
      }
      env {
        name  = "TAIGA_SITES_SCHEME"
        value = "https"
      }
      env {
        name  = "TAIGA_SITES_DOMAIN"
        value = local.taiga_fqdn
      }
      env {
        name  = "POSTGRES_HOST"
        value = local.postgres_host
      }
      env {
        name  = "POSTGRES_PORT"
        value = "5432"
      }
      env {
        name  = "POSTGRES_DB"
        value = var.postgres_db
      }
      env {
        name  = "POSTGRES_USER"
        value = var.postgres_user
      }
      env {
        name        = "POSTGRES_PASSWORD"
        secret_name = "postgres-password"
      }
      env {
        name  = "RABBITMQ_USER"
        value = var.rabbitmq_user
      }
      env {
        name        = "RABBITMQ_PASS"
        secret_name = "rabbitmq-password"
      }
      env {
        name  = "TAIGA_EVENTS_RABBITMQ_HOST"
        value = local.rabbitmq_host
      }
      env {
        name  = "TAIGA_ASYNC_RABBITMQ_HOST"
        value = local.rabbitmq_host
      }
      # No hay worker de Celery en esta app: las tareas lentas corren dentro de la API.
      env {
        name  = "CELERY_ENABLED"
        value = "false"
      }
      env {
        name  = "PUBLIC_REGISTER_ENABLED"
        value = "true"
      }
      env {
        name  = "MEDIA_ROOT"
        value = "${local.data_mount_path}/media"
      }
      env {
        name  = "STATIC_ROOT"
        value = "${local.data_mount_path}/static"
      }
      env {
        name  = "GUNICORN_WORKERS"
        value = "2"
      }
      # OpenTelemetry -> Application Insights (lo activa docker/gunicorn.conf.py)
      env {
        name        = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        secret_name = "appinsights-connection-string"
      }
      env {
        name  = "OTEL_SERVICE_NAME"
        value = "taiga-back"
      }

      # Gunicorn abre el 8000 solo al terminar migrate, loaddata y collectstatic
      # (docker/startup.py). Sin volumen en Postgres, cada arranque migra desde
      # cero: se dan hasta 10 min (10 x 60 s) antes de reiniciar el contenedor.
      # Los probes son TCP y no HTTP para no llenar la tabla requests (y el SLO).
      startup_probe {
        transport               = "TCP"
        port                    = 8000
        interval_seconds        = 60
        failure_count_threshold = 10
      }

      readiness_probe {
        transport        = "TCP"
        port             = 8000
        interval_seconds = 10
      }

      liveness_probe {
        transport        = "TCP"
        port             = 8000
        interval_seconds = 30
      }

      volume_mounts {
        name = local.data_volume_name
        path = local.data_mount_path
      }
    }

    # --- taiga-front: archivos estáticos del sitio (nginx en el 80) ---
    container {
      name   = "taiga-front"
      image  = local.images.front
      cpu    = 0.25
      memory = "0.5Gi"

      # La imagen trae conf.json apuntando a localhost:9000 (docker-compose);
      # al arrancar se reemplaza por la URL pública de la Container App.
      command = ["/bin/sh", "-c"]
      args = [
        "sed -i -e 's#http://localhost:9000#${local.taiga_url}#g' -e 's#ws://localhost:9000#wss://${local.taiga_fqdn}#g' /usr/share/nginx/html/conf.json && exec nginx -g 'daemon off;'"
      ]

      readiness_probe {
        transport        = "TCP"
        port             = 80
        interval_seconds = 10
      }

      liveness_probe {
        transport        = "TCP"
        port             = 80
        interval_seconds = 30
      }
    }

    # --- taiga-events: WebSockets (8888) y health check (3023) ---
    container {
      name   = "taiga-events"
      image  = local.images.events
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name        = "RABBITMQ_URL"
        secret_name = "rabbitmq-events-url"
      }
      env {
        name        = "SECRET"
        secret_name = "taiga-secret-key"
      }
      env {
        name  = "WEB_SOCKET_SERVER_PORT"
        value = "8888"
      }
      env {
        name  = "APP_PORT"
        value = "3023"
      }
      env {
        name  = "ALGORITHM"
        value = "HS256"
      }
      env {
        name  = "USER_ID_CLAIM"
        value = "user_id"
      }
      env {
        name  = "LOG_LEVEL"
        value = "info"
      }
      # OpenTelemetry -> Application Insights (lo activa src/telemetry.js)
      env {
        name        = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        secret_name = "appinsights-connection-string"
      }
      env {
        name  = "OTEL_SERVICE_NAME"
        value = "taiga-events"
      }

      # /healthz revisa también RabbitMQ: no se usa como readiness, porque con
      # RabbitMQ en cero réplicas dejaría sin tráfico a toda la app (front y API).
      liveness_probe {
        transport = "HTTP"
        port      = 3023
        path      = "/healthz"
      }
    }

    # --- taiga-protected: valida tokens de adjuntos (8003) ---
    container {
      name   = "taiga-protected"
      image  = local.images.protected
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name        = "SECRET_KEY"
        secret_name = "taiga-secret-key"
      }
      env {
        name  = "MAX_AGE"
        value = "3600"
      }

      readiness_probe {
        transport        = "TCP"
        port             = 8003
        interval_seconds = 10
      }

      liveness_probe {
        transport        = "TCP"
        port             = 8003
        interval_seconds = 30
      }
    }
  }

  secret {
    name  = "taiga-secret-key"
    value = var.taiga_secret_key
  }

  secret {
    name  = "postgres-password"
    value = var.postgres_password
  }

  secret {
    name  = "rabbitmq-password"
    value = var.rabbitmq_password
  }

  secret {
    name  = "appinsights-connection-string"
    value = azurerm_application_insights.appi.connection_string
  }

  secret {
    name  = "rabbitmq-events-url"
    value = "amqp://${var.rabbitmq_user}:${urlencode(var.rabbitmq_password)}@${local.rabbitmq_host}:5672/${var.rabbitmq_vhost}"
  }

  ingress {
    external_enabled           = true
    target_port                = local.gateway_port
    transport                  = "auto"
    allow_insecure_connections = false

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }
}
