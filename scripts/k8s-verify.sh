#!/usr/bin/env bash
# Verifica la orquestación del despliegue en Kubernetes (IE4/IE5):
#   1. Prueba de humo a través del Service (incluye el commit desplegado).
#   2. Balanceo de carga: las peticiones dentro del clúster llegan a varias réplicas.
#   3. Autorecuperación: se elimina un pod y Kubernetes lo reemplaza.
# Uso: scripts/k8s-verify.sh <namespace> [commit-esperado]
set -euo pipefail

NS="${1:?Indica el namespace, por ejemplo recomendaciones-dev}"
COMMIT="${2:-}"
DIR="$(cd "$(dirname "$0")" && pwd)"
TMP="${RUNNER_TEMP:-/tmp}"
RESUMEN="${GITHUB_STEP_SUMMARY:-/dev/null}"
APP=app.kubernetes.io/name=recomendaciones-svc

# Ejecuta un script sh dentro del clúster usando la misma imagen del microservicio
# (cumple la política "restricted" del namespace) y devuelve su salida.
ejecutar_en_cluster() {
  local nombre="$1" script="$2" imagen fase=""
  imagen=$(kubectl -n "$NS" get deploy recomendaciones-svc -o jsonpath='{.spec.template.spec.containers[0].image}')
  kubectl -n "$NS" delete pod "$nombre" --ignore-not-found --wait=true >/dev/null
  kubectl -n "$NS" apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${nombre}
  labels:
    app.kubernetes.io/name: verificacion
spec:
  restartPolicy: Never
  automountServiceAccountToken: false
  securityContext:
    runAsNonRoot: true
    runAsUser: 10001
    runAsGroup: 10001
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: cliente
      image: ${imagen}
      imagePullPolicy: IfNotPresent
      command:
        - sh
        - -c
        - |
$(sed 's/^/          /' <<<"$script")
      resources:
        requests:
          cpu: 50m
          memory: 32Mi
        limits:
          cpu: "1"
          memory: 64Mi
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop: ["ALL"]
EOF
  for _ in $(seq 1 120); do
    fase=$(kubectl -n "$NS" get pod "$nombre" -o jsonpath='{.status.phase}')
    [[ "$fase" == "Succeeded" || "$fase" == "Failed" ]] && break
    sleep 2
  done
  kubectl -n "$NS" logs "$nombre"
  kubectl -n "$NS" delete pod "$nombre" --wait=false >/dev/null
  [[ "$fase" == "Succeeded" ]]
}

echo "== 1. Prueba de humo a través del Service"
kubectl -n "$NS" port-forward svc/recomendaciones-svc 18080:80 >"$TMP/port-forward.log" 2>&1 &
PF=$!
trap 'kill "$PF" 2>/dev/null || true' EXIT
"$DIR/smoke-test.sh" http://127.0.0.1:18080 "$COMMIT"
kill "$PF" 2>/dev/null || true

echo "== 2. Balanceo de carga entre réplicas"
ejecutar_en_cluster balanceo '
for i in $(seq 1 40); do
  wget -qO- http://recomendaciones-svc/actuator/info; echo
done' > "$TMP/balanceo.txt"
grep -o '"pod":"[^"]*"' "$TMP/balanceo.txt" | cut -d'"' -f4 | sort | uniq -c | tee "$TMP/reparto.txt"
pods_distintos=$(wc -l < "$TMP/reparto.txt")
replicas=$(kubectl -n "$NS" get deploy recomendaciones-svc -o jsonpath='{.status.readyReplicas}')
if (( replicas > 1 && pods_distintos < 2 )); then
  echo "FALLA: 40 peticiones llegaron a una sola réplica de $replicas"; exit 1
fi
echo "OK    40 peticiones repartidas entre $pods_distintos pods"

echo "== 3. Autorecuperación (se elimina un pod)"
victima=$(kubectl -n "$NS" get pods -l "$APP" -o jsonpath='{.items[0].metadata.name}')
kubectl -n "$NS" delete pod "$victima" --wait=false
recuperado=false
for _ in $(seq 1 60); do
  sleep 3
  deseadas=$(kubectl -n "$NS" get deploy recomendaciones-svc -o jsonpath='{.spec.replicas}')
  listas=$(kubectl -n "$NS" get deploy recomendaciones-svc -o jsonpath='{.status.readyReplicas}')
  if ! kubectl -n "$NS" get pod "$victima" >/dev/null 2>&1 && [[ "$listas" == "$deseadas" ]]; then
    recuperado=true; break
  fi
done
kubectl -n "$NS" get pods -l "$APP" -o wide
if [[ "$recuperado" != true ]]; then echo "FALLA: el Deployment no recuperó sus réplicas"; exit 1; fi
echo "OK    pod $victima reemplazado; $listas/$deseadas réplicas listas"

{
  echo "### Verificación de orquestación ($NS)"
  echo ""
  echo "| Verificación | Resultado |"
  echo "|---|---|"
  echo "| Prueba de humo (salud, CRUD, validación, commit \`${COMMIT:0:7}\`) | OK |"
  echo "| Balanceo: 40 peticiones internas repartidas en $pods_distintos pods | OK |"
  echo "| Autorecuperación: pod \`$victima\` eliminado y reemplazado ($listas/$deseadas listas) | OK |"
  echo ""
  echo '```'
  cat "$TMP/reparto.txt"
  echo '```'
} >> "$RESUMEN"
