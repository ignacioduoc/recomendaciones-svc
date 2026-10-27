package cl.duoc.jv0101.caso03.recomendaciones;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Casos críticos de operación: Kubernetes usa liveness/readiness para decidir
 * si reinicia un pod o le envía tráfico, y el pipeline usa /actuator/info
 * para comprobar qué commit quedó desplegado.
 */
@SpringBootTest(properties = "APP_COMMIT=abc1234")
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
