# language: es
Característica: Servicio Recomendaciones (microservicio recomendaciones del caso caso03)
  Los escenarios validan el contrato REST del microservicio alineado a sus endpoints.

  Escenario: el listado del recurso responde 200
    Dado el servicio "Recomendaciones" está disponible
    Cuando consulto el listado de "recomendaciones"
    Entonces el listado responde con código 200

  Escenario: ciclo de vida completo del recurso
    Dado un nuevo "recomendacion" con nombre "hola-cucumber"
    Cuando consulto el "recomendacion" recién creado
    Entonces el recurso tiene nombre "hola-cucumber" y código 200
    Cuando actualizo el "recomendacion" con nombre "cucumber-actualizado"
    Entonces el recurso queda con nombre "cucumber-actualizado" y código 200
    Cuando elimino el "recomendacion"
    Entonces la eliminación responde con código 204
    Y al consultar el "recomendacion" eliminado responde 404
