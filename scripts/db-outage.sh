#!/usr/bin/env bash
# Simula una caída de la base de datos (Neon) para la demo de observabilidad.
#
#   NEON_API_KEY=... ./scripts/db-outage.sh on      # corta la base
#   NEON_API_KEY=... ./scripts/db-outage.sh off     # la restaura
#   NEON_API_KEY=... ./scripts/db-outage.sh status  # muestra el estado
#
# "on" deshabilita el endpoint de cómputo (Neon rechaza conexiones nuevas) y lo
# suspende para cerrar las que ya están abiertas. taiga-back sigue corriendo y
# empieza a fallar al consultar la base, que es lo que debe verse en la telemetría.
#
# Restaurar ("off") antes del próximo terraform apply.
set -euo pipefail

PROJECT_ID="restless-star-54395891"
ENDPOINT_ID="ep-hidden-art-bdclstku"
API="https://console.neon.tech/api/v2/projects/$PROJECT_ID/endpoints/$ENDPOINT_ID"

if [[ -z "${NEON_API_KEY:-}" ]]; then
  echo "Falta NEON_API_KEY" >&2
  exit 1
fi

neon() {
  curl -sS --fail-with-body -H "Authorization: Bearer $NEON_API_KEY" \
    -H "Content-Type: application/json" "$@"
}

set_disabled() {
  neon -X PATCH -d "{\"endpoint\":{\"disabled\":$1}}" "$API" > /dev/null
}

status() {
  neon "$API" | grep -o '"disabled":[a-z]*\|"current_state":"[a-z]*"' | tr '\n' ' '
  echo
}

case "${1:-}" in
  on)
    set_disabled true
    # Si ya estaba suspendido, Neon responde con error: no importa.
    neon -X POST "$API/suspend" > /dev/null 2>&1 || true
    echo "Base de datos cortada."
    status
    ;;
  off)
    set_disabled false
    echo "Base de datos restaurada."
    status
    ;;
  status)
    status
    ;;
  *)
    echo "Uso: $0 on|off|status" >&2
    exit 1
    ;;
esac
