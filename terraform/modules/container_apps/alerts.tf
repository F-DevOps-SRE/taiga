# Alertas de Taiga.
#
#   alert-taiga-startup-failed        taiga-back no pudo arrancar (migrate/loaddata/collectstatic)  [demo]
#   alert-taiga-restarts-<app>        algún contenedor de ca-taiga o ca-rabbitmq se reinició
#   alert-taiga-slo-<sli>-fast-burn   burn rate > 14.4 en 1 h y en 5 min (el error budget se acaba en ~2 días)  [demo]
#   alert-taiga-slo-<sli>-slow-burn   burn rate > 6 en 6 h y en 30 min (se acaba en ~5 días)  [demo]
#   alert-taiga-events-crash          taiga-events terminó por una excepción no controlada  [demo]
#   alert-taiga-availability          el test de disponibilidad falla  [demo]
#
# <sli> es login, api o latency (los tres SLIs del informe de la entrega 3).
#
# [demo]: solo existen con availability_test_enabled = true. Son las que cuestan
# (alertas de logs ~$12.60/mes y el test de disponibilidad); las de reinicios son
# alertas de métricas dentro de la capa gratuita y quedan siempre.
#
# Notifican por correo si se define alert_email; si no, solo quedan en
# Azure Monitor > Alerts.

locals {
  action_group_ids = azurerm_monitor_action_group.alerts[*].id

  # Los mismos SLIs y SLOs que el dashboard de Grafana y el informe.
  # valid: peticiones que cuentan para el SLI; bad: las que consumen presupuesto.
  slis = {
    login = {
      title = "SLI 1 (login, /api/v1/auth)"
      slo   = 0.999
      valid = "path startswith \"/api/v1/auth\" and not(code between (400 .. 499))"
      bad   = "code >= 500"
    }
    api = {
      title = "SLI 2 (API de consultas)"
      slo   = 0.995
      valid = "name startswith \"GET\" and path matches regex @\"^/api/v1/(userstories|tasks|issues|epics)/?$\" and url has_any (\"assigned_to\", \"assigned_users\") and (not(code between (400 .. 499)) or code == 429)"
      bad   = "code >= 500 or code == 429"
    }
    latency = {
      title = "SLI 3 (latencia <= 300 ms)"
      slo   = 0.95
      valid = "path startswith \"/api/v1/\" and code < 400"
      bad   = "duration > 300"
    }
  }

  # Multiventana, como en el SRE Workbook: la ventana larga evita falsas alarmas y
  # la corta hace que la alerta se apague apenas se resuelve el problema.
  burn_windows = {
    fast = { factor = 14.4, long = "1h", short = "5m", window = "PT1H", frequency = "PT5M", days = "~2 días" }
    slow = { factor = 6, long = "6h", short = "30m", window = "PT6H", frequency = "PT15M", days = "~5 días" }
  }

  slo_alerts = {
    for pair in setproduct(keys(local.slis), keys(local.burn_windows)) :
    "${pair[0]}-${pair[1]}" => { sli = pair[0], burn = pair[1] }
  }
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
  count                = var.availability_test_enabled ? 1 : 0
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
# Una alerta por app: Azure no admite alertas de métricas sobre varias Container Apps.
resource "azurerm_monitor_metric_alert" "restarts" {
  for_each = {
    taiga    = azurerm_container_app.taiga.id
    rabbitmq = azurerm_container_app.rabbitmq.id
  }
  name                = "alert-taiga-restarts-${each.key}"
  description         = "Un contenedor de ca-${each.key} se reinició (crash, OOM o probe fallido). Ver ContainerAppSystemLogs_CL."
  resource_group_name = var.resource_group_name
  scopes              = [each.value]
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"

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

# --- Burn rate de los SLOs (multiventana) ---
# Con menos de 20 peticiones en la ventana larga no se evalúa: con tráfico de
# demo, 1 error sería un 50 %.
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "slo_burn" {
  for_each = var.availability_test_enabled ? local.slo_alerts : {}

  name                 = "alert-taiga-slo-${each.value.sli}-${each.value.burn}-burn"
  description          = "${local.slis[each.value.sli].title}: burn rate > ${local.burn_windows[each.value.burn].factor} en ${local.burn_windows[each.value.burn].long} y en ${local.burn_windows[each.value.burn].short}. A este ritmo el error budget de 30 días se acaba en ${local.burn_windows[each.value.burn].days}."
  resource_group_name  = var.resource_group_name
  location             = var.location
  scopes               = [azurerm_application_insights.appi.id]
  severity             = 1
  evaluation_frequency = local.burn_windows[each.value.burn].frequency
  window_duration      = local.burn_windows[each.value.burn].window

  criteria {
    query                   = <<-KQL
      requests
      | where timestamp > ago(${local.burn_windows[each.value.burn].long}) and cloud_RoleName == "taiga-back"
      | extend path = tostring(parse_url(url).Path), code = toint(resultCode)
      | where ${local.slis[each.value.sli].valid}
      | extend is_bad = ${local.slis[each.value.sli].bad}, is_short = timestamp > ago(${local.burn_windows[each.value.burn].short})
      | summarize total_long = sum(itemCount), bad_long = sumif(itemCount, is_bad),
                  total_short = sumif(itemCount, is_short), bad_short = sumif(itemCount, is_bad and is_short)
      | where total_long >= 20 and total_short > 0
      | extend burn_rate = min_of(todouble(bad_long) / total_long, todouble(bad_short) / total_short) / ${1 - local.slis[each.value.sli].slo}
    KQL
    metric_measure_column   = "burn_rate"
    time_aggregation_method = "Maximum"
    operator                = "GreaterThan"
    threshold               = local.burn_windows[each.value.burn].factor
  }

  action {
    action_groups = local.action_group_ids
  }
}

# --- Caída de taiga-events (lo registra src/telemetry.js) ---
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "events_crash" {
  count                = var.availability_test_enabled ? 1 : 0
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

# Antes no tenían count: evita que Terraform las borre y recree al pasar a [0].
moved {
  from = azurerm_monitor_scheduled_query_rules_alert_v2.startup_failed
  to   = azurerm_monitor_scheduled_query_rules_alert_v2.startup_failed[0]
}

moved {
  from = azurerm_monitor_scheduled_query_rules_alert_v2.events_crash
  to   = azurerm_monitor_scheduled_query_rules_alert_v2.events_crash[0]
}
