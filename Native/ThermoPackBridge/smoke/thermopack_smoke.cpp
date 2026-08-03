#include "PhaseXpertThermoPackBridge.h"

#include <cmath>

namespace {
bool valid_state(double co2, double n2, double pressure, double temperature) {
    PXThermoPackState state{};
    char error[PX_THERMOPACK_ERROR_CAPACITY] = {};
    const int status = px_thermopack_state(
        pressure, temperature, co2, n2, &state, error, sizeof(error)
    );
    if (status != 0 || state.is_two_phase != 0) return false;
    return std::isfinite(state.density_kg_m3) && state.density_kg_m3 > 0
        && std::isfinite(state.compressibility_factor)
        && state.compressibility_factor > 0;
}

bool valid_envelope(double co2, double n2) {
    PXThermoPackEnvelope envelope{};
    char error[PX_THERMOPACK_ERROR_CAPACITY] = {};
    const int status = px_thermopack_envelope(
        co2, n2, 218.15, 423.15, 80000.0, 30000000.0,
        64, 5000.0, &envelope, error, sizeof(error)
    );
    if (status != 0 || envelope.bubble_count < 2 || envelope.dew_count < 2) {
        return false;
    }
    for (int index = 0; index < envelope.point_count; ++index) {
        PXThermoPackEnvelopePoint point{};
        if (px_thermopack_envelope_point(&envelope, index, &point) != 0
            || !std::isfinite(point.temperature_k)
            || !std::isfinite(point.pressure_pa)) {
            return false;
        }
    }
    return true;
}
}

int main() {
    const double compositions[][2] = {
        {1.00, 0.00},
        {0.97, 0.03},
        {0.90, 0.10}
    };
    for (const auto &composition : compositions) {
        if (!valid_state(composition[0], composition[1], 1000000.0, 293.15)
            || !valid_state(composition[0], composition[1], 15000000.0, 293.15)
            || !valid_envelope(composition[0], composition[1])) {
            return 1;
        }
    }
    return 0;
}
