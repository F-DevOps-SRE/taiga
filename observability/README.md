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
| CPU, memoria, reinicios, réplicas, ingress | métricas de plataforma de Container Apps | `microsoft.app/containerapps` |

OpenTelemetry se activa en `src/taiga-back/docker/gunicorn.conf.py` (hook `post_fork`), sin tocar el código de Taiga.
Solo arranca si existe `APPLICATIONINSIGHTS_CONNECTION_STRING`, así que docker-compose sigue funcionando igual.
Terraform crea `appi-taiga` y le pasa la connection string a taiga-back como secreto.

## Dashboard

`grafana/taiga-golden-signals.json`:

1. **SLOs y error budget (30 días):** SLI de disponibilidad y de latencia, presupuesto restante (gauge y burndown), errores que aún caben, burn rate 1 h y 6 h.
2. **Golden signals de la API:** latencia p50/p95/p99, tráfico (req/s), errores 4xx/5xx, top de endpoints.
3. **Golden signals de PostgreSQL** (medidos desde el cliente): latencia, consultas/s, fallos.
4. **Saturación:** CPU y memoria (% del límite), reinicios y réplicas de `ca-taiga`, `ca-postgres` y `ca-rabbitmq`; peticiones del ingress por código de estado.

Los SLOs son variables del dashboard (por defecto 99.5 % sin 5xx y 95 % bajo 1000 ms).

### Importarlo

**Opción A: Grafana integrado en el portal (gratis)**

1. Portal de Azure → **Monitor** → **Dashboards with Grafana** → **New** → **Import**.
2. Subir `grafana/taiga-golden-signals.json`.
3. En la variable *Azure Monitor* elegir la fuente de datos que trae el portal (usa los permisos del usuario conectado: hace falta al menos *Reader* sobre `rg-taiga`).

**Opción B: Azure Managed Grafana**

1. Crear la instancia y darle a su identidad administrada el rol **Monitoring Reader** sobre `rg-taiga`.
2. **Dashboards** → **New** → **Import** → subir el JSON y elegir la fuente *Azure Monitor*.

## Limitaciones

- La saturación de PostgreSQL y RabbitMQ se ve solo como CPU y memoria del contenedor. Para conexiones, locks o profundidad de colas haría falta un OpenTelemetry Collector con los receivers `postgresql` y `rabbitmq` exportando a Application Insights.
- taiga-events (WebSockets) y taiga-protected no están instrumentados; su tráfico aparece en el panel del ingress.
- La ventana de 30 días coincide con la retención de `log-taiga` (`retention_in_days = 30`).
