#ifndef PHASEXPERT_TEQP_BRIDGE_H
#define PHASEXPERT_TEQP_BRIDGE_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum PXTeqpPhase {
    PXTeqpPhaseUnknown = 0,
    PXTeqpPhaseSupercritical = 1
} PXTeqpPhase;

typedef struct PXTeqpResult {
    double density_kg_m3;
    double molar_density_mol_m3;
    int density_root_count;
    PXTeqpPhase phase;
} PXTeqpResult;

int px_teqp_calculate_pure_co2(
    double pressure_pa,
    double temperature_k,
    PXTeqpResult *result,
    char *error_buffer,
    size_t error_buffer_size
);

int px_teqp_copy_version(
    char *version_buffer,
    size_t version_buffer_size
);

#ifdef __cplusplus
}
#endif

#endif
