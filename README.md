# Recomendaciones — Microservicio de riesgo recomendaciones

Microservicio correspondiente al **caso caso03 — StreamVerse** (Plataforma de streaming) de la Evaluación Parcial N°1.

| | |
|---|---|
| Asignatura | JVY0101 — Java: Diseño y Construcción de Soluciones Nativas en Nube |
| Stack | Spring Boot 3.3 · Java 21 · Maven · Spring Data JPA · H2 · springdoc-openapi |
| Calidad | JaCoCo cobertura LINE 100% · Cucumber (BDD) alineado a endpoints REST |
| Entrega | Docker / Docker Compose |

## Responsabilidad (SRP)

administra los datos y la lógica del dominio de Recomendaciones del caso caso03 (StreamVerse). Su base de datos es una **H2 en memoria** (un solo microservicio por base), cumpliendo aislamiento de datos por dominio.

## Página de presentación

Al ejecutar el servicio, `http://localhost:8080/` muestra la página de presentación del microservicio con documentación y enlaces a:

- **Swagger UI**: `/swagger-ui/index.html`
- **OpenAPI (yaml)**: `/v3/api-docs.yaml`
- **ReDoc**: `/redoc.html`
- **H2 Console**: `/h2-console`

## Endpoints

| Método | Ruta | Descripción |
|--------|------|-------------|
| GET | `/api/recomendaciones` | Lista todos los recursos |
| GET | `/api/recomendaciones/{id}` | Obtiene un recurso por id |
| POST | `/api/recomendaciones` | Crea un recurso |
| PUT | `/api/recomendaciones/{id}` | Actualiza un recurso |
| DELETE | `/api/recomendaciones/{id}` | Elimina un recurso |

## Documentación del proyecto

La documentación completa está en la carpeta [`docs/`](docs/):

- [`docs/00_Resumen.md`](docs/00_Resumen.md) — propósito, responsabilidad y tecnologías
- [`docs/01_Arquitectura.md`](docs/01_Arquitectura.md) — componentes, arquitectura y patrones
- [`docs/02_API.md`](docs/02_API.md) — contrato REST y ejemplos curl
- [`docs/03_Pruebas.md`](docs/03_Pruebas.md) — tests unitarios, cobertura y Cucumber
- [`docs/04_Despliegue.md`](docs/04_Despliegue.md)
- [`docs/05_Justificacion.md`](docs/05_Justificacion.md) — justificación del servicio: RF/RNF/seguridad cubiertos, stack y por qué cada tecnología AWS
- [`docs/diagramas/`](docs/diagramas/) — C4 (contexto, contenedores, componentes), secuencia e infraestructura AWS — Docker, Docker Compose e integración

## Cómo ejecutar localmente

```bash
mvn spring-boot:run
```

## Cómo ejecutar con Docker

```bash
docker compose up --build
# http://localhost:8080
```

## Cómo ejecutar las pruebas

```bash
mvn test      # unit tests + Cucumber
mvn verify    # + verificación de cobertura JaCoCo (100% LINE, falla si baja)
```

## Modelo de ramificación

Elegimos GitFlow para este proyecto.

Pensamos también en GitHub Flow y en trunk-based, pero el curso dura todo el semestre y cada entrega se construye sobre la anterior. Por eso nos convenía tener una rama develop separada de main. Así main queda siempre estable, y los cambios se van integrando en develop antes de pasar a producción.

Otra cosa que pesó en la decisión fue poder manejar imprevistos sin frenar el resto del trabajo. Si algo falla en la versión ya entregada, queremos poder corregirlo aparte, sin que eso choque con lo que se está desarrollando en paralelo.

## Uso de Inteligencia Artificial

Se utilizó IA (Claude) como apoyo para entender la estructura del proyecto, nos guia en los 
comandos de Git y GitHub, y pediamos que nos explicara el funcionamiento de cada línea de código que realizabamos, con el fin de reforzar nuestros conocimientos. Las redacciones finales sobre el README fueron hechas por el equipo.

## Buenas practicas

## Commits 
Usamos este formato para los mensajes

    Feat: cuando agregamos algo nuevo
    fix: cuando corregimos algun error
    docs: solo cambios de documentacion
    chore: cambios de configuracion o mantenimiento

Ejemplos:

    docs: agregar changelogs
    fix: corregir typo en readme

## Nombre de las ramas

    Main: Rama de produccion
    develop: Donde se integran los features
    feature: para las nuevas funcionalidades
    hotfix:  para correciones urgentes del main

## Reflexion Felipe Veliz

En este trabajo logre comprender mas las funcionalidades de git y aprender un poco mas de los comandos basicos como  un git commit  guardar los cambios con git push y unir las ramas con git merge antes la usaba sin saber para que servian pero con este trabajo pude entender del porque el uso de ellas

## Reflexion Ignacio Gonzalez

Durante el proyecto logré comprender mejor las funcionalidades de git y los diferentes tipos de comandos, los cuales fuimos profundizando y, a su vez, aprendiendo para qué sirven. Esto también sirvió para empezar a trabajar en equipo y tener una mejor comunicación al respecto. Tuve varios errores de sintaxis, pero se fueron corrigiendo mediante la práctica que conllevaba el trabajo. En lo personal, entender la diferencia entre las distintas ramas que hay, como por ejemplo develop y las ramas feature, fue lo que más trabajo me costó al principio de entender.