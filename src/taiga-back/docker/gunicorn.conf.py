# Configuración de Gunicorn propia del equipo (no es código de Taiga).
#
# OpenTelemetry se inicializa en cada worker (post_fork) y no en el proceso
# maestro: los exportadores usan hilos que no sobreviven a un fork. El hook corre
# antes de que el worker importe taiga.wsgi, así que Django y psycopg2 quedan
# instrumentados desde la primera petición.
#
# Sin APPLICATIONINSIGHTS_CONNECTION_STRING (por ejemplo en docker-compose)
# no se activa nada.
import os


def post_fork(server, worker):
    if not os.environ.get("APPLICATIONINSIGHTS_CONNECTION_STRING"):
        return

    from azure.monitor.opentelemetry import configure_azure_monitor

    configure_azure_monitor()
    server.log.info("OpenTelemetry -> Application Insights activo (pid %s)", worker.pid)
