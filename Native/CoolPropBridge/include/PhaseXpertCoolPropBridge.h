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
    double density_mol_m3;
    double reducing_density_mol_m3;
    double gibbs_molar_j_mol;
    PXCoolPropPhase phase;
} PXCoolPropBinaryResult;

typedef enum PXCoolPropPhaseHint {
    PXCoolPropPhaseHintNone = 0,
    PXCoolPropPhaseHintGas = 1,
    PXCoolPropPhaseHintLiquid = 2
} PXCoolPropPhaseHint;

typedef struct PXCoolPropMixtureSaturationPressures {
    double bubble_pressure_pa;
    double dew_pressure_pa;
} PXCoolPropMixtureSaturationPressures;

typedef struct PXCoolPropSaturationLimits {
    double triple_temperature_k;
    double critical_temperature_k;
    double critical_pressure_pa;
} PXCoolPropSaturationLimits;

typedef enum PXCoolPropEnvelopeBranch {
    PXCoolPropEnvelopeBubble = 0,
    PXCoolPropEnvelopeDew = 1,
    PXCoolPropEnvelopeCritical = 2
} PXCoolPropEnvelopeBranch;

typedef struct PXCoolPropEnvelopePoint {
    double temperature_k;
    double pressure_pa;
    PXCoolPropEnvelopeBranch branch;
} PXCoolPropEnvelopePoint;

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
/// Fractions are ordered CO2, N2, O2, Ar, CH4, H2, CO and H2S. Total impurity
/// is temporarily capped at 10 mol%; this product guardrail is not an accuracy
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
    double carbon_monoxide_mole_fraction,
    double hydrogen_sulfide_mole_fraction,
    PXCoolPropBinaryResult *result,
    char *error_buffer,
    size_t error_buffer_size
);

/// Calculates a restricted dry CO2-rich state with an imposed single-phase
/// hint. Intended for Phase Map points that have first been classified outside
/// the CoolProp bubble/dew interval at the same temperature. No estimated
/// mixing rule is applied.
int px_coolprop_calculate_dry_co2_mixture_with_phase_hint(
    double pressure_pa,
    double temperature_k,
    double carbon_dioxide_mole_fraction,
    double nitrogen_mole_fraction,
    double oxygen_mole_fraction,
    double argon_mole_fraction,
    double methane_mole_fraction,
    double hydrogen_mole_fraction,
    double carbon_monoxide_mole_fraction,
    double hydrogen_sulfide_mole_fraction,
    PXCoolPropPhaseHint phase_hint,
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

/// Returns CoolProp bubble and dew pressures at a fixed temperature for the
/// restricted dry CO2-rich mixture. Fractions use the same order and guardrail
/// as the state calculation.
int px_coolprop_dry_co2_mixture_saturation_pressures(
    double temperature_k,
    double carbon_dioxide_mole_fraction,
    double nitrogen_mole_fraction,
    double oxygen_mole_fraction,
    double argon_mole_fraction,
    double methane_mole_fraction,
    double hydrogen_mole_fraction,
    double carbon_monoxide_mole_fraction,
    double hydrogen_sulfide_mole_fraction,
    PXCoolPropMixtureSaturationPressures *pressures,
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

/// Builds the real HEOS phase envelope for a supported dry CO2-rich mixture.
/// Fractions use the same order and product guardrail as the state calculation.
/// No estimated mixing rule or interpolated scientific point is introduced.
/// Continuation starts at the PhaseXpert domain minimum of 80000 Pa, requests
/// no optional refinement, and is capped by the tracked PhaseXpert CoolProp
/// source patch at 256 successfully calculated provider steps. Reaching the cap
/// leaves `is_complete` and `is_closed` zero while preserving returned points.
/// A nonzero `is_complete` means CoolProp reached its native exit condition;
/// `is_closed` separately reports CoolProp's pressure-closure condition.
int px_coolprop_dry_co2_mixture_phase_envelope(
    double carbon_dioxide_mole_fraction,
    double nitrogen_mole_fraction,
    double oxygen_mole_fraction,
    double argon_mole_fraction,
    double methane_mole_fraction,
    double hydrogen_mole_fraction,
    double carbon_monoxide_mole_fraction,
    double hydrogen_sulfide_mole_fraction,
    PXCoolPropEnvelopePoint *points,
    size_t point_capacity,
    size_t *point_count,
    int *is_complete,
    int *is_closed,
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
