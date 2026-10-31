#!/bin/sh
set -eu

cd /taiga-back

# migrate, loaddata y collectstatic, con telemetría (ver docker/startup.py)
echo "[Taiga] Running startup tasks..."
python docker/startup.py

echo "[Taiga] Fixing permissions on persistent directories..."
chown -R taiga:taiga /taiga-back/static /taiga-back/media

echo "[Taiga] Starting Gunicorn..."

exec su-exec taiga gunicorn taiga.wsgi:application \
    --config /taiga-back/docker/gunicorn.conf.py \
    --name taiga_api \
    --bind 0.0.0.0:8000 \
    --workers "${GUNICORN_WORKERS:-3}" \
    --worker-tmp-dir /dev/shm \
    --timeout "${GUNICORN_TIMEOUT:-60}" \
    --log-level info \
    --access-logfile - \
    "$@"
