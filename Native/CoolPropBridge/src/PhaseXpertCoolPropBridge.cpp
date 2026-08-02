#include "PhaseXpertCoolPropBridge.h"

#include "CoolProp/AbstractState.h"
#include "CoolProp/CoolProp.h"

#include <array>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <exception>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

constexpr const char *kFluid = "HEOS::CarbonDioxide";
constexpr double kPhaseEnvelopeMinimumPressurePa = 80000.0;
constexpr double kPhaseEnvelopeMaximumPressurePa = 30000000.0;
constexpr size_t kPhaseEnvelopePressureSampleCount = 80;

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
        std::shared_ptr<CoolProp::AbstractState> state(
            CoolProp::AbstractState::factory("HEOS", "CarbonDioxide")
        );
        state->update(CoolProp::PT_INPUTS, pressure_pa, temperature_k);

        const double density = state->rhomass();
        const double viscosity = state->viscosity();
        const double enthalpy = state->hmass();
        const double entropy = state->smass();
        const double internal_energy = state->umass();
        const double isobaric_heat_capacity = state->cpmass();
        const double isochoric_heat_capacity = state->cvmass();
        const double speed_of_sound = state->speed_sound();
        const double thermal_conductivity = state->conductivity();
        const double joule_thomson = state->first_partial_deriv(
            CoolProp::iT,
            CoolProp::iP,
            CoolProp::iHmass
        );
        const std::string phase = CoolProp::PhaseSI(
            "P", pressure_pa, "T", temperature_k, kFluid
        );

        const bool invalid_positive_property =
            !std::isfinite(density) || density <= 0
            || !std::isfinite(viscosity) || viscosity <= 0
            || !std::isfinite(isobaric_heat_capacity) || isobaric_heat_capacity <= 0
            || !std::isfinite(isochoric_heat_capacity) || isochoric_heat_capacity <= 0
            || !std::isfinite(speed_of_sound) || speed_of_sound <= 0
            || !std::isfinite(thermal_conductivity) || thermal_conductivity <= 0;
        const bool invalid_signed_property =
            !std::isfinite(enthalpy)
            || !std::isfinite(entropy)
            || !std::isfinite(internal_energy)
            || !std::isfinite(joule_thomson);

        if (invalid_positive_property || invalid_signed_property) {
            copy_text("CoolProp returned an invalid pure-CO2 property.", error_buffer, error_buffer_size);
            return 3;
        }

        result->density_kg_m3 = density;
        result->dynamic_viscosity_pa_s = viscosity;
        result->enthalpy_j_kg = enthalpy;
        result->entropy_j_kg_k = entropy;
        result->internal_energy_j_kg = internal_energy;
        result->isobaric_heat_capacity_j_kg_k = isobaric_heat_capacity;
        result->isochoric_heat_capacity_j_kg_k = isochoric_heat_capacity;
        result->speed_of_sound_m_s = speed_of_sound;
        result->thermal_conductivity_w_m_k = thermal_conductivity;
        result->joule_thomson_k_pa = joule_thomson;
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

int px_coolprop_calculate_dry_co2_mixture(
    double pressure_pa,
    double temperature_k,
    double carbon_dioxide_mole_fraction,
    double nitrogen_mole_fraction,
    double oxygen_mole_fraction,
    double argon_mole_fraction,
    double methane_mole_fraction,
    double hydrogen_mole_fraction,
    PXCoolPropBinaryResult *result,
    char *error_buffer,
    size_t error_buffer_size
) {
    if (result == nullptr) {
        copy_text("Mixture-result pointer is null.", error_buffer, error_buffer_size);
        return 1;
    }

    const std::array<double, 6> fractions = {
        carbon_dioxide_mole_fraction,
        nitrogen_mole_fraction,
        oxygen_mole_fraction,
        argon_mole_fraction,
        methane_mole_fraction,
        hydrogen_mole_fraction
    };
    if (!std::isfinite(pressure_pa) || !std::isfinite(temperature_k)
        || pressure_pa <= 0 || temperature_k <= 0) {
        copy_text("Pressure and temperature must be finite and positive.", error_buffer, error_buffer_size);
        return 2;
    }
    double total = 0;
    for (const double fraction : fractions) {
        if (!std::isfinite(fraction) || fraction < 0) {
            copy_text("Mole fractions must be finite and non-negative.", error_buffer, error_buffer_size);
            return 3;
        }
        total += fraction;
    }
    const double total_impurity = 1.0 - carbon_dioxide_mole_fraction;
    bool carbon_dioxide_is_unique_largest = carbon_dioxide_mole_fraction > 0;
    for (size_t index = 1; index < fractions.size(); ++index) {
        carbon_dioxide_is_unique_largest =
            carbon_dioxide_is_unique_largest
            && carbon_dioxide_mole_fraction > fractions[index];
    }
    if (std::abs(total - 1.0) > 1e-10
        || total_impurity <= 0
        || total_impurity > 0.10 + 1e-12
        || !carbon_dioxide_is_unique_largest) {
        copy_text(
            "Dry mixtures require CO2 as the unique largest component, total impurity in (0, 0.10], and fractions summing to one.",
            error_buffer,
            error_buffer_size
        );
        return 4;
    }

    try {
        constexpr std::array<const char *, 6> names = {
            "CarbonDioxide", "Nitrogen", "Oxygen", "Argon", "Methane", "Hydrogen"
        };
        std::string fluid = "HEOS::";
        bool first = true;
        char component[96];
        for (size_t index = 0; index < fractions.size(); ++index) {
            if (fractions[index] <= 1e-14) {
                continue;
            }
            const int length = std::snprintf(
                component,
                sizeof(component),
                "%s%s[%.17g]",
                first ? "" : "&",
                names[index],
                fractions[index]
            );
            if (length <= 0 || static_cast<size_t>(length) >= sizeof(component)) {
                copy_text("Could not construct the bounded dry-mixture identifier.", error_buffer, error_buffer_size);
                return 5;
            }
            fluid += component;
            first = false;
        }

        // CoolProp resolves only interaction entries shipped in version 8.0.0.
        // This bridge never calls apply_simple_mixing_rule and never mutates
        // binary interaction parameters.
        const double density = CoolProp::PropsSI(
            "Dmass", "P", pressure_pa, "T", temperature_k, fluid
        );
        const std::string phase = CoolProp::PhaseSI(
            "P", pressure_pa, "T", temperature_k, fluid
        );
        if (!std::isfinite(density) || density <= 0) {
            copy_text("CoolProp returned an invalid dry-mixture density.", error_buffer, error_buffer_size);
            return 6;
        }

        result->density_kg_m3 = density;
        result->phase = map_phase(phase);
        copy_text("", error_buffer, error_buffer_size);
        return 0;
    } catch (const std::exception &error) {
        copy_text(error.what(), error_buffer, error_buffer_size);
        return 7;
    } catch (...) {
        copy_text("CoolProp dry-mixture calculation failed with an unknown native exception.", error_buffer, error_buffer_size);
        return 8;
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
    return px_coolprop_calculate_dry_co2_mixture(
        pressure_pa,
        temperature_k,
        carbon_dioxide_mole_fraction,
        nitrogen_mole_fraction,
        0,
        0,
        0,
        0,
        result,
        error_buffer,
        error_buffer_size
    );
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

int px_coolprop_dry_co2_mixture_phase_envelope(
    double carbon_dioxide_mole_fraction,
    double nitrogen_mole_fraction,
    double oxygen_mole_fraction,
    double argon_mole_fraction,
    double methane_mole_fraction,
    double hydrogen_mole_fraction,
    PXCoolPropEnvelopePoint *points,
    size_t point_capacity,
    size_t *point_count,
    size_t *attempted_point_count,
    size_t *failed_point_count,
    int *is_complete,
    int *is_closed,
    char *error_buffer,
    size_t error_buffer_size
) {
    if (points == nullptr || point_count == nullptr
        || attempted_point_count == nullptr || failed_point_count == nullptr
        || is_complete == nullptr || is_closed == nullptr
        || point_capacity == 0) {
        copy_text("Phase-envelope output buffer is invalid.", error_buffer, error_buffer_size);
        return 1;
    }
    *point_count = 0;
    *attempted_point_count = 0;
    *failed_point_count = 0;
    *is_complete = 0;
    *is_closed = 0;

    const std::array<double, 6> fractions = {
        carbon_dioxide_mole_fraction,
        nitrogen_mole_fraction,
        oxygen_mole_fraction,
        argon_mole_fraction,
        methane_mole_fraction,
        hydrogen_mole_fraction
    };
    double total = 0;
    for (const double fraction : fractions) {
        if (!std::isfinite(fraction) || fraction < 0) {
            copy_text("Mole fractions must be finite and non-negative.", error_buffer, error_buffer_size);
            return 2;
        }
        total += fraction;
    }
    const double total_impurity = 1.0 - carbon_dioxide_mole_fraction;
    bool carbon_dioxide_is_unique_largest = carbon_dioxide_mole_fraction > 0;
    for (size_t index = 1; index < fractions.size(); ++index) {
        carbon_dioxide_is_unique_largest = carbon_dioxide_is_unique_largest
            && carbon_dioxide_mole_fraction > fractions[index];
    }
    if (std::abs(total - 1.0) > 1e-10
        || total_impurity <= 0
        || total_impurity > 0.10 + 1e-12
        || !carbon_dioxide_is_unique_largest) {
        copy_text(
            "Dry-mixture phase envelopes require total impurity in (0, 0.10] and fractions summing to one.",
            error_buffer,
            error_buffer_size
        );
        return 3;
    }

    try {
        constexpr std::array<const char *, 6> names = {
            "CarbonDioxide", "Nitrogen", "Oxygen", "Argon", "Methane", "Hydrogen"
        };
        std::vector<std::string> active_names;
        std::vector<double> active_fractions;
        for (size_t index = 0; index < fractions.size(); ++index) {
            if (fractions[index] > 1e-14) {
                active_names.emplace_back(names[index]);
                active_fractions.push_back(fractions[index]);
            }
        }
        std::string fluids;
        for (size_t index = 0; index < active_names.size(); ++index) {
            if (index > 0) {
                fluids += "&";
            }
            fluids += active_names[index];
        }

        size_t output_index = 0;
        const double logarithmic_span = std::log(
            kPhaseEnvelopeMaximumPressurePa
            / kPhaseEnvelopeMinimumPressurePa
        );

        const auto sample_branch = [&](
            double quality,
            PXCoolPropEnvelopeBranch branch
        ) -> size_t {
            size_t branch_point_count = 0;
            bool branch_started = false;
            for (size_t sample_index = 0;
                 sample_index < kPhaseEnvelopePressureSampleCount;
                 ++sample_index) {
                const double fraction = static_cast<double>(sample_index)
                    / static_cast<double>(kPhaseEnvelopePressureSampleCount - 1);
                const double pressure_pa = kPhaseEnvelopeMinimumPressurePa
                    * std::exp(logarithmic_span * fraction);
                ++(*attempted_point_count);

                try {
                    // A fresh state makes every bounded provider flash
                    // independent of any failed preceding pressure.
                    std::shared_ptr<CoolProp::AbstractState> state(
                        CoolProp::AbstractState::factory("HEOS", fluids)
                    );
                    state->set_mole_fractions(active_fractions);
                    state->update(CoolProp::PQ_INPUTS, pressure_pa, quality);
                    const double temperature_k = state->T();
                    const double returned_pressure_pa = state->p();
                    if (!std::isfinite(temperature_k) || temperature_k <= 0
                        || !std::isfinite(returned_pressure_pa)
                        || returned_pressure_pa <= 0) {
                        throw std::runtime_error(
                            "CoolProp returned a non-finite bubble/dew state."
                        );
                    }
                    if (output_index >= point_capacity) {
                        throw std::runtime_error(
                            "CoolProp phase boundary exceeds the bounded output capacity."
                        );
                    }
                    points[output_index].temperature_k = temperature_k;
                    points[output_index].pressure_pa = returned_pressure_pa;
                    points[output_index].branch = branch;
                    ++output_index;
                    ++branch_point_count;
                    branch_started = true;
                } catch (...) {
                    ++(*failed_point_count);
                    if (branch_started) {
                        // Stop rather than bridge a failed scientific point.
                        break;
                    }
                }
            }
            return branch_point_count;
        };

        const size_t bubble_point_count = sample_branch(
            0.0,
            PXCoolPropEnvelopeBubble
        );
        const size_t dew_point_count = sample_branch(
            1.0,
            PXCoolPropEnvelopeDew
        );
        if (bubble_point_count < 2 || dew_point_count < 2) {
            copy_text(
                "CoolProp did not return at least two bounded provider points for both bubble and dew branches.",
                error_buffer,
                error_buffer_size
            );
            return 4;
        }

        *point_count = output_index;
        *is_complete = 1;
        // Pointwise sampling never infers a geometric closure or critical point.
        *is_closed = 0;
        copy_text("", error_buffer, error_buffer_size);
        return 0;
    } catch (const std::exception &error) {
        copy_text(error.what(), error_buffer, error_buffer_size);
        return 7;
    } catch (...) {
        copy_text("CoolProp mixture phase-boundary sampling failed with an unknown native exception.", error_buffer, error_buffer_size);
        return 8;
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
