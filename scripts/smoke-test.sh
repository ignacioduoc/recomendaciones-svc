#!/usr/bin/env bash
# Prueba de humo del microservicio desplegado (se usa en Docker Compose y en Kubernetes).
# Uso: scripts/smoke-test.sh <url-base> [commit-esperado]
#   scripts/smoke-test.sh http://localhost:8080
#   scripts/smoke-test.sh http://localhost:8080 "$GITHUB_SHA"   # además valida trazabilidad
set -euo pipefail

BASE_URL="${1:?Falta la URL base, por ejemplo http://localhost:8080}"
COMMIT_ESPERADO="${2:-}"
API="$BASE_URL/api/recomendaciones"
JSON='Content-Type: application/json'

codigo() { curl -s -o /dev/null -w '%{http_code}' "$@"; }

verificar() {
  local descripcion="$1" esperado="$2" obtenido="$3"
  if [[ "$esperado" == "$obtenido" ]]; then
    echo "OK    $descripcion ($obtenido)"
  else
    echo "FALLA $descripcion: se esperaba $esperado y se obtuvo $obtenido"
    exit 1
  fi
}

echo "Esperando que $BASE_URL esté listo..."
for _ in $(seq 1 45); do
  if [[ "$(codigo "$BASE_URL/actuator/health/readiness")" == "200" ]]; then break; fi
  sleep 2
done

verificar "liveness"  200 "$(codigo "$BASE_URL/actuator/health/liveness")"
verificar "readiness" 200 "$(codigo "$BASE_URL/actuator/health/readiness")"

if [[ -n "$COMMIT_ESPERADO" ]]; then
  commit=$(curl -fsS "$BASE_URL/actuator/info" | jq -r '.app.commit')
  verificar "commit desplegado = commit del pipeline" "$COMMIT_ESPERADO" "$commit"
fi

respuesta=$(curl -s -w '\n%{http_code}' -H "$JSON" \
  -d '{"nombre":"smoke-test","contenido":"pipeline","score":4.5}' "$API")
verificar "POST crea recurso" 201 "$(tail -n1 <<<"$respuesta")"
id=$(head -n -1 <<<"$respuesta" | jq -r '.id')

verificar "GET recurso creado" 200 "$(codigo "$API/$id")"
verificar "PUT actualiza recurso" 200 \
  "$(codigo -X PUT -H "$JSON" -d '{"nombre":"smoke-actualizado"}' "$API/$id")"
verificar "POST inválido es rechazado" 400 "$(codigo -H "$JSON" -d '{"nombre":""}' "$API")"
verificar "DELETE elimina recurso" 204 "$(codigo -X DELETE "$API/$id")"
verificar "GET recurso eliminado" 404 "$(codigo "$API/$id")"
verificar "/actuator/env no está expuesto" 404 "$(codigo "$BASE_URL/actuator/env")"

echo "Prueba de humo completa."
