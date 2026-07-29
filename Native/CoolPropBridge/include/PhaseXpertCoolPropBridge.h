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

/// Returns zero on success. On failure, writes a diagnostic to `error_buffer`.
int px_coolprop_calculate_pure_co2(
    double pressure_pa,
    double temperature_k,
    PXCoolPropResult *result,
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
