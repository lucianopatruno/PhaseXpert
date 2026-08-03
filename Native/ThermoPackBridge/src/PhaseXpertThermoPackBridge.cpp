#include "PhaseXpertThermoPackBridge.h"
#include "thermopack.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>
#include <mutex>

namespace {
constexpr const char *kBridgeVersion = "1.0.0";
constexpr const char *kLibraryVersion = "2.2.4+ca75d8e095e8b951616897efe1bca9b8c3badda7";
constexpr const char *kConfiguration =
    "PR (Peng-Robinson), Classic alpha, Classic/van der Waals one-fluid mixing, "
    "ThermoPack PR_kij.json vdW-18 ref=Default";
std::mutex model_mutex;

void set_error(char *error, size_t capacity, const char *message) {
    if (error == nullptr || capacity == 0) return;
    std::strncpy(error, message, capacity - 1);
    error[capacity - 1] = '\0';
}

bool valid_composition(double co2, double n2) {
    return std::isfinite(co2) && std::isfinite(n2) && co2 >= 0.90 && co2 <= 1.0
        && n2 >= 0.0 && n2 <= 0.10 && std::abs((co2 + n2) - 1.0) <= 1e-10;
}

void initialize_model() {
    int nphases = 2;
    int discriminator = 0;
    double b_exponent = 0.0;
    thermopack_init_c(
        "PR", "Classic", "Classic", "CO2,N2", &nphases, &discriminator,
        "", "", "Default", "Default", "", &b_exponent
    );
}

bool finite_positive(double value) {
    return std::isfinite(value) && value > 0.0;
}
}

const char *px_thermopack_bridge_version(void) { return kBridgeVersion; }
const char *px_thermopack_library_version(void) { return kLibraryVersion; }
const char *px_thermopack_configuration(void) { return kConfiguration; }

int32_t px_thermopack_state(
    double pressure_pa,
    double temperature_k,
    double carbon_dioxide_mole_fraction,
    double nitrogen_mole_fraction,
    PXThermoPackState *output,
    char *error,
    size_t error_capacity
) {
    if (output == nullptr) {
        set_error(error, error_capacity, "ThermoPack state output is null.");
        return 1;
    }
    *output = {};
    output->vapor_fraction = NAN;
    if (!finite_positive(pressure_pa) || !finite_positive(temperature_k)) {
        set_error(error, error_capacity, "Pressure and temperature must be finite and positive.");
        return 2;
    }
    if (!valid_composition(carbon_dioxide_mole_fraction, nitrogen_mole_fraction)) {
        set_error(error, error_capacity, "ThermoPack PR scope requires 90-100 mol% CO2 and 0-10 mol% N2, summing exactly to one.");
        return 3;
    }

    std::lock_guard<std::mutex> lock(model_mutex);
    initialize_model();

    const double z[2] = {carbon_dioxide_mole_fraction, nitrogen_mole_fraction};
    double beta = 0.0;
    int phase = 0;
    double liquid[2] = {0.0, 0.0};
    double vapor[2] = {0.0, 0.0};
    thermopack_tpflash_c(&temperature_k, &pressure_pa, z, &beta, &phase, liquid, vapor);

    int two_phase = 0, liquid_phase = 0, vapor_phase = 0, minimum_gibbs = 0;
    int single_phase = 0, solid_phase = 0, fake_phase = 0;
    get_phase_flags_c(
        &two_phase, &liquid_phase, &vapor_phase, &minimum_gibbs,
        &single_phase, &solid_phase, &fake_phase
    );
    output->phase = phase;
    output->is_two_phase = phase == two_phase ? 1 : 0;
    if (output->is_two_phase) {
        if (!std::isfinite(beta) || beta < 0.0 || beta > 1.0) {
            set_error(error, error_capacity, "ThermoPack returned a non-finite or invalid vapor fraction.");
            return 4;
        }
        output->vapor_fraction = beta;
        return 0;
    }

    int property_phase = phase;
    if (property_phase != liquid_phase && property_phase != vapor_phase) {
        thermopack_guess_phase_c(&temperature_k, &pressure_pa, z, &property_phase);
    }

    double molar_mass = 0.0;
    double molar_volume = 0.0;
    double compressibility = 0.0;
    double molar_enthalpy = 0.0;
    double molar_cp = 0.0;
    double dhdp = 0.0;
    double dhdx[2] = {0.0, 0.0};
    double molar_entropy = 0.0;
    thermopack_moleweight_c(z, &molar_mass);
    thermopack_specific_volume_c(
        &temperature_k, &pressure_pa, z, &property_phase, &molar_volume
    );
    thermopack_zfac_c(
        &temperature_k, &pressure_pa, z, &property_phase, &compressibility
    );
    thermopack_enthalpy_c(
        &temperature_k, &pressure_pa, z, &property_phase,
        &molar_enthalpy, &molar_cp, &dhdp, dhdx
    );
    thermopack_entropy_c(
        &temperature_k, &pressure_pa, z, &property_phase, &molar_entropy
    );

    if (!finite_positive(molar_mass) || !finite_positive(molar_volume)
        || !finite_positive(compressibility) || !std::isfinite(molar_enthalpy)
        || !std::isfinite(molar_entropy) || !finite_positive(molar_cp)) {
        set_error(error, error_capacity, "ThermoPack returned a non-finite or non-physical single-phase property.");
        return 5;
    }

    output->molar_mass_kg_mol = molar_mass;
    output->density_kg_m3 = molar_mass / molar_volume;
    output->specific_volume_m3_kg = molar_volume / molar_mass;
    output->compressibility_factor = compressibility;
    output->enthalpy_j_kg = molar_enthalpy / molar_mass;
    output->entropy_j_kg_k = molar_entropy / molar_mass;
    output->cp_j_kg_k = molar_cp / molar_mass;

    if (!finite_positive(output->density_kg_m3)
        || !finite_positive(output->specific_volume_m3_kg)
        || !std::isfinite(output->enthalpy_j_kg)
        || !std::isfinite(output->entropy_j_kg_k)
        || !finite_positive(output->cp_j_kg_k)) {
        set_error(error, error_capacity, "ThermoPack mass-specific conversion produced an invalid value.");
        return 6;
    }
    return 0;
}

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
) {
    if (output == nullptr) {
        set_error(error, error_capacity, "ThermoPack envelope output is null.");
        return 1;
    }
    *output = {};
    if (!valid_composition(carbon_dioxide_mole_fraction, nitrogen_mole_fraction)) {
        set_error(error, error_capacity, "Unsupported ThermoPack envelope composition.");
        return 2;
    }
    if (!finite_positive(minimum_temperature_k)
        || !finite_positive(maximum_temperature_k)
        || maximum_temperature_k <= minimum_temperature_k
        || !finite_positive(minimum_pressure_pa)
        || !finite_positive(maximum_pressure_pa)
        || maximum_pressure_pa <= minimum_pressure_pa
        || maximum_points_per_branch < 2
        || maximum_points_per_branch > PX_THERMOPACK_MAX_POINTS / 2
        || !finite_positive(maximum_elapsed_ms)) {
        set_error(error, error_capacity, "Invalid bounded ThermoPack envelope settings.");
        return 3;
    }

    std::lock_guard<std::mutex> lock(model_mutex);
    initialize_model();
    const auto started = std::chrono::steady_clock::now();
    const double increment = (maximum_temperature_k - minimum_temperature_k)
        / static_cast<double>(maximum_points_per_branch - 1);
    const double co2n2[2] = {carbon_dioxide_mole_fraction, nitrogen_mole_fraction};

    for (int branch = 0; branch < 2; ++branch) {
        bool branch_complete = true;
        for (int32_t index = 0; index < maximum_points_per_branch; ++index) {
            const auto now = std::chrono::steady_clock::now();
            const double elapsed = std::chrono::duration<double, std::milli>(now - started).count();
            if (elapsed >= maximum_elapsed_ms) {
                output->timed_out = 1;
                branch_complete = false;
                break;
            }
            const double temperature = minimum_temperature_k + increment * index;
            double incipient[2] = {0.0, 0.0};
            double pressure = NAN;
            int ierr = 0;
            output->attempted_calls += 1;
            if (branch == 0) {
                thermopack_bubp_c(&temperature, co2n2, incipient, &pressure, &ierr);
            } else {
                thermopack_dewp_c(&temperature, incipient, co2n2, &pressure, &ierr);
            }
            if (ierr != 0 || !finite_positive(pressure)) {
                output->failed_calls += 1;
                branch_complete = false;
                continue;
            }
            if (pressure < minimum_pressure_pa || pressure > maximum_pressure_pa) {
                branch_complete = false;
                continue;
            }
            const int32_t point_index = output->point_count;
            if (point_index >= PX_THERMOPACK_MAX_POINTS) {
                branch_complete = false;
                break;
            }
            output->points[point_index] = {temperature, pressure, branch};
            output->point_count += 1;
            if (branch == 0) output->bubble_count += 1;
            else output->dew_count += 1;
        }
        if (!branch_complete) output->complete = 0;
    }
    output->elapsed_ms = std::chrono::duration<double, std::milli>(
        std::chrono::steady_clock::now() - started
    ).count();
    output->complete = output->complete != 0
        && output->bubble_count == maximum_points_per_branch
        && output->dew_count == maximum_points_per_branch;
    if (output->bubble_count < 2 || output->dew_count < 2) {
        set_error(error, error_capacity, "ThermoPack did not return at least two finite points on each bubble/dew branch.");
        return 4;
    }
    return 0;
}
