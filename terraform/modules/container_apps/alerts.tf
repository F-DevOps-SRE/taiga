# Alertas de Taiga.
#
#   alert-taiga-startup-failed   taiga-back no pudo arrancar (migrate/loaddata/collectstatic)
#   alert-taiga-restarts         algún contenedor de ca-taiga, ca-postgres o ca-rabbitmq se reinició
#   alert-taiga-slo-fast-burn    error budget de 30 días consumiéndose 14.4x (se acaba en ~2 días)
#   alert-taiga-slo-slow-burn    error budget consumiéndose 6x (se acaba en ~5 días)
#   alert-taiga-events-crash     taiga-events terminó por una excepción no controlada
#   alert-taiga-availability     el test de disponibilidad falla (solo si availability_test_enabled)
#
# Notifican por correo si se define alert_email; si no, solo quedan en
# Azure Monitor > Alerts.

locals {
  # Mismo SLO que el dashboard de Grafana: 99.5 % de peticiones sin 5xx.
  slo_availability = 0.995
  error_budget     = 1 - local.slo_availability

  action_group_ids = azurerm_monitor_action_group.alerts[*].id

  # Error ratio de la API (taiga-back) en la ventana de la alerta. Con menos de
  # 20 peticiones no se evalúa: con tráfico de demo, 1 error sería un 50 %.
  api_error_ratio_query = <<-KQL
    requests
    | where cloud_RoleName == "taiga-back"
    | summarize total = sum(itemCount), failed = sumif(itemCount, toint(resultCode) >= 500)
    | where total >= 20
    | extend error_ratio = todouble(failed) / total
  KQL
}

resource "azurerm_monitor_action_group" "alerts" {
  count               = var.alert_email == "" ? 0 : 1
  name                = "ag-taiga"
  resource_group_name = var.resource_group_name
  short_name          = "taiga"

  email_receiver {
    name                    = "equipo"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }
}

# --- Arranque fallido de taiga-back (lo registra docker/startup.py) ---
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "startup_failed" {
  name                 = "alert-taiga-startup-failed"
  description          = "taiga-back falló en migrate, loaddata o collectstatic. customDimensions dice el paso y la migración."
  resource_group_name  = var.resource_group_name
  location             = var.location
  scopes               = [azurerm_application_insights.appi.id]
  severity             = 1
  evaluation_frequency = "PT5M"
  window_duration      = "PT15M"

  criteria {
    query                   = <<-KQL
      union exceptions, traces
      | where tostring(customDimensions.taiga_phase) == "startup" and severityLevel >= 3
    KQL
    time_aggregation_method = "Count"
    operator                = "GreaterThan"
    threshold               = 0
  }

  action {
    action_groups = local.action_group_ids
  }
}

# --- Reinicios de contenedores ---
# RestartCount es acumulado por réplica: > 0 mientras viva una réplica que se reinició.
resource "azurerm_monitor_metric_alert" "restarts" {
  name                = "alert-taiga-restarts"
  description         = "Un contenedor se reinició (crash, OOM o probe fallido). Ver ContainerAppSystemLogs_CL."
  resource_group_name = var.resource_group_name
  scopes = [
    azurerm_container_app.taiga.id,
    azurerm_container_app.postgres.id,
    azurerm_container_app.rabbitmq.id,
  ]
  target_resource_type     = "Microsoft.App/containerApps"
  target_resource_location = var.location
  severity                 = 2
  frequency                = "PT5M"
  window_size              = "PT15M"

  criteria {
    metric_namespace = "Microsoft.App/containerApps"
    metric_name      = "RestartCount"
    aggregation      = "Maximum"
    operator         = "GreaterThan"
    threshold        = 0
  }

  dynamic "action" {
    for_each = local.action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

# --- Burn rate del SLO de disponibilidad (multiwindow, como en el libro de SRE de Google) ---
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "slo_fast_burn" {
  name                 = "alert-taiga-slo-fast-burn"
  description          = "Burn rate > 14.4 en 1 h: a este ritmo el error budget de 30 días se acaba en ~2 días."
  resource_group_name  = var.resource_group_name
  location             = var.location
  scopes               = [azurerm_application_insights.appi.id]
  severity             = 1
  evaluation_frequency = "PT5M"
  window_duration      = "PT1H"

  criteria {
    query                   = local.api_error_ratio_query
    metric_measure_column   = "error_ratio"
    time_aggregation_method = "Maximum"
    operator                = "GreaterThan"
    threshold               = 14.4 * local.error_budget
  }

  action {
    action_groups = local.action_group_ids
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "slo_slow_burn" {
  name                 = "alert-taiga-slo-slow-burn"
  description          = "Burn rate > 6 en 6 h: a este ritmo el error budget de 30 días se acaba en ~5 días."
  resource_group_name  = var.resource_group_name
  location             = var.location
  scopes               = [azurerm_application_insights.appi.id]
  severity             = 2
  evaluation_frequency = "PT30M"
  window_duration      = "PT6H"

  criteria {
    query                   = local.api_error_ratio_query
    metric_measure_column   = "error_ratio"
    time_aggregation_method = "Maximum"
    operator                = "GreaterThan"
    threshold               = 6 * local.error_budget
  }

  action {
    action_groups = local.action_group_ids
  }
}

# --- Caída de taiga-events (lo registra src/telemetry.js) ---
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "events_crash" {
  name                 = "alert-taiga-events-crash"
  description          = "taiga-events terminó por una excepción no controlada (p. ej. se cortó la conexión con RabbitMQ)."
  resource_group_name  = var.resource_group_name
  location             = var.location
  scopes               = [azurerm_application_insights.appi.id]
  severity             = 2
  evaluation_frequency = "PT5M"
  window_duration      = "PT15M"

  criteria {
    query                   = <<-KQL
      exceptions
      | where cloud_RoleName == "taiga-events"
    KQL
    time_aggregation_method = "Count"
    operator                = "GreaterThan"
    threshold               = 0
  }

  action {
    action_groups = local.action_group_ids
  }
}

# --- Test de disponibilidad (bajo demanda) ---
# Despierta ca-taiga cada 5 min: con min_replicas = 0 eso cuesta cómputo y, sin
# réplica caliente, cada prueba pagaría un arranque en frío. Se activa para las
# demos con availability_test_enabled = true.
resource "azurerm_application_insights_standard_web_test" "api" {
  count                   = var.availability_test_enabled ? 1 : 0
  name                    = "webtest-taiga-api"
  description             = "GET /api/v1/ a través del gateway: valida ingress, nginx y taiga-back."
  resource_group_name     = var.resource_group_name
  location                = var.location
  application_insights_id = azurerm_application_insights.appi.id
  geo_locations           = ["us-va-ash-azr", "us-tx-sn1-azr", "us-il-ch1-azr"]
  frequency               = 300
  timeout                 = 120
  retry_enabled           = true

  request {
    url = "${local.taiga_url}/api/v1/"
  }

  validation_rules {
    expected_status_code = 200
    ssl_check_enabled    = true
  }

  # Azure agrega solo el tag hidden-link hacia Application Insights.
  lifecycle {
    ignore_changes = [tags]
  }
}

resource "azurerm_monitor_metric_alert" "availability" {
  count               = var.availability_test_enabled ? 1 : 0
  name                = "alert-taiga-availability"
  description         = "El test de disponibilidad de /api/v1/ falla desde 2 o más ubicaciones."
  resource_group_name = var.resource_group_name
  scopes = [
    azurerm_application_insights_standard_web_test.api[0].id,
    azurerm_application_insights.appi.id,
  ]
  severity    = 1
  frequency   = "PT1M"
  window_size = "PT5M"

  application_insights_web_test_location_availability_criteria {
    web_test_id           = azurerm_application_insights_standard_web_test.api[0].id
    component_id          = azurerm_application_insights.appi.id
    failed_location_count = 2
  }

  dynamic "action" {
    for_each = local.action_group_ids
    content {
      action_group_id = action.value
    }
  }
}
