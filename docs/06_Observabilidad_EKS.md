# Observabilidad y despliegue en la nube (EP3)

Documenta el monitoreo, el despliegue en Kubernetes en la nube y el dashboard del microservicio `recomendaciones-svc`.

## Monitoreo (IE1)

El servicio expone sus métricas en `/actuator/prometheus` con Micrometer. Prometheus las recoge cada 15 segundos.

| Entorno | Qué corre | Dónde está |
|---|---|---|
| Local | Prometheus, Grafana, Loki y Promtail con Docker Compose | `monitoring/` |
| Nube | Prometheus, Grafana y Pushgateway en Kubernetes | `k8s/observabilidad/` |

### Alertas (`alertas.yml`)

| Alerta | Condición | Severidad |
|---|---|---|
| `ServicioCaido` | `up{job="recomendaciones-svc"} == 0` durante 1 minuto | crítica |
| `ErroresServidorAltos` | Más del 5 % de las peticiones con 5xx durante 5 minutos | alta |
| `MemoriaHeapAlta` | Heap sobre el 85 % durante 5 minutos | media |

## Kubernetes en la nube (IE2)

| Elemento | Valor |
|---|---|
| Plataforma | Amazon EKS (AWS Academy Learner Lab) |
| Clúster | `recomendaciones`, región `us-east-1` |
| Nodos | Grupo `nodos-recomendaciones`, 2 nodos `t3.medium` |
| Microservicio | Namespace `recomendaciones-eks`, overlay `k8s/overlays/eks` |
| Observabilidad | Namespace `observabilidad`, `k8s/observabilidad` |
| Entrada | Servicios `LoadBalancer` para el microservicio y para Grafana |

### Cómo se despliega

Todo se aplica desde el pipeline `.github/workflows/ep3-a.yml`, con `kubectl apply`. Nada se aplica a mano. Se ejecuta en cada push a `develop`:

1. Espera a que el CI/CD publique la imagen `sha-<commit>` en GHCR.
2. Comprueba las credenciales de AWS y conecta `kubectl` al clúster.
3. Crea el namespace `observabilidad` y el Secret `grafana-admin` desde un secret de GitHub.
4. Despliega el microservicio con `scripts/k8s-deploy.sh eks`.
5. Aplica `k8s/observabilidad` y espera los rollouts de Prometheus, Grafana y Pushgateway.
6. Verifica `/actuator/health` y `/actuator/prometheus` por el balanceador.
7. Publica la cobertura y el tiempo de despliegue en el Pushgateway.

### Secrets de GitHub

| Secret | Uso |
|---|---|
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` | Credenciales temporales del Learner Lab |
| `GRAFANA_ADMIN_PASSWORD` | Clave de administrador de Grafana |

Las credenciales del Learner Lab vencen al terminar la sesión del laboratorio. Hay que renovar los tres secrets antes de un nuevo despliegue.

### Limitaciones del laboratorio

- Postgres usa un volumen temporal (`emptyDir`), así que los datos no persisten si el pod se reinicia.
- Los balanceadores usan HTTP, porque no hay dominio ni certificado.

### Seguridad de los manifiestos

Los manifiestos de observabilidad pasan el escaneo de configuración con Trivy: contenedores sin root, `readOnlyRootFilesystem` y permisos mínimos para Prometheus (`nodes/metrics`, pods, services y endpoints).

## Dashboard (IE3)

Grafana carga el datasource y el dashboard `ep3-observabilidad` desde archivos de provisioning, por lo que no hay que configurar nada a mano.

| Panel | Métrica |
|---|---|
| Pods arriba | `up{job="recomendaciones-svc"}` |
| CPU por contenedor | cAdvisor, leído directo del kubelet |
| Memoria por contenedor | cAdvisor, leído directo del kubelet |
| Errores 5xx | `http_server_requests_seconds_count{status=~"5.."}` |
| Peticiones por estado | `http_server_requests_seconds_count` |
| Cobertura de pruebas | `ci_cobertura_lineas_percent` (JaCoCo) |
| Tiempo de despliegue | `ci_despliegue_duracion_segundos` |

La cobertura y el tiempo de despliegue los empuja el pipeline al Pushgateway después de cada despliegue.

## Evidencias

Las capturas están en `docs/evidencias/`:

- `eks-pods-en-ejecucion.png`: pods del clúster en ejecución.
- `eks-grafana-conexion-prometheus.png`: Grafana conectado a Prometheus.
- `eks-grafana-memoria-pods.png`: memoria por pod.
- `eks-prometheus-kubelet-directo.png`: cAdvisor leído directo del kubelet.
- `eks-pipeline-despliegue-automatico.png`: ejecución de `ep3-a.yml` en verde, disparada por un push a `develop`.
