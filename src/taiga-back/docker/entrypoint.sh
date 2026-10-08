#!/usr/bin/env bash
set -euo pipefail

cd /taiga-back

echo "[Taiga] Applying database migrations..."
python manage.py migrate --noinput

echo "[Taiga] Loading initial project templates..."
python manage.py loaddata initial_project_templates --verbosity 0

echo "[Taiga] Collecting static files..."
python manage.py collectstatic --noinput --clear

echo "[Taiga] Fixing permissions on persistent directories..."
chown -R taiga:taiga /taiga-back/static /taiga-back/media

echo "[Taiga] Starting Gunicorn..."

exec gosu taiga gunicorn taiga.wsgi:application \
    --name taiga_api \
    --bind 0.0.0.0:8000 \
    --workers "${GUNICORN_WORKERS:-3}" \
    --worker-tmp-dir /dev/shm \
    --timeout "${GUNICORN_TIMEOUT:-60}" \
    --log-level info \
    --access-logfile - \
    "$@"
