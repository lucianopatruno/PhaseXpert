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

enum { PXTeqpMaximumDensityRootDiagnostics = 8 };

typedef enum PXTeqpDensityRootSelectionHint {
    PXTeqpDensityRootSelectionAutomatic = 0,
    PXTeqpDensityRootSelectionHomogeneousGas = 1,
    PXTeqpDensityRootSelectionHomogeneousLiquidOrDense = 2,
    PXTeqpDensityRootSelectionSupercritical = 3
} PXTeqpDensityRootSelectionHint;

typedef struct PXTeqpNComponentDensityResult {
    double density_kg_m3;
    double molar_density_mol_m3;
    int density_root_count;
    int root_diagnostic_count;
    double root_molar_densities_mol_m3[PXTeqpMaximumDensityRootDiagnostics];
    double root_densities_kg_m3[PXTeqpMaximumDensityRootDiagnostics];
    double root_dp_drho_molar_j_mol[PXTeqpMaximumDensityRootDiagnostics];
    double root_minimum_stability_eigenvalues[PXTeqpMaximumDensityRootDiagnostics];
    int root_is_mechanically_stable[PXTeqpMaximumDensityRootDiagnostics];
    int root_is_locally_stable[PXTeqpMaximumDensityRootDiagnostics];
    int selected_root_index;
    PXTeqpDensityRootSelectionHint selected_root_hint;
    int converged;
    PXTeqpPhase phase;
} PXTeqpNComponentDensityResult;

typedef enum PXTeqpEquilibriumSpecification {
    PXTeqpEquilibriumBubble = 1,
    PXTeqpEquilibriumDew = 2
} PXTeqpEquilibriumSpecification;

typedef enum PXTeqpEquilibriumStatus {
    PXTeqpEquilibriumConverged = 0,
    PXTeqpEquilibriumMaximumIterations = 1,
    PXTeqpEquilibriumStagnated = 2,
    PXTeqpEquilibriumIllConditioned = 3,
    PXTeqpEquilibriumNoDistinctPhaseSplit = 4,
    PXTeqpEquilibriumInvalidInput = 5,
    PXTeqpEquilibriumThermodynamicFailure = 6
} PXTeqpEquilibriumStatus;

typedef struct PXTeqpNComponentVLEResult {
    int converged;
    int iteration_count;
    PXTeqpEquilibriumStatus status;
    double pressure_pa;
    double liquid_molar_density_mol_m3;
    double vapor_molar_density_mol_m3;
    double maximum_log_fugacity_residual;
    double relative_pressure_residual;
    double liquid_minimum_stability_eigenvalue;
    double vapor_minimum_stability_eigenvalue;
} PXTeqpNComponentVLEResult;

typedef struct PXTeqpPhaseThermodynamicResult {
    double pressure_pa;
    double minimum_stability_eigenvalue;
} PXTeqpPhaseThermodynamicResult;

typedef enum PXTeqpStabilityStatus {
    PXTeqpStabilityStable = 0,
    PXTeqpStabilityUnstable = 1,
    PXTeqpStabilityNearNeutral = 2,
    PXTeqpStabilityFailed = 3
} PXTeqpStabilityStatus;

typedef struct PXTeqpTPDResult {
    PXTeqpStabilityStatus status;
    int converged;
    int iteration_count;
    int density_root_evaluations;
    int distinct_minimum_count;
    double minimum_tpd;
    double trial_molar_density_mol_m3;
    double reference_molar_density_mol_m3;
} PXTeqpTPDResult;

typedef struct PXTeqpTPFlashResult {
    int converged;
    PXTeqpEquilibriumStatus status;
    int iteration_count;
    double vapor_fraction;
    double liquid_molar_density_mol_m3;
    double vapor_molar_density_mol_m3;
    double maximum_material_balance_residual;
    double maximum_log_fugacity_residual;
    double relative_liquid_pressure_residual;
    double relative_vapor_pressure_residual;
    double liquid_minimum_stability_eigenvalue;
    double vapor_minimum_stability_eigenvalue;
    double postcheck_minimum_tpd;
} PXTeqpTPFlashResult;

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
    PXTeqpDensityRootSelectionHint root_selection_hint,
    PXTeqpNComponentDensityResult *result,
    char *error_buffer,
    size_t error_buffer_size
);

int px_teqp_calculate_ncomponent_vle(
    const int *component_ids,
    const double *specified_mole_fractions,
    size_t component_count,
    double temperature_k,
    PXTeqpEquilibriumSpecification specification,
    double *liquid_mole_fractions,
    size_t liquid_mole_fractions_length,
    double *vapor_mole_fractions,
    size_t vapor_mole_fractions_length,
    PXTeqpNComponentVLEResult *result,
    char *error_buffer,
    size_t error_buffer_size
);

int px_teqp_evaluate_ncomponent_phase(
    const int *component_ids,
    const double *partial_molar_densities_mol_m3,
    size_t component_count,
    double temperature_k,
    double *chemical_potentials_j_mol,
    size_t chemical_potentials_length,
    PXTeqpPhaseThermodynamicResult *result,
    char *error_buffer,
    size_t error_buffer_size
);

int px_teqp_calculate_ncomponent_tpd(
    const int *component_ids,
    const double *feed_mole_fractions,
    size_t component_count,
    double pressure_pa,
    double temperature_k,
    double *minimum_composition,
    size_t minimum_composition_length,
    PXTeqpTPDResult *result,
    char *error_buffer,
    size_t error_buffer_size
);

int px_teqp_calculate_ncomponent_tp_flash(
    const int *component_ids,
    const double *feed_mole_fractions,
    size_t component_count,
    double pressure_pa,
    double temperature_k,
    double *liquid_mole_fractions,
    size_t liquid_mole_fractions_length,
    double *vapor_mole_fractions,
    size_t vapor_mole_fractions_length,
    PXTeqpTPFlashResult *result,
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
