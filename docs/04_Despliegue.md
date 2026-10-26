# Recomendaciones — Despliegue y operación

## Requisitos

- Java 21, Maven 3.9 (build local)
- Docker + Docker Compose (despliegue)

## Ejecución local

```bash
mvn spring-boot:run
```

URLs en `http://localhost:8080`:

| Recurso | URL |
|---------|-----|
| Página de presentación | `/` |
| Swagger UI | `/swagger-ui/index.html` |
| OpenAPI yaml | `/v3/api-docs.yaml` |
| ReDoc | `/redoc.html` |
| H2 Console | `/h2-console` |
| API base | `/api/recomendaciones` |

## Pipeline CI/CD

El despliegue automático (Kubernetes con kind) y la trazabilidad están documentados en el [README](../README.md#ie4--despliegue-automático-y-trazabilidad).

## Docker

```bash
docker build -t recomendaciones-svc:local .
docker run -p 8080:8080 recomendaciones-svc:local   # usa H2 en memoria
```

## Docker Compose

```bash
docker compose up --build
PORT=9090 docker compose up --build   # cambiar puerto host
```

## Base de datos

H2 en memoria (se pierde al detener el contenedor), configurable en `src/main/resources/application.yml`. Consola web en `/h2-console` (JDBC URL, usuario `sa`, sin clave).

## Variables de entorno

| Variable | Defecto | Descripción |
|----------|---------|-------------|
| `PORT` | `8080` | Puerto del servidor y mapeo del contenedor |
| `DB_URL` | H2 en memoria | URL JDBC (Compose y Kubernetes usan PostgreSQL) |
| `DB_USER` / `DB_PASSWORD` | `sa` / vacío | Credenciales de la base |
| `JPA_DDL_AUTO` | `create-drop` | `update` fuera de desarrollo local |
| `JPA_SHOW_SQL` | `true` | `false` fuera de desarrollo local |
| `H2_CONSOLE_ENABLED` | `true` | `false` fuera de desarrollo local |
| `APP_COMMIT` | `local` | Commit de la imagen (lo fija el Dockerfile con `GIT_COMMIT`) |
