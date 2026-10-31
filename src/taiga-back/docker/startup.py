# Arranque de taiga-back propio del equipo (no es código de Taiga).
#
# Corre las tareas previas a Gunicorn (migrate, loaddata, collectstatic) con
# telemetría. Antes eran comandos sueltos de manage.py en entrypoint.sh y, como
# OpenTelemetry solo arranca dentro de los workers de Gunicorn, un fallo aquí
# no llegaba a Application Insights: solo quedaba el traceback partido en líneas
# en ContainerAppConsoleLogs_CL, sin decir qué migración falló.
#
# Ahora:
#   - cada paso es un span (taiga.startup > startup.migrate, ...) con su duración
#   - un fallo se registra como excepción en Application Insights con
#     customDimensions.taiga_phase = "startup", el paso y la migración en curso
#   - en la consola cada evento es UNA línea JSON (traceback incluido)
# Sin APPLICATIONINSIGHTS_CONNECTION_STRING (docker-compose) solo hace lo último.
import json
import logging
import os
import re
import sys
import time

# El script vive en docker/: el proyecto (settings, taiga) está un nivel arriba.
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

ENABLED = bool(os.environ.get("APPLICATIONINSIGHTS_CONNECTION_STRING"))
EXTRA_FIELDS = ("taiga_phase", "taiga_step", "taiga_migration", "migrations_applied", "duration_ms")


class JsonFormatter(logging.Formatter):
    """Una línea JSON por registro: el traceback no se parte en filas sueltas."""

    def format(self, record):
        data = {
            "timestamp": self.formatTime(record, "%Y-%m-%dT%H:%M:%S%z"),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        for key in EXTRA_FIELDS:
            if hasattr(record, key):
                data[key] = getattr(record, key)
        if record.exc_info:
            data["exception"] = self.formatException(record.exc_info)
        return json.dumps(data, ensure_ascii=False)


class MigrationProgress:
    """Salida de `migrate`: se reenvía a stdout y se recuerda la migración en curso.

    Django escribe "  Applying app.0001_x..." y, al terminar, " OK". Si una
    migración falla, `current` queda con su nombre.
    """

    APPLYING = re.compile(r"Applying (\S+?)\.\.\.")

    def __init__(self):
        self.current = None
        self.applied = 0

    def write(self, text):
        sys.stdout.write(text)
        match = self.APPLYING.search(text)
        if match:
            self.current = match.group(1)
        elif self.current and text.strip() in ("OK", "FAKED"):
            self.applied += 1
            self.current = None
        return len(text)

    def flush(self):
        sys.stdout.flush()

    def isatty(self):
        return False


def configure_telemetry():
    if not ENABLED:
        return
    from azure.monitor.opentelemetry import configure_azure_monitor

    # Las migraciones lanzan miles de consultas: no se trazan una por una
    # (el error de PostgreSQL ya viaja en el mensaje de la excepción).
    configure_azure_monitor(
        enable_live_metrics=False,
        instrumentation_options={
            "django": {"enabled": False},
            "psycopg2": {"enabled": False},
            "requests": {"enabled": False},
            "urllib3": {"enabled": False},
        },
    )


def flush_telemetry():
    if not ENABLED:
        return
    from opentelemetry import trace
    from opentelemetry._logs import get_logger_provider

    for provider in (trace.get_tracer_provider(), get_logger_provider()):
        if hasattr(provider, "force_flush"):
            provider.force_flush(timeout_millis=15000)


def main():
    configure_telemetry()

    import django
    from django.core.management import call_command
    from opentelemetry import trace

    django.setup()

    # Se crea después de django.setup(): el LOGGING de Taiga usa
    # disable_existing_loggers y apagaría un logger creado antes. Propaga al
    # logger raíz, donde la distro puso el handler de Application Insights.
    log = logging.getLogger("startup")
    log.setLevel(logging.INFO)
    console = logging.StreamHandler(sys.stdout)
    console.setFormatter(JsonFormatter())
    log.addHandler(console)

    tracer = trace.get_tracer("taiga.startup")
    progress = MigrationProgress()
    steps = [
        ("migrate", lambda: call_command("migrate", interactive=False, stdout=progress)),
        ("loaddata", lambda: call_command("loaddata", "initial_project_templates", verbosity=0)),
        ("collectstatic", lambda: call_command("collectstatic", interactive=False, clear=True, verbosity=0)),
    ]

    started = time.monotonic()
    # record_exception=False: la excepción se registra una sola vez, con el log de abajo.
    with tracer.start_as_current_span("taiga.startup", record_exception=False) as root:
        for name, run in steps:
            step_started = time.monotonic()
            with tracer.start_as_current_span(f"startup.{name}", record_exception=False) as span:
                try:
                    run()
                except Exception as exc:
                    if name == "migrate" and progress.current:
                        sys.stdout.write("\n")  # cierra el "Applying ..." que quedó abierto
                    extra = {
                        "taiga_phase": "startup",
                        "taiga_step": name,
                        "duration_ms": round((time.monotonic() - step_started) * 1000),
                    }
                    if name == "migrate":
                        extra["taiga_migration"] = progress.current or "unknown"
                        extra["migrations_applied"] = progress.applied
                        span.set_attribute("taiga.migration", extra["taiga_migration"])
                    message = f"Startup step '{name}' failed"
                    if name == "migrate":
                        message += f" at migration {extra['taiga_migration']}"
                    log.exception("%s: %s", message, str(exc).strip(), extra=extra)
                    span.set_status(trace.Status(trace.StatusCode.ERROR, str(exc)))
                    root.set_status(trace.Status(trace.StatusCode.ERROR, message))
                    return 1

            log.info(
                "Startup step '%s' done",
                name,
                extra={
                    "taiga_phase": "startup",
                    "taiga_step": name,
                    "duration_ms": round((time.monotonic() - step_started) * 1000),
                    **({"migrations_applied": progress.applied} if name == "migrate" else {}),
                },
            )

    log.info(
        "Startup finished",
        extra={"taiga_phase": "startup", "duration_ms": round((time.monotonic() - started) * 1000)},
    )
    return 0


if __name__ == "__main__":
    code = 1
    try:
        code = main()
    finally:
        flush_telemetry()
    sys.exit(code)
