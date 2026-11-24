# Changelog

## [Unreleased]
- Se agrega archivo de changelog.
- Página de presentación del microservicio.
- EP3 · Auditoría automatizada de cumplimiento (`audit/auditoria.sh`): Gitleaks, Trivy sobre el jar y verificación de reglas de rama, acciones por SHA, permisos, excepciones y archivos sensibles.
- EP3 · Workflow `ep3-b.yml`: gates en secuencia, check `Resultado de auditoría (IE5, IE6)` y aprobación del environment `produccion-eks` antes de desplegar en EKS.
- EP3 · Documentación de cumplimiento, freno del pipeline y mapa del pipeline (`docs/07` a `docs/09`).

## [1.1.0] - Octubre 2026 (EP2 DOY0101)
- Pipeline CI/CD en GitHub Actions: pruebas y cobertura, SonarQube Cloud, imagen Docker, Trivy, Dependency Review, despliegue en Kubernetes (kind) y publicación en GHCR.
- Dockerfile multi-stage con capas de Spring Boot, JRE alpine, usuario sin privilegios y HEALTHCHECK.
- Orquestación con Kubernetes (kustomize): Deployment, Service, HPA, PodDisruptionBudget y PostgreSQL en StatefulSet; overlays desarrollo y produccion.
- Docker Compose con PostgreSQL, healthchecks y límites de recursos.
- Spring Boot Actuator (liveness, readiness, info con commit desplegado) y apagado ordenado.
- Dependabot para Maven, Docker, Docker Compose y GitHub Actions.
- Actualización a Spring Boot 3.5.16 y springdoc 2.8.17.
- Parches de seguridad detectados por Trivy: Tomcat 10.1.59, Jackson 2.21.8, PostgreSQL JDBC 42.7.14 y paquetes de alpine; excepción documentada con vencimiento para 2 CVE de Spring Web MVC 6.2.

## [0.1.0] - Agosto 2026
- Primera versión del microservicio de Recomendaciones (StreamVerse).
