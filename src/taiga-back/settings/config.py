# -*- coding: utf-8 -*-
"""Environment-driven Docker configuration for Taiga 6.10.2."""

import os

from .common import *  # noqa: F401,F403


def env_bool(name, default=False):
    return os.getenv(name, str(default)).lower() in {"1", "true", "yes", "on"}


# ---------------------------------------------------------------------------
# Generic
# ---------------------------------------------------------------------------

DEBUG = env_bool("DEBUG", False)

SECRET_KEY = os.getenv("TAIGA_SECRET_KEY")
if not SECRET_KEY:
    raise RuntimeError("TAIGA_SECRET_KEY must be defined")

TAIGA_SITES_SCHEME = os.getenv("TAIGA_SITES_SCHEME", "http")
TAIGA_SITES_DOMAIN = os.getenv("TAIGA_SITES_DOMAIN", "localhost:9000")
FORCE_SCRIPT_NAME = os.getenv("TAIGA_SUBPATH", "")

TAIGA_URL = f"{TAIGA_SITES_SCHEME}://{TAIGA_SITES_DOMAIN}{FORCE_SCRIPT_NAME}"

SITES = {
    "api": {
        "name": "api",
        "scheme": TAIGA_SITES_SCHEME,
        "domain": TAIGA_SITES_DOMAIN,
    },
    "front": {
        "name": "front",
        "scheme": TAIGA_SITES_SCHEME,
        "domain": f"{TAIGA_SITES_DOMAIN}{FORCE_SCRIPT_NAME}",
    },
}

DEFAULT_PROJECT_SLUG_PREFIX = env_bool("DEFAULT_PROJECT_SLUG_PREFIX", False)
LANGUAGE_CODE = os.getenv("LANGUAGE_CODE", "en-us")

# ---------------------------------------------------------------------------
# PostgreSQL
# ---------------------------------------------------------------------------

DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.postgresql",
        "NAME": os.getenv("POSTGRES_DB", "taiga"),
        "USER": os.getenv("POSTGRES_USER", "taiga"),
        "PASSWORD": os.getenv("POSTGRES_PASSWORD", "taiga"),
        "HOST": os.getenv("POSTGRES_HOST", "taiga-db"),
        "PORT": os.getenv("POSTGRES_PORT", "5432"),
        "OPTIONS": {
            "sslmode": os.getenv("POSTGRES_SSLMODE", "disable"),
        },
        "DISABLE_SERVER_SIDE_CURSORS": env_bool(
            "POSTGRES_DISABLE_SERVER_SIDE_CURSORS", False
        ),
    }
}

# ---------------------------------------------------------------------------
# Media and static files
# ---------------------------------------------------------------------------

MEDIA_ROOT = os.getenv("MEDIA_ROOT", os.path.join(BASE_DIR, "media"))
MEDIA_URL = f"{TAIGA_URL}/media/"

STATIC_ROOT = os.getenv("STATIC_ROOT", os.path.join(BASE_DIR, "static"))
STATIC_URL = f"{TAIGA_URL}/static/"

# easy-thumbnails falls back to the default storage, so thumbnails are protected too.
STORAGES["default"]["BACKEND"] = "taiga_contrib_protected.storage.ProtectedFileSystemStorage"

# ---------------------------------------------------------------------------
# Email
# ---------------------------------------------------------------------------

EMAIL_BACKEND = os.getenv(
    "EMAIL_BACKEND", "django.core.mail.backends.console.EmailBackend"
)
DEFAULT_FROM_EMAIL = os.getenv("DEFAULT_FROM_EMAIL", "system@taiga.local")
EMAIL_USE_TLS = env_bool("EMAIL_USE_TLS", False)
EMAIL_USE_SSL = env_bool("EMAIL_USE_SSL", False)
EMAIL_HOST = os.getenv("EMAIL_HOST", "localhost")
EMAIL_PORT = int(os.getenv("EMAIL_PORT", "587"))
EMAIL_HOST_USER = os.getenv("EMAIL_HOST_USER", "")
EMAIL_HOST_PASSWORD = os.getenv("EMAIL_HOST_PASSWORD", "")

# ---------------------------------------------------------------------------
# RabbitMQ / real-time events
# ---------------------------------------------------------------------------

RABBITMQ_USER = os.getenv("RABBITMQ_USER", "taiga")
RABBITMQ_PASS = os.getenv("RABBITMQ_PASS", "taiga")

EVENTS_PUSH_BACKEND = "taiga.events.backends.rabbitmq.EventsPushBackend"
EVENTS_PUSH_BACKEND_URL = os.getenv(
    "EVENTS_PUSH_BACKEND_URL",
    f"amqp://{RABBITMQ_USER}:{RABBITMQ_PASS}@"
    f"{os.getenv('TAIGA_EVENTS_RABBITMQ_HOST', 'taiga-events-rabbitmq')}:5672/taiga",
)
EVENTS_PUSH_BACKEND_OPTIONS = {"url": EVENTS_PUSH_BACKEND_URL}

# ---------------------------------------------------------------------------
# Celery / asynchronous tasks
# ---------------------------------------------------------------------------

CELERY_ENABLED = env_bool("CELERY_ENABLED", True)
CELERY_BROKER_URL = os.getenv(
    "CELERY_BROKER_URL",
    f"amqp://{RABBITMQ_USER}:{RABBITMQ_PASS}@"
    f"{os.getenv('TAIGA_ASYNC_RABBITMQ_HOST', 'taiga-async-rabbitmq')}:5672/taiga",
)
CELERY_RESULT_BACKEND = None
CELERY_ACCEPT_CONTENT = ["pickle"]
CELERY_TASK_SERIALIZER = "pickle"
CELERY_RESULT_SERIALIZER = "pickle"
CELERY_TIMEZONE = os.getenv("CELERY_TIMEZONE", "Europe/Madrid")

# ---------------------------------------------------------------------------
# Registration / telemetry
# ---------------------------------------------------------------------------

PUBLIC_REGISTER_ENABLED = env_bool("PUBLIC_REGISTER_ENABLED", True)
ENABLE_TELEMETRY = env_bool("ENABLE_TELEMETRY", False)

# The default project already has the contrib package installed in the image.
# The plugin itself is enabled through STORAGES above.
