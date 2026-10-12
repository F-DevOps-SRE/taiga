# Taiga Back 6.10.2 - academic Docker image
# Build context: ./src/taiga-back

FROM python:3.14-alpine AS builder

ENV PIP_DISABLE_PIP_VERSION_CHECK=1     PIP_NO_CACHE_DIR=1     PYTHONDONTWRITEBYTECODE=1

WORKDIR /build

RUN apk add --no-cache        build-base        git        libpq-dev

COPY requirements.txt ./

RUN python -m pip install --upgrade pip wheel     && pip wheel --wheel-dir /wheels -r requirements.txt

# Taiga's protected storage plugin is not part of requirements.txt.
# It is required by settings/config.py for protected media.
RUN pip wheel --wheel-dir /wheels     "git+https://github.com/taigaio/taiga-contrib-protected.git"


FROM python:3.14-alpine AS runtime

ENV PYTHONDONTWRITEBYTECODE=1     PYTHONUNBUFFERED=1     PYTHONFAULTHANDLER=1     PIP_DISABLE_PIP_VERSION_CHECK=1     DJANGO_SETTINGS_MODULE=settings.config

WORKDIR /taiga-back

# `apk upgrade` aplica los parches de seguridad del sistema base publicados
# después de la imagen oficial.
RUN apk upgrade --no-cache     && apk add --no-cache        libpq        libmagic        libstdc++        gettext        su-exec        curl

# pip no se usa en runtime: se desinstala para no arrastrar las vulnerabilidades
# de sus dependencias empaquetadas (si hace falta: `python -m ensurepip`).
COPY --from=builder /wheels /wheels
RUN pip install --no-cache-dir /wheels/*     && rm -rf /wheels     && pip uninstall -y pip

COPY . .
COPY docker/entrypoint.sh /usr/local/bin/taiga-entrypoint

RUN chmod +x /usr/local/bin/taiga-entrypoint     && addgroup -S taiga     && adduser -S -G taiga -h /taiga-back -s /sbin/nologin taiga     && mkdir -p /taiga-back/static /taiga-back/media     && chown -R taiga:taiga /taiga-back

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=5     CMD curl --fail http://localhost:8000/api/v1/ || exit 1

ENTRYPOINT ["/usr/local/bin/taiga-entrypoint"]
