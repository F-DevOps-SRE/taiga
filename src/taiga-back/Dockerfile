# Taiga Back 6.10.2 - academic Docker image
# Build context: ./src/taiga-back

FROM python:3.11-slim AS builder

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /build

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       build-essential \
       git \
       libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt ./

RUN python -m pip install --upgrade pip wheel \
    && pip wheel --wheel-dir /wheels -r requirements.txt

# Taiga's protected storage plugin is not part of requirements.txt.
# It is required by settings/config.py for protected media.
RUN pip wheel --wheel-dir /wheels \
    "git+https://github.com/taigaio/taiga-contrib-protected.git"


FROM python:3.11-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONFAULTHANDLER=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    DJANGO_SETTINGS_MODULE=settings.config

WORKDIR /taiga-back

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       libpq5 \
       libmagic1 \
       gettext \
       gosu \
       curl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /wheels /wheels
RUN pip install --no-cache-dir /wheels/* \
    && rm -rf /wheels

COPY . .
COPY docker/entrypoint.sh /usr/local/bin/taiga-entrypoint

RUN chmod +x /usr/local/bin/taiga-entrypoint \
    && groupadd --system taiga \
    && useradd --system --gid taiga --home-dir /taiga-back --shell /usr/sbin/nologin taiga \
    && mkdir -p /taiga-back/static /taiga-back/media \
    && chown -R taiga:taiga /taiga-back

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=5 \
    CMD curl --fail http://localhost:8000/api/v1/ || exit 1

ENTRYPOINT ["/usr/local/bin/taiga-entrypoint"]
