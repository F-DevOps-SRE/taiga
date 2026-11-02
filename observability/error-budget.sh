#!/usr/bin/env bash
# Política de error budget (informe de la entrega 3): calcula los tres presupuestos
# de 30 días en Application Insights y decide el estado del sistema.
#
#   NORMAL  los tres presupuestos con más del 50 % disponible
#   ALERTA  alguno con 50 % o menos: se permite desplegar, con revisión estricta
#   FREEZE  alguno agotado (0 % o menos): falla, lo que bloquea merge y despliegue
#
# El freeze se registra como un issue abierto con la etiqueta release-freeze y no
# se levanta hasta que el presupuesto más degradado recupere al menos un 20 %.
#
# Variables:
#   SUBSCRIPTION, RESOURCE_GROUP, APPI_NAME  dónde está Application Insights
#   HOTFIX=true        excepción de emergencia (no falla aunque haya freeze)
#   MANAGE_ISSUE=true  abre o cierra el issue de release-freeze (requiere GH_TOKEN)
set -euo pipefail

SUBSCRIPTION="${SUBSCRIPTION:?}"
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-taiga}"
APPI_NAME="${APPI_NAME:-appi-taiga}"
HOTFIX="${HOTFIX:-false}"
MANAGE_ISSUE="${MANAGE_ISSUE:-false}"
FREEZE_LABEL="release-freeze"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/stdout}"

# Mismos SLIs y SLOs que el dashboard (grafana/taiga-golden-signals.json) y las
# alertas (terraform/modules/container_apps/alerts.tf). Sin tráfico, 100 %.
read -r -d '' QUERY <<'KQL' || true
requests
| where timestamp > ago(30d) and cloud_RoleName == "taiga-back"
| extend path = tostring(parse_url(url).Path), code = toint(resultCode)
| extend v1 = path startswith "/api/v1/auth" and not(code between (400 .. 499))
| extend v2 = name startswith "GET" and path matches regex @"^/api/v1/(userstories|tasks|issues|epics)/?$" and url has_any ("assigned_to", "assigned_users") and (not(code between (400 .. 499)) or code == 429)
| extend v3 = path startswith "/api/v1/" and code < 400
| summarize t1 = sumif(itemCount, v1), b1 = sumif(itemCount, v1 and code >= 500),
            t2 = sumif(itemCount, v2), b2 = sumif(itemCount, v2 and (code >= 500 or code == 429)),
            t3 = sumif(itemCount, v3), b3 = sumif(itemCount, v3 and duration > 300)
| project login = iff(t1 == 0, 100.0, round(100.0 * (1.0 - (todouble(b1) / t1) / 0.001), 1)),
          api = iff(t2 == 0, 100.0, round(100.0 * (1.0 - (todouble(b2) / t2) / 0.005), 1)),
          latency = iff(t3 == 0, 100.0, round(100.0 * (1.0 - (todouble(b3) / t3) / 0.05), 1)),
          t1, t2, t3
KQL

row=$(az monitor app-insights query \
  --subscription "$SUBSCRIPTION" -g "$RESOURCE_GROUP" --app "$APPI_NAME" \
  --offset 30d --analytics-query "$QUERY" -o json | jq -c '.tables[0].rows[0]')

read -r login api latency t1 t2 t3 < <(jq -r '@tsv' <<<"$row")
min=$(printf '%s\n' "$login" "$api" "$latency" | sort -g | head -n1)

freeze_issue=""
if [ -n "${GH_TOKEN:-}" ]; then
  freeze_issue=$(gh issue list --label "$FREEZE_LABEL" --state open --json number -q '.[0].number' 2>/dev/null || true)
fi

lt() { jq -en --argjson a "$1" --argjson b "$2" '$a < $b' >/dev/null; }
le() { jq -en --argjson a "$1" --argjson b "$2" '$a <= $b' >/dev/null; }

if le "$min" 0; then
  state="FREEZE"
elif [ -n "$freeze_issue" ] && lt "$min" 20; then
  state="FREEZE" # todavía sin el 20 % de margen para descongelar
elif le "$min" 50; then
  state="ALERTA"
else
  state="NORMAL"
fi

{
  echo "### Error budget (30 días): **${state}**"
  echo ""
  echo "| SLI | SLO | Presupuesto restante | Peticiones válidas |"
  echo "| --- | --- | --- | --- |"
  echo "| 1. Login (\`/api/v1/auth\`) | 99.9 % | ${login} % | ${t1} |"
  echo "| 2. API de consultas | 99.5 % | ${api} % | ${t2} |"
  echo "| 3. Latencia <= 300 ms | 95 % | ${latency} % | ${t3} |"
} >> "$SUMMARY"

if [ "$MANAGE_ISSUE" = "true" ] && [ -n "${GH_TOKEN:-}" ]; then
  if [ "$state" = "FREEZE" ] && [ -z "$freeze_issue" ]; then
    gh label create "$FREEZE_LABEL" --color B60205 --description "Error budget agotado" --force >/dev/null
    gh issue create --label "$FREEZE_LABEL" \
      --title "Release freeze: error budget agotado" \
      --body "$(printf 'Un presupuesto de error de 30 días se agotó (login %s %%, API %s %%, latencia %s %%).\n\nSegún la política de error budget: no se fusionan ni despliegan features hasta que el presupuesto más degradado recupere un 20 %%. Solo se permiten hotfixes aprobados por el SRE Lead y el Product Owner (etiqueta `hotfix` en el PR o `[hotfix]` en el commit).\n\nEl postmortem debe estar listo en 48 h.' "$login" "$api" "$latency")"
  elif [ "$state" != "FREEZE" ] && [ -n "$freeze_issue" ]; then
    gh issue close "$freeze_issue" \
      --comment "El presupuesto más degradado recuperó el margen (${min} %): se levanta el release freeze."
  fi
fi

case "$state" in
  FREEZE)
    if [ "$HOTFIX" = "true" ]; then
      echo "::warning::Release freeze activo (presupuesto mínimo ${min} %), pero es un hotfix: se permite."
    else
      echo "::error::Release freeze: el error budget está agotado (presupuesto mínimo ${min} %). Solo se permiten hotfixes."
      exit 1
    fi
    ;;
  ALERTA)
    echo "::warning::Error budget en alerta (presupuesto mínimo ${min} %): revisión estricta y pruebas de carga obligatorias."
    ;;
esac
