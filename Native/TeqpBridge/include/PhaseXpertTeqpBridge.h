#ifndef PHASEXPERT_TEQP_BRIDGE_H
#define PHASEXPERT_TEQP_BRIDGE_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum PXTeqpPhase {
    PXTeqpPhaseUnknown = 0,
    PXTeqpPhaseSupercritical = 1,
    PXTeqpPhaseGas = 2,
    PXTeqpPhaseLiquid = 3,
    PXTeqpPhaseTwoPhase = 4
} PXTeqpPhase;

typedef struct PXTeqpResult {
    double density_kg_m3;
    double molar_density_mol_m3;
    double isochoric_heat_capacity_j_kg_k;
    double isobaric_heat_capacity_j_kg_k;
    double heat_capacity_ratio;
    double speed_of_sound_m_s;
    int density_root_count;
    PXTeqpPhase phase;
} PXTeqpResult;

typedef struct PXTeqpSaturationResult {
    double pressure_pa;
    double liquid_molar_density_mol_m3;
    double vapor_molar_density_mol_m3;
    double liquid_density_kg_m3;
    double vapor_density_kg_m3;
} PXTeqpSaturationResult;

typedef struct PXTeqpBinaryVLEResult {
    int converged;
    int iteration_count;
    int return_code;
    double pressure_pa;
    double liquid_molar_density_mol_m3;
    double vapor_molar_density_mol_m3;
    double liquid_co2_mole_fraction;
    double liquid_n2_mole_fraction;
    double vapor_co2_mole_fraction;
    double vapor_n2_mole_fraction;
    double pressure_residual_pa;
    double co2_chemical_potential_residual;
    double n2_chemical_potential_residual;
} PXTeqpBinaryVLEResult;

typedef enum PXTeqpBinaryFormulation {
    PXTeqpBinaryFormulationCO2N2 = 1,
    PXTeqpBinaryFormulationEOSCGCO2H2 = 2,
    PXTeqpBinaryFormulationEOSCGCO2CH4 = 3
} PXTeqpBinaryFormulation;

typedef enum PXTeqpComponentID {
    PXTeqpComponentCarbonDioxide = 1,
    PXTeqpComponentNitrogen = 2,
    PXTeqpComponentMethane = 3,
    PXTeqpComponentHydrogen = 4,
    PXTeqpComponentOxygen = 5,
    PXTeqpComponentArgon = 6,
    PXTeqpComponentCarbonMonoxide = 7,
    PXTeqpComponentHydrogenSulfide = 8,
    PXTeqpComponentWater = 9
} PXTeqpComponentID;

typedef struct PXTeqpGenericBinaryVLEResult {
    int converged;
    int iteration_count;
    int return_code;
    double pressure_pa;
    double liquid_molar_density_mol_m3;
    double vapor_molar_density_mol_m3;
    double liquid_component1_mole_fraction;
    double liquid_component2_mole_fraction;
    double vapor_component1_mole_fraction;
    double vapor_component2_mole_fraction;
    double pressure_residual_pa;
    double component1_chemical_potential_residual;
    double component2_chemical_potential_residual;
} PXTeqpGenericBinaryVLEResult;

typedef struct PXTeqpBinaryVLEInitialGuess {
    double liquid_molar_density_mol_m3;
    double vapor_molar_density_mol_m3;
    double vapor_component2_mole_fraction;
} PXTeqpBinaryVLEInitialGuess;

typedef struct PXTeqpBinaryPointResult {
    double density_kg_m3;
    double molar_density_mol_m3;
    int density_root_count;
    PXTeqpPhase phase;
    double dew_pressure_pa;
    double bubble_pressure_pa;
    int dew_converged;
    int bubble_converged;
} PXTeqpBinaryPointResult;

typedef struct PXTeqpMixtureDensityResult {
    double density_kg_m3;
    double molar_density_mol_m3;
    int density_root_count;
    PXTeqpPhase phase;
} PXTeqpMixtureDensityResult;

typedef struct PXTeqpNComponentDensityResult {
    double density_kg_m3;
    double molar_density_mol_m3;
    int density_root_count;
    int converged;
    PXTeqpPhase phase;
} PXTeqpNComponentDensityResult;

typedef struct PXTeqpMixtureThermodynamicResult {
    double density_kg_m3;
    double molar_density_mol_m3;
    double pressure_pa;
    double dp_drho_molar_j_mol;
    double dp_dt_pa_k;
    double isochoric_heat_capacity_j_kg_k;
    double isobaric_heat_capacity_j_kg_k;
    double heat_capacity_ratio;
    double speed_of_sound_m_s;
    double speed_of_sound_squared_m2_s2;
    double minimum_stability_eigenvalue;
    int density_root_count;
    int converged;
    PXTeqpPhase phase;
} PXTeqpMixtureThermodynamicResult;

typedef struct PXTeqpBinaryCriticalResult {
    int converged;
    int iteration_count;
    double temperature_k;
    double pressure_pa;
    double molar_density_mol_m3;
    double density_kg_m3;
    double component2_mole_fraction;
    double minimum_stability_eigenvalue;
    double third_order_residual;
} PXTeqpBinaryCriticalResult;

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

int px_teqp_saturation_pure_co2(
    double temperature_k,
    PXTeqpSaturationResult *result,
    char *error_buffer,
    size_t error_buffer_size
);

int px_teqp_calculate_co2_n2_vle_tx(
    double temperature_k,
    double liquid_nitrogen_mole_fraction,
    PXTeqpBinaryVLEResult *result,
    char *error_buffer,
    size_t error_buffer_size
);

int px_teqp_calculate_binary_vle_tx(
    PXTeqpBinaryFormulation formulation,
    double temperature_k,
    double liquid_component2_mole_fraction,
    PXTeqpGenericBinaryVLEResult *result,
    char *error_buffer,
    size_t error_buffer_size
);

int px_teqp_calculate_binary_vle_tx_with_initial_guess(
    PXTeqpBinaryFormulation formulation,
    double temperature_k,
    double liquid_component2_mole_fraction,
    PXTeqpBinaryVLEInitialGuess initial_guess,
    PXTeqpGenericBinaryVLEResult *result,
    char *error_buffer,
    size_t error_buffer_size
);

int px_teqp_calculate_co2_n2_point(
    double pressure_pa,
    double temperature_k,
    double nitrogen_mole_fraction,
    PXTeqpBinaryPointResult *result,
    char *error_buffer,
    size_t error_buffer_size
);

int px_teqp_calculate_eoscg_co2_h2_gas_density(
    double pressure_pa,
    double temperature_k,
    double hydrogen_mole_fraction,
    PXTeqpMixtureDensityResult *result,
    char *error_buffer,
    size_t error_buffer_size
);

int px_teqp_calculate_eoscg_co2_ch4_gas_density(
    double pressure_pa,
    double temperature_k,
    double methane_mole_fraction,
    PXTeqpMixtureDensityResult *result,
    char *error_buffer,
    size_t error_buffer_size
);

int px_teqp_calculate_binary_thermodynamic_state(
    PXTeqpBinaryFormulation formulation,
    double pressure_pa,
    double temperature_k,
    double component2_mole_fraction,
    PXTeqpMixtureThermodynamicResult *result,
    char *error_buffer,
    size_t error_buffer_size
);

int px_teqp_calculate_binary_critical_point(
    PXTeqpBinaryFormulation formulation,
    double component2_mole_fraction,
    PXTeqpBinaryCriticalResult *result,
    char *error_buffer,
    size_t error_buffer_size
);

int px_teqp_calculate_ncomponent_density(
    const int *component_ids,
    const double *mole_fractions,
    size_t component_count,
    double pressure_pa,
    double temperature_k,
    PXTeqpNComponentDensityResult *result,
    char *error_buffer,
    size_t error_buffer_size
);

int px_teqp_calculate_eoscg_co2_o2_gas_density(
    double pressure_pa,
    double temperature_k,
    double oxygen_mole_fraction,
    PXTeqpMixtureDensityResult *result,
    char *error_buffer,
    size_t error_buffer_size
);

#ifdef __cplusplus
}
#endif

#endif
