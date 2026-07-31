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

int px_coolprop_calculate_co2_n2(
    double pressure_pa,
    double temperature_k,
    double carbon_dioxide_mole_fraction,
    double nitrogen_mole_fraction,
    PXCoolPropBinaryResult *result,
    char *error_buffer,
    size_t error_buffer_size
) {
    if (result == nullptr) {
        copy_text("Binary-result pointer is null.", error_buffer, error_buffer_size);
        return 1;
    }
    if (!std::isfinite(pressure_pa) || !std::isfinite(temperature_k)
        || pressure_pa <= 0 || temperature_k <= 0
        || !std::isfinite(carbon_dioxide_mole_fraction)
        || !std::isfinite(nitrogen_mole_fraction)) {
        copy_text("Pressure, temperature, and mole fractions must be finite and positive.", error_buffer, error_buffer_size);
        return 2;
    }
    if (carbon_dioxide_mole_fraction <= 0.5
        || nitrogen_mole_fraction <= 0
        || nitrogen_mole_fraction > 0.10
        || std::abs(carbon_dioxide_mole_fraction + nitrogen_mole_fraction - 1.0) > 1e-10) {
        copy_text("The binary spike requires CO2 as the largest component, 0 < N2 <= 0.10, and mole fractions summing to one.", error_buffer, error_buffer_size);
        return 3;
    }

    try {
        char fluid[192];
        const int length = std::snprintf(
            fluid,
            sizeof(fluid),
            "HEOS::CarbonDioxide[%.17g]&Nitrogen[%.17g]",
            carbon_dioxide_mole_fraction,
            nitrogen_mole_fraction
        );
        if (length <= 0 || static_cast<size_t>(length) >= sizeof(fluid)) {
            copy_text("Could not construct the bounded CO2-N2 mixture identifier.", error_buffer, error_buffer_size);
            return 4;
        }

        // PropsSI resolves the CarbonDioxide-Nitrogen pair already present in
        // CoolProp 8.0.0. This bridge never calls apply_simple_mixing_rule or
        // mutates binary interaction parameters.
        const double density = CoolProp::PropsSI(
            "Dmass", "P", pressure_pa, "T", temperature_k, fluid
        );
        const std::string phase = CoolProp::PhaseSI(
            "P", pressure_pa, "T", temperature_k, fluid
        );

        if (!std::isfinite(density) || density <= 0) {
            copy_text("CoolProp returned a non-finite or non-positive binary-mixture density.", error_buffer, error_buffer_size);
            return 5;
        }

        result->density_kg_m3 = density;
        result->phase = map_phase(phase);
        copy_text("", error_buffer, error_buffer_size);
        return 0;
    } catch (const std::exception &error) {
        copy_text(error.what(), error_buffer, error_buffer_size);
        return 6;
    } catch (...) {
        copy_text("CoolProp CO2-N2 calculation failed with an unknown native exception.", error_buffer, error_buffer_size);
        return 7;
    }
}

int px_coolprop_pure_co2_saturation_limits(
    PXCoolPropSaturationLimits *limits,
    char *error_buffer,
    size_t error_buffer_size
) {
    if (limits == nullptr) {
        copy_text("Saturation-limits pointer is null.", error_buffer, error_buffer_size);
        return 1;
    }

    try {
        const double triple_temperature = CoolProp::PropsSI(
            "Ttriple", "", 0, "", 0, kFluid
        );
        const double critical_temperature = CoolProp::PropsSI(
            "Tcrit", "", 0, "", 0, kFluid
        );
        const double critical_pressure = CoolProp::PropsSI(
            "pcrit", "", 0, "", 0, kFluid
        );

        if (!std::isfinite(triple_temperature) || triple_temperature <= 0
            || !std::isfinite(critical_temperature)
            || critical_temperature <= triple_temperature
            || !std::isfinite(critical_pressure) || critical_pressure <= 0) {
            copy_text("CoolProp returned invalid pure-CO2 saturation limits.", error_buffer, error_buffer_size);
            return 2;
        }

        limits->triple_temperature_k = triple_temperature;
        limits->critical_temperature_k = critical_temperature;
        limits->critical_pressure_pa = critical_pressure;
        copy_text("", error_buffer, error_buffer_size);
        return 0;
    } catch (const std::exception &error) {
        copy_text(error.what(), error_buffer, error_buffer_size);
        return 3;
    } catch (...) {
        copy_text("CoolProp saturation limits failed with an unknown native exception.", error_buffer, error_buffer_size);
        return 4;
    }
}

int px_coolprop_pure_co2_saturation_pressure(
    double temperature_k,
    double *pressure_pa,
    char *error_buffer,
    size_t error_buffer_size
) {
    if (pressure_pa == nullptr) {
        copy_text("Saturation-pressure pointer is null.", error_buffer, error_buffer_size);
        return 1;
    }
    if (!std::isfinite(temperature_k) || temperature_k <= 0) {
        copy_text("Saturation temperature must be finite and positive.", error_buffer, error_buffer_size);
        return 2;
    }

    try {
        const double pressure = CoolProp::PropsSI(
            "P", "T", temperature_k, "Q", 0, kFluid
        );
        if (!std::isfinite(pressure) || pressure <= 0) {
            copy_text("CoolProp returned invalid pure-CO2 saturation pressure.", error_buffer, error_buffer_size);
            return 3;
        }
        *pressure_pa = pressure;
        copy_text("", error_buffer, error_buffer_size);
        return 0;
    } catch (const std::exception &error) {
        copy_text(error.what(), error_buffer, error_buffer_size);
        return 4;
    } catch (...) {
        copy_text("CoolProp saturation calculation failed with an unknown native exception.", error_buffer, error_buffer_size);
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
