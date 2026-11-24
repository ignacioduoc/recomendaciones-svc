package cl.duoc.jv0101.caso03.recomendaciones;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.web.servlet.MockMvc;

import static org.hamcrest.Matchers.containsString;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Casos críticos de operación: Kubernetes usa liveness/readiness para decidir
 * si reinicia un pod o le envía tráfico, y el pipeline usa /actuator/info
 * para comprobar qué commit quedó desplegado.
 */
@SpringBootTest(properties = {
    "APP_COMMIT=abc1234",
    // En los tests Spring Boot desactiva la exportación de métricas, así que se activa para Prometheus
    "management.prometheus.metrics.export.enabled=true"
})
@AutoConfigureMockMvc
class ActuatorEndpointsTest {

    @Autowired
    private MockMvc mockMvc;

    @Test
    void livenessRespondeUp() throws Exception {
        mockMvc.perform(get("/actuator/health/liveness"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.status").value("UP"));
    }

    @Test
    void readinessRespondeUpConBaseDeDatos() throws Exception {
        mockMvc.perform(get("/actuator/health/readiness"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.status").value("UP"));
    }

    @Test
    void infoExponeElCommitDesplegado() throws Exception {
        mockMvc.perform(get("/actuator/info"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.app.commit").value("abc1234"))
            .andExpect(jsonPath("$.build.artifact").value("recomendaciones-svc"));
    }

    @Test
    void prometheusExponeMetricasDeUsoYDeErrores() throws Exception {
        // Una petición previa garantiza que exista la serie http_server_requests
        mockMvc.perform(get("/api/recomendaciones")).andExpect(status().isOk());
        mockMvc.perform(get("/actuator/prometheus"))
            .andExpect(status().isOk())
            .andExpect(content().string(containsString("jvm_memory_used_bytes")))
            .andExpect(content().string(containsString("process_cpu_usage")))
            .andExpect(content().string(containsString("http_server_requests_seconds_count")))
            .andExpect(content().string(containsString("application=\"recomendaciones-svc\"")));
    }

    @Test
    void healthNoExponeDetallesInternos() throws Exception {
        mockMvc.perform(get("/actuator/health"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.components").doesNotExist());
    }

    @Test
    void endpointsSensiblesNoEstanExpuestos() throws Exception {
        mockMvc.perform(get("/actuator/env")).andExpect(status().isNotFound());
        mockMvc.perform(get("/actuator/beans")).andExpect(status().isNotFound());
    }
}