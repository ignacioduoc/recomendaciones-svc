package cl.duoc.jv0101.caso03.recomendaciones.repository;

import org.springframework.data.jpa.repository.JpaRepository;
import cl.duoc.jv0101.caso03.recomendaciones.model.Recomendacion;

public interface RecomendacionRepository extends JpaRepository<Recomendacion, Long> {
}
