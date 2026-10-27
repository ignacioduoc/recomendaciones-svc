#!/usr/bin/env bash
# Despliega recomendaciones-svc en el clúster del contexto actual de kubectl (IE4/IE5).
# Uso: scripts/k8s-deploy.sh <desarrollo|produccion> <tag-imagen> [commit] [url-ejecucion]
#   Pipeline: scripts/k8s-deploy.sh desarrollo sha-1a2b3c4 "$GITHUB_SHA" "$URL_DEL_RUN"
#   Local:    scripts/k8s-deploy.sh desarrollo local
set -euo pipefail

OVERLAY="${1:?Indica el overlay: desarrollo o produccion}"
TAG="${2:?Indica la etiqueta de la imagen, por ejemplo sha-1a2b3c4}"
COMMIT="${3:-local}"
RUN_URL="${4:-local}"

case "$OVERLAY" in
  desarrollo) NAMESPACE=recomendaciones-dev ;;
  produccion) NAMESPACE=recomendaciones-prod ;;
  *) echo "Overlay desconocido: $OVERLAY (usa desarrollo o produccion)" >&2; exit 2 ;;
esac

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
TRABAJO="$RAIZ/k8s/.deploy"   # carpeta temporal, ignorada por git
mkdir -p "$TRABAJO"

# La contraseña de PostgreSQL se genera en el primer despliegue y nunca se versiona.
if [[ ! -f "$TRABAJO/db.env" ]]; then
  ( umask 077; printf 'password=%s\n' "${DB_PASSWORD:-$(openssl rand -hex 16)}" > "$TRABAJO/db.env" )
fi

# Kustomization de despliegue: overlay + imagen trazable + Secret + anotaciones de origen
cat > "$TRABAJO/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: ${NAMESPACE}
resources:
  - ../overlays/${OVERLAY}
images:
  - name: recomendaciones-svc
    newTag: ${TAG}
secretGenerator:
  - name: recomendaciones-db
    envs:
      - db.env
patches:
  - target:
      kind: Deployment
      name: recomendaciones-svc
    patch: |-
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: recomendaciones-svc
        annotations:
          kubernetes.io/change-cause: "commit ${COMMIT} - imagen recomendaciones-svc:${TAG}"
          recomendaciones.duoc.cl/pipeline-run: "${RUN_URL}"
      spec:
        template:
          metadata:
            labels:
              app.kubernetes.io/version: "${TAG}"
            annotations:
              recomendaciones.duoc.cl/git-commit: "${COMMIT}"
EOF

echo "Aplicando overlay '$OVERLAY' en namespace '$NAMESPACE' con imagen recomendaciones-svc:$TAG"
kubectl apply -k "$TRABAJO"

echo "Esperando PostgreSQL..."
kubectl -n "$NAMESPACE" rollout status statefulset/recomendaciones-db --timeout=180s
echo "Esperando el rollout del microservicio..."
kubectl -n "$NAMESPACE" rollout status deployment/recomendaciones-svc --timeout=300s

kubectl -n "$NAMESPACE" get deploy,sts,svc,hpa,pdb,pods -o wide
