package cl.duoc.jv0101.caso03.recomendaciones.service;

import java.util.List;
import java.util.Optional;
import org.springframework.stereotype.Service;
import cl.duoc.jv0101.caso03.recomendaciones.model.Recomendacion;
import cl.duoc.jv0101.caso03.recomendaciones.repository.RecomendacionRepository;

@Service
public class RecomendacionService {

    private final RecomendacionRepository repository;

    public RecomendacionService(RecomendacionRepository repository) {
        this.repository = repository;
    }

    public List<Recomendacion> findAll() {
        return repository.findAll();
    }

    public Optional<Recomendacion> findById(Long id) {
        return repository.findById(id);
    }

    public Recomendacion create(Recomendacion recurso) {
        return repository.save(recurso);
    }

    public Optional<Recomendacion> update(Long id, Recomendacion datos) {
        return repository.findById(id).map(existente -> {
            existente.setNombre(datos.getNombre());
            existente.setContenido(datos.getContenido());
            existente.setScore(datos.getScore());
            return repository.save(existente);
        });
    }

    public boolean delete(Long id) {
        return repository.findById(id).map(existente -> {
            repository.delete(existente);
            return true;
        }).orElse(false);
    }
}
