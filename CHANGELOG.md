# Changelog

## [Unreleased]
- Se agrega archivo de changelog.
- Página de presentación del microservicio.

## [1.1.0] - Octubre 2026 (EP2 DOY0101)
- Pipeline CI/CD en GitHub Actions: pruebas y cobertura, SonarQube Cloud, imagen Docker, Trivy, Dependency Review, despliegue en Kubernetes (kind) y publicación en GHCR.
- Dockerfile multi-stage con capas de Spring Boot, JRE alpine, usuario sin privilegios y HEALTHCHECK.
- Orquestación con Kubernetes (kustomize): Deployment, Service, HPA, PodDisruptionBudget y PostgreSQL en StatefulSet; overlays desarrollo y produccion.
- Docker Compose con PostgreSQL, healthchecks y límites de recursos.
- Spring Boot Actuator (liveness, readiness, info con commit desplegado) y apagado ordenado.
- Dependabot para Maven, Docker, Docker Compose y GitHub Actions.
- Actualización a Spring Boot 3.5.16 y springdoc 2.8.17.

## [0.1.0] - Agosto 2026
- Primera versión del microservicio de Recomendaciones (StreamVerse).
