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

/// Returns zero on success. On failure, writes a diagnostic to `error_buffer`.
int px_coolprop_calculate_pure_co2(
    double pressure_pa,
    double temperature_k,
    PXCoolPropResult *result,
    char *error_buffer,
    size_t error_buffer_size
);

/// Calculates the restricted CO2-N2 binary state using only the interaction
/// data shipped by the pinned CoolProp release. No estimated mixing rule is
/// applied. Nitrogen is temporarily capped at 10 mol% for this spike.
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

typedef enum PXCoolPropEnvelopeBranch {
    PXCoolPropEnvelopeBranchBubble = 0,
    PXCoolPropEnvelopeBranchDew = 1,
    PXCoolPropEnvelopeBranchCritical = 2
} PXCoolPropEnvelopeBranch;

typedef struct PXCoolPropEnvelopePoint {
    double temperature_k;
    double pressure_pa;
    PXCoolPropEnvelopeBranch branch;
} PXCoolPropEnvelopePoint;

typedef struct PXCoolPropEnvelopeSummary {
    size_t point_count;
    int is_closed;
    double maximum_temperature_k;
    double maximum_pressure_pa;
} PXCoolPropEnvelopeSummary;

/// Builds the restricted CO2-N2 HEOS phase envelope using the binary
/// interaction data shipped by the pinned CoolProp release. No estimated
/// mixing rule is applied. The caller supplies storage for every returned
/// point; insufficient capacity is an explicit failure.
int px_coolprop_co2_n2_phase_envelope(
    double carbon_dioxide_mole_fraction,
    double nitrogen_mole_fraction,
    PXCoolPropEnvelopePoint *points,
    size_t point_capacity,
    PXCoolPropEnvelopeSummary *summary,
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
