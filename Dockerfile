# syntax=docker/dockerfile:1.7
# Imagen del microservicio recomendaciones-svc (IE1)
#  - Multi-stage: Maven/JDK solo en la etapa de build; la imagen final lleva solo el JRE.
#  - Capas de Spring Boot: dependencias y código van en capas separadas, así un cambio
#    de código no vuelve a subir las dependencias (builds y despliegues más rápidos).
#  - Usuario sin privilegios (UID 10001) y HEALTHCHECK propio.

# ---------- Etapa 1: compilación ----------
FROM maven:3.9-eclipse-temurin-21-alpine AS build
WORKDIR /app
COPY pom.xml ./
RUN --mount=type=cache,target=/root/.m2 mvn -B -q dependency:go-offline
COPY src ./src
RUN --mount=type=cache,target=/root/.m2 mvn -B -q package -DskipTests \
 && java -Djarmode=tools -jar target/recomendaciones-svc-*.jar extract --layers --launcher --destination /app/extracted

# ---------- Etapa 2: ejecución ----------
FROM eclipse-temurin:25-jre-alpine AS runtime

# Commit que originó la imagen: lo expone /actuator/info (trazabilidad commit -> imagen -> pod)
ARG GIT_COMMIT=local

# Aplica los parches de seguridad publicados para los paquetes del sistema (alpine)
RUN apk upgrade --no-cache \
 && addgroup -S -g 10001 app && adduser -S -D -H -u 10001 -G app app

WORKDIR /app
# Archivos de la app quedan como root y solo lectura para el usuario "app"
COPY --from=build /app/extracted/dependencies/ ./
COPY --from=build /app/extracted/spring-boot-loader/ ./
COPY --from=build /app/extracted/snapshot-dependencies/ ./
COPY --from=build /app/extracted/application/ ./

ENV APP_COMMIT=${GIT_COMMIT} \
    JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=50.0 -XX:+ExitOnOutOfMemoryError"

USER 10001:10001
EXPOSE 8080

HEALTHCHECK --interval=15s --timeout=3s --start-period=60s --retries=3 \
  CMD wget -qO /dev/null http://127.0.0.1:8080/actuator/health/liveness || exit 1

ENTRYPOINT ["java", "org.springframework.boot.loader.launch.JarLauncher"]
