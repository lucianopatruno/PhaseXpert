#ifndef PhaseXpertThermoPackBridge_h
#define PhaseXpertThermoPackBridge_h

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PX_THERMOPACK_MAX_POINTS 192
#define PX_THERMOPACK_ERROR_CAPACITY 512

typedef struct {
    double density_kg_m3;
    double molar_mass_kg_mol;
    double specific_volume_m3_kg;
    double compressibility_factor;
    double enthalpy_j_kg;
    double entropy_j_kg_k;
    double cp_j_kg_k;
    double vapor_fraction;
    int32_t phase;
    int32_t is_two_phase;
} PXThermoPackState;

typedef struct {
    double temperature_k;
    double pressure_pa;
    int32_t branch; /* 0 bubble, 1 dew */
} PXThermoPackEnvelopePoint;

typedef struct {
    PXThermoPackEnvelopePoint points[PX_THERMOPACK_MAX_POINTS];
    int32_t point_count;
    int32_t bubble_count;
    int32_t dew_count;
    int32_t attempted_calls;
    int32_t failed_calls;
    int32_t complete;
    int32_t timed_out;
    double elapsed_ms;
} PXThermoPackEnvelope;

const char *px_thermopack_bridge_version(void);
const char *px_thermopack_library_version(void);
const char *px_thermopack_configuration(void);

int32_t px_thermopack_state(
    double pressure_pa,
    double temperature_k,
    double carbon_dioxide_mole_fraction,
    double nitrogen_mole_fraction,
    PXThermoPackState *output,
    char *error,
    size_t error_capacity
);

int32_t px_thermopack_envelope(
    double carbon_dioxide_mole_fraction,
    double nitrogen_mole_fraction,
    double minimum_temperature_k,
    double maximum_temperature_k,
    double minimum_pressure_pa,
    double maximum_pressure_pa,
    int32_t maximum_points_per_branch,
    double maximum_elapsed_ms,
    PXThermoPackEnvelope *output,
    char *error,
    size_t error_capacity
);

int32_t px_thermopack_envelope_point(
    const PXThermoPackEnvelope *envelope,
    int32_t index,
    PXThermoPackEnvelopePoint *point
);

#ifdef __cplusplus
}
#endif
#endif
