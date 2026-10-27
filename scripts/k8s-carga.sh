#!/usr/bin/env bash
# Demostración de autoescalado (HPA): genera carga dentro del clúster durante ~90 s
# y registra cuántas réplicas levanta Kubernetes. Es informativa: no bloquea el pipeline.
# Uso: scripts/k8s-carga.sh <namespace>
set -euo pipefail

NS="${1:?Indica el namespace, por ejemplo recomendaciones-dev}"
RESUMEN="${GITHUB_STEP_SUMMARY:-/dev/null}"
IMAGEN=$(kubectl -n "$NS" get deploy recomendaciones-svc -o jsonpath='{.spec.template.spec.containers[0].image}')
INICIAL=$(kubectl -n "$NS" get deploy recomendaciones-svc -o jsonpath='{.status.readyReplicas}')

kubectl -n "$NS" delete pod generador-carga --ignore-not-found --wait=true >/dev/null
kubectl -n "$NS" apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: generador-carga
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
    - name: carga
      image: ${IMAGEN}
      imagePullPolicy: IfNotPresent
      command:
        - sh
        - -c
        - |
          fin=\$((\$(date +%s) + 90))
          for p in 1 2 3 4 5 6 7 8; do
            ( while [ "\$(date +%s)" -lt "\$fin" ]; do
                wget -qO /dev/null http://recomendaciones-svc/api/recomendaciones || true
              done ) &
          done
          wait
      resources:
        requests:
          cpu: 250m
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

maximo=${INICIAL:-0}
muestras=""
for i in $(seq 1 9); do
  sleep 15
  actuales=$(kubectl -n "$NS" get deploy recomendaciones-svc -o jsonpath='{.status.replicas}')
  actuales=${actuales:-0}
  cpu=$(kubectl -n "$NS" get hpa recomendaciones-svc -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}' 2>/dev/null || true)
  echo "t=$((i * 15))s réplicas=$actuales cpu=${cpu:-?}%"
  muestras+="| $((i * 15)) s | $actuales | ${cpu:-?}% |"$'\n'
  (( actuales > maximo )) && maximo=$actuales
done

kubectl -n "$NS" delete pod generador-carga --wait=false >/dev/null || true
kubectl -n "$NS" get hpa recomendaciones-svc

{
  echo "### Autoescalado bajo carga ($NS)"
  echo ""
  echo "Réplicas al inicio: **${INICIAL}**, máximo observado: **${maximo}** (objetivo HPA: 70% CPU)."
  echo ""
  echo "| Tiempo | Réplicas | CPU promedio |"
  echo "|---|---|---|"
  printf '%s' "$muestras"
} >> "$RESUMEN"
