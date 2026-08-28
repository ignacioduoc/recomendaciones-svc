# ms-recomendaciones — Justificación del servicio y cobertura de requisitos

**Caso caso03 — StreamVerse** (Plataforma de streaming) · EP01 JVY0101

Este documento justifica la existencia de **ms-recomendaciones** como microservicio independiente: qué requisitos del negocio cubre (funcionales, no funcionales y de seguridad), por qué está delimitado así (SRP), y qué tecnología AWS se usa para cada responsabilidad y **por qué**. Los diagramas que respaldan esta justificación están en `docs/diagramas/`.

---

## 1. Misión del servicio

ms-recomendaciones convierte los eventos del negocio en información: consolida métricas, reportes y detección de patrones sobre un data lake, sin golpear jamás las bases de datos transaccionales del caso caso03 (StreamVerse).

> Trabaja sobre una copia histórica de los datos (CQRS-lite) con procesamiento por lotes serverless: puede caerse o demorarse sin afectar en nada la operación del negocio, y en cambio absorbe cargas de cómputo masivas cuando se generan reportes.

---

## 2. Requisitos funcionales que cubre

| RF | Requisito (de `00_PresentacionEmpresa.md`) | Qué hace ms-recomendaciones al respecto | Evidencia |
|----|------------------------------------------|-------------------------------|-----------|
| **RF-05** | Generar recomendaciones personalizadas por historial de visualización | Consolida los eventos del dominio en el data lake y expone los reportes e indicadores del negocio | infraestructura AWS (Lambda + S3 + Athena) |

**Por qué estos RF justifican un servicio aparte:** Trabaja sobre una copia histórica de los datos (CQRS-lite) con procesamiento por lotes serverless: puede caerse o demorarse sin afectar en nada la operación del negocio, y en cambio absorbe cargas de cómputo masivas cuando se generan reportes.

---

## 3. Requisitos no funcionales que cubre

| RNF | Criterio | Cómo lo cumple ms-recomendaciones | Decisión técnica |
|-----|----------|--------------------------|------------------|
| **RNF-01** (Escalabilidad) | Escalar reproducción y catálogo horizontalmente ante millones de usuarios simultáneos | Auto scaling independiente de este servicio (0→0 tareas Fargate según carga) | ECS Fargate + alarmas de CloudWatch: solo este componente escala en el pico |
| **RNF-03** (Mantenibilidad) | Despliegue independiente de servicios; estrenos y catálogo actualizables sin downtime | Despliegue independiente (blue/green) sin coordinar con otros dominios | Pipeline CI/CD propio + bajo acoplamiento solo por API/eventos |

**Justificación SRP (IE9):** ms-recomendaciones tiene **una sola razón de cambio**: los reportes e indicadores que pide el negocio (nuevas métricas no tocan la operación). Si mañana cambia esa regla, **ningún otro servicio se modifica**.

---

## 4. Requisitos de seguridad que cubre (mapeo STRIDE)

| Amenaza | Escenario en este servicio | Contramedida |
|---------|-----------------------------|--------------|
| **S**poofing | Publicar métricas falsas en los reportes | Los datos solo provienen del data lake alimentado por eventos firmados del bus; sin ingesta manual |
| **T**ampering | Alterar reportes ya emitidos | Los archivos del data lake son inmutables (S3 con versionado); los reportes son derivados reproducibles |
| **R**epudiation | Negar lo que muestran las métricas | Cada reporte referencia el rango de datos y la consulta (SQL) que lo generó, reproducible |
| **I**nformation disclosure | Filtrar datos personales en reportes | Agregación y anonimización antes de exponer; cifrado del data lake con KMS; acceso por rol |
| **D**enial of service | Consulta masiva que encarezca o colapse | Consultas serverless (Athena) con límite de concurrencia; el cómputo no toca la operación |
| **E**levation of privilege | Ver reportes de otro tenant/empresa | Autorización por tenant en los endpoints; bucket policy del data lake por rol |

---

## 5. Stack tecnológico y por qué cada tecnología

### 5.1 Stack de la aplicación

| Tecnología | Para qué se usa en ms-recomendaciones |
|------------|------------------------------|
| **Java 21 + Spring Boot 3.3** | Framework estándar de la asignatura: implementa la API REST, la lógica de negocio y el acceso a datos del servicio |
| **Spring Data JPA** | Persistencia de las entidades del dominio en la base de datos propia (repositorios por entidad) |
| **Bean Validation** | Validación de los payloads de entrada antes de procesar (jakarta.validation) |
| **springdoc-openapi** | Documentación viva del contrato REST (Swagger UI / ReDoc) para consumidores y equipo |
| **Docker + Docker Compose** | Empaquetado reproducible; la misma imagen corre en local y en ECS Fargate |
| **JUnit 5 + Mockito + MockMvc** | Pruebas unitarias y de contrato HTTP (cobertura 100 % LINE con JaCoCo) |
| **Cucumber (BDD)** | Escenarios en español alineados a los endpoints, ejecutados contra el servidor real |

### 5.2 Stack AWS y justificación de cada servicio

| Servicio AWS | Rol en ms-recomendaciones | Por qué se eligió |
|--------------|----------------|--------------------|
| **AWS Lambda** | Procesa y consolida eventos hacia el data lake | Carga por lotes intermitente: serverless escala a cero entre reportes (costo ~0 en valle) |
| **Amazon S3** | Data lake cifrado del dominio | Almacén de objetos barato, versionado e inmutable para el histórico (RNF de escalabilidad de datos) |
| **Amazon Athena** | Consulta SQL serverless sobre el data lake | Los reportes nunca tocan las bases transaccionales (CQRS-lite, IE10) |
| **Amazon EventBridge / SQS** | Ingesta de eventos de dominio | Desacople de los servicios productores |
| **AWS KMS** | Cifrado del data lake | Protección de datos personales agregados |
| **CloudWatch** | Métricas de ejecución batch | Monitoreo de las ventanas de procesamiento (IE8) |

### 5.3 Patrones aplicados (IE5)

| Patrón | Dónde |
|--------|-------|
| **CQRS-lite** | Lee del data lake, nunca de las bases transaccionales |
| **Event Sourcing ligero** | El data lake conserva el historial completo de eventos del dominio |
| **Serverless burst** | Lambda + Athena escalan a cero fuera de las ventanas de reporte |

---

## 6. Delimitación: qué NO hace ms-recomendaciones (IE9/IE10)

| No hace | Lo hace | Por qué |
|---------|---------|---------|
| usuarios | ms-usuarios | razones de cambio distintas: la autenticación se centraliza aquí, pero el negocio de cada dominio queda en su servicio |
| catálogo | ms-catalogo | razones de cambio distintas: el catálogo consulta y publica; las operaciones de negocio las orquesta el servicio transaccional |
| reproducción | ms-reproduccion | razones de cambio distintas: el seguimiento vive aquí, pero la operación que lo origina vive en el servicio central |
| suscripciones | ms-suscripciones | razones de cambio distintas: la operación se orquesta aquí, pero cada colaborador es autónomo |
| notificaciones | ms-notificaciones | razones de cambio distintas: la entrega de mensajes vive aquí, pero el contenido lo definen los productores |

---

## 7. Diagramas que respaldan esta justificación

```
docs/diagramas/
├── c4/
│   ├── C4-1-Contexto     el servicio, sus actores y sus vecinos
│   ├── C4-2-Contenedor   la API, la BD propia y los componentes del dominio
│   └── C4-3-Componentes  validador/service, clientes, publicador, repos
├── secuencia/
│   └── Secuencia-Recomendacion   consolidación batch y consulta de reportes
└── infraestructura/
    └── Infra-AWS         despliegue solo de este servicio, con iconos oficiales AWS
```

