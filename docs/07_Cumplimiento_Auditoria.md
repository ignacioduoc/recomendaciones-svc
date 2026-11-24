# Cumplimiento y auditoría automatizada (EP3 · IE5)

Documenta las políticas de cumplimiento de `recomendaciones-svc`, la herramienta que aplica cada una y cómo se verifica.

| | |
|---|---|
| Workflow | [`.github/workflows/ep3-b.yml`](../.github/workflows/ep3-b.yml) |
| Script de auditoría | [`audit/auditoria.sh`](../audit/auditoria.sh) |
| Configuración de Gitleaks | [`.gitleaks.toml`](../.gitleaks.toml) |
| Excepciones de seguridad | [`.trivyignore.yaml`](../.trivyignore.yaml) |
| Responsable | Felipe Veliz |

## Cuándo se audita

| Evento | Qué corre | Qué revisa Gitleaks |
|---|---|---|
| Pull Request hacia `develop` o `main` | `ep3-b.yml` completo | Los commits del PR |
| Push a `develop` | `ep3-a.yml` llama a `ep3-b.yml` antes de desplegar en EKS | Los commits nuevos del push |
| *Run workflow* manual | `ep3-b.yml` sobre la rama elegida | Los archivos del commit actual |
| Local | `audit/auditoria.sh todo` | Los archivos actuales, o el rango de `AUDITORIA_RANGO` |

## Políticas, herramientas y verificación

| # | Política | Herramienta | Cómo se verifica | Si no se cumple |
|---|---|---|---|---|
| 1 | Todo cambio a `main` o `develop` entra por Pull Request, con los checks en verde y sin force push | Ruleset `proteccion-main-develop` de GitHub | `auditoria.sh politicas` consulta la API `GET /repos/{repo}/rules/branches/{rama}` y exige las reglas `pull_request`, `required_status_checks` y `non_fast_forward` | GitHub rechaza el push o el merge, y la auditoría falla si alguien desactiva una regla |
| 2 | El código cumple el Quality Gate de calidad y seguridad | SonarQube Cloud | Job `analisis-codigo` de `ci-cd.yml` con `sonar.qualitygate.wait=true` | El job falla y el PR no se puede integrar |
| 3 | No hay secretos en el código | Gitleaks 8.30.1 | Job `Auditoría · Secretos (IE5)` de `ep3-b.yml` | El pipeline se detiene; el PR muestra el archivo y la línea |
| 4 | Ninguna librería del jar tiene un CVE crítico sin excepción vigente | Trivy 0.70.0 (`rootfs` sobre el jar) | Job `Auditoría · Dependencias críticas (IE5)` de `ep3-b.yml` | El pipeline se detiene; los hallazgos quedan en la pestaña *Security* |
| 5 | La imagen no tiene CVE HIGH/CRITICAL con parche y su configuración es segura | Trivy (imagen y configuración) | Job `escaneo-imagen` de `ci-cd.yml` | No se despliega ni se publica la imagen |
| 6 | Un PR no agrega dependencias con vulnerabilidad alta o crítica | Dependency Review | Job `revision-dependencias` de `ci-cd.yml` | El check falla y comenta el PR |
| 7 | Las dependencias se mantienen al día | Dependabot | PR semanales hacia `develop`; `auditoria.sh politicas` verifica que vigile Maven, Docker y GitHub Actions | La auditoría falla si se quita un ecosistema |
| 8 | Toda excepción de seguridad tiene justificación y vence en 180 días o menos | `.trivyignore.yaml` | `auditoria.sh politicas` revisa `statement` y `expired_at` de cada excepción | La auditoría falla; al vencer la fecha, Trivy vuelve a bloquear |
| 9 | Las acciones de GitHub van fijadas por SHA completo | GitHub Actions | `auditoria.sh politicas` revisa cada `uses:` de `.github/workflows/` | La auditoría falla y marca la línea |
| 10 | Cada workflow declara permisos mínimos para el `GITHUB_TOKEN` | `permissions:` en cada workflow | `auditoria.sh politicas` exige `permissions:` y rechaza `write-all` | La auditoría falla |
| 11 | No se versionan archivos de credenciales | `.gitignore` | `auditoria.sh politicas` busca `.env`, llaves, keystores, kubeconfig y `tfstate` en `git ls-files` | La auditoría falla |
| 12 | El despliegue en EKS lo aprueba una persona distinta a la que lo disparó | Environment `produccion-eks` con revisores requeridos | Job `Aprobación para producción (IE6)` de `ep3-b.yml` | El despliegue queda esperando o, si se rechaza, en *skipped* |
| 13 | La imagen no corre como root, tiene HEALTHCHECK, pesa menos de 400 MB y apunta a su commit | Política de imagen | Job `imagen` de `ci-cd.yml` | No se despliega |
| 14 | Las credenciales de AWS, Grafana y SonarQube viven fuera del repositorio | GitHub Secrets | Gitleaks (política 3) y archivos sensibles (política 11) | Igual que las políticas 3 y 11 |

Las políticas 3, 4 y 7 a 11 las aplica el script de este EP. El resto ya venían del pipeline de la EP2 y del despliegue en EKS, y aquí solo se registran.

## Controles del script

`audit/auditoria.sh` termina con código `0` si cumple, `1` si no cumple una política y `2` si no pudo auditar, por ejemplo si falta una herramienta o la API no respondió. En el pipeline (`AUDITORIA_ESTRICTA=true`), el código `2` también detiene el despliegue: lo que no se puede verificar no se da por bueno.

### Secretos

- Usa todas las reglas por defecto de Gitleaks (claves de AWS, tokens de GitHub, llaves privadas, contraseñas, etc.).
- En un PR revisa solo sus commits y en un push solo los commits nuevos. Así un secreto que quedó en el historial de una rama de demostración no bloquea los PR siguientes.
- El reporte oculta los valores (`--redact`).
- `.gitleaks.toml` excluye binarios (`png`, `pdf`), `target/`, `reportes/` y las líneas `apiVersion:` de Kubernetes, que la regla genérica puede confundir con una clave.

### Dependencias críticas

- Empaqueta el jar con `mvn -DskipTests package` y lo escanea con `trivy rootfs`. Escanear el jar y no solo el `pom.xml` entrega las versiones exactas que se despliegan, con las transitivas y los ajustes de `pom.xml` (Tomcat, Jackson, driver de PostgreSQL).
- Bloquea solo con severidad `CRITICAL`. Los `HIGH` se ven en la pestaña *Security* y la imagen ya se bloquea por HIGH/CRITICAL en `ci-cd.yml`.
- Aplica las excepciones de `.trivyignore.yaml`. Una excepción vencida deja de aplicarse y el CVE vuelve a bloquear.

### Políticas del repositorio

| Control | Qué revisa | Fuente |
|---|---|---|
| Ramas protegidas | `main` y `develop` tienen las reglas `pull_request`, `required_status_checks` y `non_fast_forward` activas. El reporte lista los checks requeridos y las aprobaciones exigidas | API de rulesets de GitHub |
| Acciones fijadas por SHA | Cada `uses:` externo termina en un SHA de 40 caracteres | `.github/workflows/*.yml` |
| Permisos mínimos | Cada workflow declara `permissions:` y ninguno usa `write-all` | `.github/workflows/*.yml` |
| Excepciones | Cada entrada tiene `statement` y `expired_at`, no está vencida y no vence en más de 180 días | `.trivyignore.yaml` |
| Archivos sensibles | No hay `.env`, `*.pem`, `*.key`, `*.p12`, `*.jks`, `id_rsa`, `kubeconfig` ni `*.tfstate` versionados | `git ls-files` |
| Dependabot | Vigila `maven`, `docker` y `github-actions` | `.github/dependabot.yml` |

## Reporte de auditoría

Cada ejecución deja la misma evidencia en cuatro lugares:

| Dónde | Qué contiene |
|---|---|
| Resumen del job `Resultado de auditoría (IE5, IE6)` | Tabla con cada control, la herramienta, el resultado y el detalle; commit, rama, evento y enlace a la ejecución |
| Artefacto `reporte-auditoria` (90 días) | `resumen.md`, `reporte.json`, `gitleaks.json`, `trivy-dependencias.json` y el detalle de cada control |
| Pestaña *Security → Code scanning* | Hallazgos HIGH/CRITICAL de Trivy en la categoría `trivy-dependencias` |
| Anotaciones del PR | Archivo y línea de cada secreto detectado y de cada acción sin fijar |

## Registro de excepciones

| CVE | Librería | Motivo | Vence |
|---|---|---|---|
| CVE-2026-47884 | spring-webmvc 6.2.19 | La falla está en `XsltView`; el servicio es una API REST JSON y no usa vistas XSLT. No hay parche en Spring Framework 6.2 OSS | 2027-01-31 |
| CVE-2026-47890 | spring-webmvc 6.2.19 | La falla afecta Server-Sent Events con vistas; el servicio no usa SSE. No hay parche en Spring Framework 6.2 OSS | 2027-01-31 |

El arreglo definitivo de ambas es migrar a Spring Boot 4 (Spring Framework 7.0.9 o superior).

Para agregar una excepción:

1. Abrir un PR que agregue la entrada en `.trivyignore.yaml` con `id`, `statement` (por qué el servicio no está expuesto) y `expired_at` (180 días como máximo).
2. Actualizar esta tabla en el mismo PR.
3. El otro integrante revisa y aprueba el PR. La auditoría rechaza excepciones sin justificación, sin fecha o con un plazo mayor.

## Revisión de Dependabot

Criterio para cada PR de Dependabot:

| Tipo de actualización | Decisión |
|---|---|
| Parche o versión menor, con todos los checks en verde | Se integra |
| Versión mayor de una librería o imagen | Se cierra con `@dependabot ignore this major version` y se planifica aparte, porque puede romper compatibilidad |
| Imagen de Java que no es LTS (24, 26) | Se cierra con `@dependabot ignore this major version`: el proyecto usa Java 21 LTS |
| Actualización que corrige una alerta de seguridad | Se integra aunque sea mayor, si los checks quedan en verde |

Revisión del 23 de noviembre de 2026:

| PR de Dependabot | Cambio | Decisión |
|---|---|---|
| Grupo `acciones` (6 actualizaciones) | Versiones menores de `setup-java`, `action-junit-report`, `upload-sarif`, `dependency-review-action`, `kind-action` y `login-action` en `ci-cd.yml` | Integrar si los checks pasan |
| `maven-surefire-plugin` | 3.2.5 → 3.6.1 | Integrar si los checks pasan |
| `sonar-maven-plugin` | 5.7.0 → 5.9.0 | Integrar si los checks pasan |
| Grupo `pruebas` | Cucumber 7.18.1 → 8.1.0 (mayor) y JaCoCo 0.8.12 → 0.8.16 | Integrar si los checks pasan; si fallan, cerrar e ignorar la versión mayor de Cucumber |
| Grupo `spring-boot` | Spring Boot 3.5.16 → 4.2.0 y springdoc 2.8.17 → 3.2.1 | Cerrar. Es una migración: el `pom.xml` fija Tomcat 10.1, y Spring Boot 4 usa Tomcat 11 y Jackson 3. Las dos alertas críticas que corrige siguen cubiertas por la excepción hasta el 2027-01-31 |
| `eclipse-temurin` 21 → 24 (imagen de ejecución) | Java no LTS | Cerrar e ignorar la versión mayor |
| `maven:3.9-eclipse-temurin` → 26 (imagen de compilación) | Java no LTS | Cerrar e ignorar la versión mayor |
| `postgres` 17 → 19 (Kubernetes y Docker Compose) | Versión mayor de la base de datos | Cerrar e ignorar la versión mayor |

## Ejecutar la auditoría en local

Requiere `git`, `jq`, `yq` y `curl`, y además `gitleaks` y `trivy` instalados (o Docker para usar sus imágenes).

```bash
mvn -B -ntp -DskipTests package           # el control de dependencias audita el jar
audit/auditoria.sh todo                   # los tres controles y el reporte
cat reportes/auditoria/resumen.md

# Solo los commits de tu rama, como lo haría un PR
AUDITORIA_RANGO=origin/develop..HEAD audit/auditoria.sh secretos

# Con un token, también verifica las reglas de rama
GH_TOKEN=$(gh auth token) audit/auditoria.sh politicas
```

## Evidencias

Capturas en [`docs/evidencias/`](evidencias/):

| Archivo | Qué muestra |
|---|---|
| `auditoria-resultado-pipeline.png` | Resumen del job `Resultado de auditoría (IE5, IE6)` en verde, con la tabla de controles |
| `auditoria-politicas-verificadas.png` | Tabla de políticas del reporte, con los checks requeridos de `main` y `develop` |
| `auditoria-trivy-security.png` | Pestaña *Security → Code scanning* filtrada por `trivy-dependencias` |
| `auditoria-ruleset-check-requerido.png` | Ruleset `proteccion-main-develop` con `Resultado de auditoría (IE5, IE6)` como check requerido |
| `auditoria-dependabot-revisado.png` | Pestaña *Security → Dependabot* después de la revisión |

## Justificación técnica

> **Pendiente:** la escribe Felipe, sin IA.
