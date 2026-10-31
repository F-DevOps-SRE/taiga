# Observabilidad: OpenTelemetry + Application Insights + Grafana

```
taiga-back (Django + gunicorn) ──OpenTelemetry──► Application Insights (appi-taiga) ──┐
                                                    (datos en log-taiga)               ├──► Grafana (fuente Azure Monitor)
Container Apps: CPU, memoria, reinicios, réplicas, ingress ── Azure Monitor metrics ───┘
```

## Qué se recolecta

| Origen | Cómo | Tabla / métrica |
| --- | --- | --- |
| Peticiones HTTP de la API | `azure-monitor-opentelemetry` (instrumentación de Django) | `requests` |
| Consultas a PostgreSQL | instrumentación de psycopg2 | `dependencies` (`type == "postgresql"`) |
| Llamadas HTTP salientes | instrumentación de requests/urllib3 | `dependencies` |
| Logs de Python (`taiga`, `django.request`, `gunicorn.error`...) | handler de OpenTelemetry, nivel INFO+ (`OTEL_TAIGA_LOG_LEVEL`) | `traces` |
| Excepciones no controladas | instrumentación de Django | `exceptions` |
| CPU y memoria de cada worker | performance counters de la distro | `performanceCounters` |
| Live Metrics | distro | portal: Application Insights > Live metrics |
| CPU, memoria, reinicios, réplicas, ingress | métricas de plataforma de Container Apps | `microsoft.app/containerapps` |
| stdout/stderr de todos los contenedores | Container Apps → `log-taiga` | `ContainerAppConsoleLogs_CL` |
| Eventos de plataforma (reinicios, probes) | Container Apps → `log-taiga` | `ContainerAppSystemLogs_CL` |
| Arranque de taiga-back (migrate, loaddata, collectstatic) | `docker/startup.py`: span por paso y, si falla, excepción con el paso y la migración | `traces` / `exceptions` (`customDimensions.taiga_phase == "startup"`) |
| Logs y excepciones no controladas de taiga-events | `@azure/monitor-opentelemetry` cargado con `node --require src/telemetry.js` | `traces` / `exceptions` (`cloud_RoleName == "taiga-events"`) |
| Access log del gateway (todas las rutas: front, API, events, media) | `log_format taiga_json` en `taiga-gateway/nginx.conf` | `ContainerAppConsoleLogs_CL` (JSON en `Log_s`) |
| Logs de RabbitMQ (incluye aperturas y cierres de conexiones AMQP) | `log.console.formatter = json` | `ContainerAppConsoleLogs_CL` (JSON en `Log_s`) |
| Logs de PostgreSQL (consultas > 1 s, esperas por locks) | `log_line_prefix` con `[pid]` y `usuario@base` | `ContainerAppConsoleLogs_CL` |

Logs, excepciones y dependencias llevan el `operation_Id` de la petición: desde una traza se ven sus logs y viceversa.

OpenTelemetry se activa en `src/taiga-back/docker/gunicorn.conf.py` sin tocar el código de Taiga: `post_fork` inicializa la distro y `post_worker_init` engancha los loggers de Taiga que no propagan al raíz (y reactiva los que apaga `disable_existing_loggers`).
Solo arranca si existe `APPLICATIONINSIGHTS_CONNECTION_STRING`, así que docker-compose sigue funcionando igual.
Terraform crea `appi-taiga` y le pasa la connection string a taiga-back como secreto.

## Dashboard

`grafana/taiga-golden-signals.json`:

1. **SLOs y error budget (30 días):** SLI de disponibilidad y de latencia, presupuesto restante (gauge y burndown), errores que aún caben, burn rate 1 h y 6 h.
2. **Golden signals de la API:** latencia p50/p95/p99, tráfico (req/s), errores 4xx/5xx, top de endpoints.
3. **Golden signals de PostgreSQL** (medidos desde el cliente): latencia, consultas/s, fallos.
4. **Saturación:** CPU y memoria (% del límite), reinicios y réplicas de `ca-taiga`, `ca-postgres` y `ca-rabbitmq`; peticiones del ingress por código de estado; CPU y memoria de los workers de taiga-back.
5. **Trazas:** peticiones más lentas y fallidas, vista de la traza seleccionada y tabla de dependencias.
6. **Logs:** logs por severidad, excepciones, logs Warning+ y errores en la consola de todos los contenedores.

Clic en un `operation_Id` (o escribirlo en la variable `operation_id`) filtra la traza, sus logs y sus excepciones.

7. **Arranque y servicios sin SDK propio:** arranques de taiga-back (paso, migración y error), peticiones y latencia p95 por servicio desde el gateway, errores de taiga-events y RabbitMQ.

Los SLOs son variables del dashboard (por defecto 99.5 % sin 5xx y 95 % bajo 1000 ms).

### Importarlo

**Opción A: Grafana integrado en el portal (gratis)**

1. Portal de Azure → **Monitor** → **Dashboards with Grafana** → **New** → **Import**.
2. Subir `grafana/taiga-golden-signals.json`.
3. En la variable *Azure Monitor* elegir la fuente de datos que trae el portal (usa los permisos del usuario conectado: hace falta al menos *Reader* sobre `rg-taiga`).

**Opción B: Azure Managed Grafana**

1. Crear la instancia y darle a su identidad administrada el rol **Monitoring Reader** sobre `rg-taiga`.
2. **Dashboards** → **New** → **Import** → subir el JSON y elegir la fuente *Azure Monitor*.

## Probes

Todos los contenedores tienen readiness y liveness (TCP, salvo taiga-events que usa `/healthz`); taiga-back, Postgres y RabbitMQ además tienen startup probe. El de taiga-back da hasta 10 min, porque Gunicorn abre el puerto 8000 solo después de las migraciones. Los probes son TCP para no llenar la tabla `requests` ni afectar el SLO. Los fallos quedan en `ContainerAppSystemLogs_CL`.

## Alertas

Definidas en `terraform/modules/container_apps/alerts.tf`:

| Alerta | Dispara cuando |
| --- | --- |
| `alert-taiga-startup-failed` (sev 1) | taiga-back falla en migrate, loaddata o collectstatic |
| `alert-taiga-restarts` (sev 2) | algún contenedor de `ca-taiga`, `ca-postgres` o `ca-rabbitmq` se reinicia |
| `alert-taiga-slo-fast-burn` (sev 1) | burn rate > 14.4 en 1 h (el error budget de 30 días se acaba en ~2 días) |
| `alert-taiga-slo-slow-burn` (sev 2) | burn rate > 6 en 6 h (se acaba en ~5 días) |
| `alert-taiga-events-crash` (sev 2) | taiga-events termina por una excepción no controlada |
| `alert-taiga-availability` (sev 1) | el test de disponibilidad de `/api/v1/` falla desde 2 o más ubicaciones |

- **Correo:** secreto de GitHub `ALERT_EMAIL`. Sin él no se crea el action group y las alertas solo se ven en *Azure Monitor > Alerts*.
- **Test de disponibilidad (bajo demanda):** variable de repositorio `AVAILABILITY_TEST_ENABLED = true` y volver a correr el workflow de Terraform. Consulta `/api/v1/` cada 5 min desde 3 ubicaciones, por lo que mantiene `ca-taiga` despierto: activarlo solo para las demos.

## Limitaciones

- La saturación de PostgreSQL y RabbitMQ se ve solo como CPU y memoria del contenedor. Para conexiones, locks o profundidad de colas haría falta un OpenTelemetry Collector con los receivers `postgresql` y `rabbitmq` exportando a Application Insights.
- taiga-protected y taiga-front no tienen SDK: su tráfico, errores y latencia se ven desde el access log del gateway. En taiga-events no se trazan los mensajes de AMQP, solo logs y excepciones.
- La ventana de 30 días coincide con la retención de `log-taiga` (`retention_in_days = 30`).
