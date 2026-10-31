# Configuración de Gunicorn propia del equipo (no es código de Taiga).
#
# Envía las tres señales de OpenTelemetry a Application Insights:
#   - trazas:   peticiones Django, consultas psycopg2 y HTTP saliente
#   - métricas: estándar de requests/dependencies, performance counters
#               (CPU y memoria del proceso) y Live Metrics
#   - logs:     registros de Python, correlacionados con la traza de cada petición
#
# Sin APPLICATIONINSIGHTS_CONNECTION_STRING (por ejemplo en docker-compose)
# no se activa nada.
import logging
import os

ENABLED = bool(os.environ.get("APPLICATIONINSIGHTS_CONNECTION_STRING"))

# Loggers de Taiga y Gunicorn con "propagate": False: sus registros no llegan al
# logger raíz (donde la distro pone su handler), así que se les añade uno propio.
# Los hijos (taiga.projects..., etc.) propagan hasta "taiga".
NON_PROPAGATING_LOGGERS = ("taiga", "taiga.export_import", "django.request", "gunicorn.error")


def post_fork(server, worker):
    # Se inicializa en cada worker y no en el maestro: los exportadores usan hilos
    # que no sobreviven a un fork. Corre antes de que el worker importe taiga.wsgi,
    # así que Django y psycopg2 quedan instrumentados desde la primera petición.
    if not ENABLED:
        return

    from azure.monitor.opentelemetry import configure_azure_monitor

    configure_azure_monitor()
    server.log.info("OpenTelemetry -> Application Insights activo (pid %s)", worker.pid)


def post_worker_init(worker):
    # Corre después de cargar la app, es decir, después de que Django aplicó
    # LOGGING (settings/common.py); si se hiciera antes, dictConfig lo pisaría.
    if not ENABLED:
        return

    from opentelemetry._logs import get_logger_provider

    try:  # la misma clase que usa la distro para el logger raíz
        from opentelemetry.instrumentation.logging.handler import LoggingHandler
    except ImportError:
        from opentelemetry.sdk._logs import LoggingHandler

    # El logger "taiga" está en DEBUG; a Application Insights solo va INFO o más.
    level = os.environ.get("OTEL_TAIGA_LOG_LEVEL", "INFO").upper()
    handler = LoggingHandler(level=level, logger_provider=get_logger_provider())

    for name in NON_PROPAGATING_LOGGERS:
        logger = logging.getLogger(name)
        # "disable_existing_loggers": True de Taiga apaga los loggers que ya
        # existían al cargar Django (gunicorn.error entre ellos): se reactivan.
        logger.disabled = False
        if not any(isinstance(h, LoggingHandler) for h in logger.handlers):
            logger.addHandler(handler)

    worker.log.info("Logs de %s -> Application Insights (nivel %s)", ", ".join(NON_PROPAGATING_LOGGERS), level)
