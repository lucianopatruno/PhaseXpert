#include "PhaseXpertCoolPropBridge.h"

#include "CoolProp.h"

#include <cmath>
#include <cstdio>
#include <cstring>
#include <exception>
#include <string>

namespace {

constexpr const char *kFluid = "HEOS::CarbonDioxide";

void copy_text(const std::string &text, char *buffer, size_t buffer_size) {
    if (buffer == nullptr || buffer_size == 0) {
        return;
    }
    std::snprintf(buffer, buffer_size, "%s", text.c_str());
}

PXCoolPropPhase map_phase(const std::string &phase) {
    if (phase == "gas" || phase == "supercritical_gas") {
        return PXCoolPropPhaseGas;
    }
    if (phase == "liquid") {
        return PXCoolPropPhaseLiquid;
    }
    if (phase == "supercritical_liquid") {
        return PXCoolPropPhaseDense;
    }
    if (phase == "supercritical" || phase == "critical_point") {
        return PXCoolPropPhaseSupercritical;
    }
    if (phase == "twophase") {
        return PXCoolPropPhaseTwoPhase;
    }
    if (phase == "solid") {
        return PXCoolPropPhaseSolid;
    }
    return PXCoolPropPhaseUnknown;
}

}  // namespace

int px_coolprop_calculate_pure_co2(
    double pressure_pa,
    double temperature_k,
    PXCoolPropResult *result,
    char *error_buffer,
    size_t error_buffer_size
) {
    if (result == nullptr) {
        copy_text("Result pointer is null.", error_buffer, error_buffer_size);
        return 1;
    }
    if (!std::isfinite(pressure_pa) || !std::isfinite(temperature_k)
        || pressure_pa <= 0 || temperature_k <= 0) {
        copy_text("Pressure and temperature must be finite and positive.", error_buffer, error_buffer_size);
        return 2;
    }

    try {
        const double density = CoolProp::PropsSI(
            "Dmass", "P", pressure_pa, "T", temperature_k, kFluid
        );
        const double viscosity = CoolProp::PropsSI(
            "VISCOSITY", "P", pressure_pa, "T", temperature_k, kFluid
        );
        const std::string phase = CoolProp::PhaseSI(
            "P", pressure_pa, "T", temperature_k, kFluid
        );

        if (!std::isfinite(density) || density <= 0
            || !std::isfinite(viscosity) || viscosity <= 0) {
            copy_text("CoolProp returned a non-finite or non-positive property.", error_buffer, error_buffer_size);
            return 3;
        }

        result->density_kg_m3 = density;
        result->dynamic_viscosity_pa_s = viscosity;
        result->phase = map_phase(phase);
        copy_text("", error_buffer, error_buffer_size);
        return 0;
    } catch (const std::exception &error) {
        copy_text(error.what(), error_buffer, error_buffer_size);
        return 4;
    } catch (...) {
        copy_text("CoolProp failed with an unknown native exception.", error_buffer, error_buffer_size);
        return 5;
    }
}

int px_coolprop_copy_version(
    char *version_buffer,
    size_t version_buffer_size
) {
    if (version_buffer == nullptr || version_buffer_size == 0) {
        return 1;
    }
    try {
        copy_text(
            CoolProp::get_global_param_string("version"),
            version_buffer,
            version_buffer_size
        );
        return 0;
    } catch (...) {
        copy_text("Unknown", version_buffer, version_buffer_size);
        return 2;
    }
}
