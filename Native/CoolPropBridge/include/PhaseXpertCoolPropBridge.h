#ifndef PHASEXPERT_COOLPROP_BRIDGE_H
#define PHASEXPERT_COOLPROP_BRIDGE_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum PXCoolPropPhase {
    PXCoolPropPhaseUnknown = 0,
    PXCoolPropPhaseGas = 1,
    PXCoolPropPhaseLiquid = 2,
    PXCoolPropPhaseDense = 3,
    PXCoolPropPhaseSupercritical = 4,
    PXCoolPropPhaseTwoPhase = 5,
    PXCoolPropPhaseSolid = 6
} PXCoolPropPhase;

typedef struct PXCoolPropResult {
    double density_kg_m3;
    double dynamic_viscosity_pa_s;
    double enthalpy_j_kg;
    double entropy_j_kg_k;
    double internal_energy_j_kg;
    double isobaric_heat_capacity_j_kg_k;
    double isochoric_heat_capacity_j_kg_k;
    double speed_of_sound_m_s;
    double thermal_conductivity_w_m_k;
    double joule_thomson_k_pa;
    PXCoolPropPhase phase;
} PXCoolPropResult;

typedef struct PXCoolPropBinaryResult {
    double density_kg_m3;
    PXCoolPropPhase phase;
} PXCoolPropBinaryResult;

typedef struct PXCoolPropSaturationLimits {
    double triple_temperature_k;
    double critical_temperature_k;
    double critical_pressure_pa;
} PXCoolPropSaturationLimits;

/// Calculates the pure-CO2 state using one HEOS state update. Returned caloric,
/// acoustic, transport and derivative values use SI units. Enthalpy, entropy,
/// internal energy and the Joule-Thomson coefficient may be negative; all
/// other numeric outputs must be finite and positive.
/// Returns zero on success. On failure, writes a diagnostic to `error_buffer`.
int px_coolprop_calculate_pure_co2(
    double pressure_pa,
    double temperature_k,
    PXCoolPropResult *result,
    char *error_buffer,
    size_t error_buffer_size
);

/// Calculates a restricted dry CO2-rich state using only interaction entries
/// shipped by the pinned CoolProp release. No estimated mixing rule is applied.
/// Fractions are ordered CO2, N2, O2, Ar, CH4 and H2. Total impurity is
/// temporarily capped at 10 mol%; this product guardrail is not an accuracy
/// or validation claim.
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
);

/// Backwards-compatible entry point for the restricted CO2-N2 subset.
int px_coolprop_calculate_co2_n2(
    double pressure_pa,
    double temperature_k,
    double carbon_dioxide_mole_fraction,
    double nitrogen_mole_fraction,
    PXCoolPropBinaryResult *result,
    char *error_buffer,
    size_t error_buffer_size
);

/// Returns the pure-CO2 saturation temperature limits and critical pressure.
int px_coolprop_pure_co2_saturation_limits(
    PXCoolPropSaturationLimits *limits,
    char *error_buffer,
    size_t error_buffer_size
);

/// Returns pure-CO2 saturation pressure at temperature using HEOS and Q=0.
int px_coolprop_pure_co2_saturation_pressure(
    double temperature_k,
    double *pressure_pa,
    char *error_buffer,
    size_t error_buffer_size
);

/// Copies the linked CoolProp version into `version_buffer`.
int px_coolprop_copy_version(
    char *version_buffer,
    size_t version_buffer_size
);

#ifdef __cplusplus
}
#endif

#endif
