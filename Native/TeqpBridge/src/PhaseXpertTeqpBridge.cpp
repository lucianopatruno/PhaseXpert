#include "PhaseXpertTeqpBridge.h"

#include "PhaseXpertTeqpCarbonDioxideData.hpp"

#include "teqp/derivs.hpp"
#include "teqp/models/multifluid.hpp"
#include "teqp/models/multifluid_ancillaries.hpp"

#include <Eigen/Dense>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <exception>
#include <limits>
#include <mutex>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

constexpr double kMaximumMolarDensity = 100000.0;
constexpr int kScanPointCount = 900;
constexpr int kBisectionIterations = 120;
constexpr double kMinimumSaturationPressureTolerancePa = 1.0;
constexpr double kRelativeSaturationPressureTolerance = 1e-8;

void copy_text(const std::string &text, char *buffer, size_t buffer_size) {
    if (buffer == nullptr || buffer_size == 0) {
        return;
    }
    std::snprintf(buffer, buffer_size, "%s", text.c_str());
}

// Narrow transcription of teqp v0.23.1 IsothermPureVLEResiduals/do_pure_VLE_T
// for non-AbstractModel pure fluids. Keeping it local avoids pulling in teqpcpp
// and critical-tracing headers that are unrelated to PhaseXpert's CO2 gate.
template<typename Model>
class PureCO2VLEResiduals {
public:
    using EigenArray = Eigen::Array<double, 2, 1>;
    using EigenArray1 = Eigen::Array<double, 1, 1>;
    using EigenMatrix = Eigen::Array<double, 2, 2>;

    PureCO2VLEResiduals(const Model &model, double temperature_k)
        : model_(model),
          temperature_k_(temperature_k),
          molefractions_(Eigen::ArrayXd::Ones(1, 1)),
          gas_constant_ratio_(model_.R(molefractions_) / model_.R(molefractions_)) {}

    EigenArray call(const EigenArray &rhovec) {
        const EigenArray1 rhovec_liquid = rhovec.head(1);
        const EigenArray1 rhovec_vapor = rhovec.tail(1);
        const double rho_liquid = rhovec_liquid.sum();
        const double rho_vapor = rhovec_vapor.sum();

        auto liquid_derivatives = derivatives(rho_liquid);
        const double p_over_rt_liquid = rho_liquid
            * (gas_constant_ratio_ + liquid_derivatives[1]);
        const double dp_over_rt_drho_liquid = gas_constant_ratio_
            + 2.0 * liquid_derivatives[1] + liquid_derivatives[2];
        const double chemical_potential_liquid = liquid_derivatives[1]
            + liquid_derivatives[0]
            + gas_constant_ratio_ * std::log(rho_liquid);
        const double dchemical_potential_drho_liquid =
            (2.0 * liquid_derivatives[1] + liquid_derivatives[2])
                / rho_liquid
            + gas_constant_ratio_ / rho_liquid;

        auto vapor_derivatives = derivatives(rho_vapor);
        const double p_over_rt_vapor = rho_vapor
            * (gas_constant_ratio_ + vapor_derivatives[1]);
        const double dp_over_rt_drho_vapor = gas_constant_ratio_
            + 2.0 * vapor_derivatives[1] + vapor_derivatives[2];
        const double chemical_potential_vapor = vapor_derivatives[1]
            + vapor_derivatives[0]
            + gas_constant_ratio_ * std::log(rho_vapor);
        const double dchemical_potential_drho_vapor =
            (2.0 * vapor_derivatives[1] + vapor_derivatives[2]) / rho_vapor
            + gas_constant_ratio_ / rho_vapor;

        residuals_(0) = p_over_rt_liquid - p_over_rt_vapor;
        jacobian_(0, 0) = dp_over_rt_drho_liquid;
        jacobian_(0, 1) = -dp_over_rt_drho_vapor;

        residuals_(1) = chemical_potential_liquid - chemical_potential_vapor;
        jacobian_(1, 0) = dchemical_potential_drho_liquid;
        jacobian_(1, 1) = -dchemical_potential_drho_vapor;

        return residuals_;
    }

    const EigenMatrix &jacobian() const { return jacobian_; }

private:
    auto derivatives(double rho) const {
        using Derivatives = teqp::TDXDerivatives<Model, double, Eigen::ArrayXd>;
        return Derivatives::template get_Ar0n<2, teqp::ADBackends::autodiff>(
            model_,
            temperature_k_,
            rho,
            molefractions_
        );
    }

    const Model &model_;
    double temperature_k_;
    Eigen::ArrayXd molefractions_;
    double gas_constant_ratio_;
    EigenMatrix jacobian_;
    EigenArray residuals_;
};

template<typename Model>
Eigen::Array<double, 2, 1> solve_pure_co2_vle(
    const Model &model,
    double temperature_k,
    double liquid_molar_density,
    double vapor_molar_density,
    int max_iterations
) {
    using EigenArray = Eigen::Array<double, 2, 1>;
    PureCO2VLEResiduals<Model> residual(model, temperature_k);
    EigenArray rhovec;
    rhovec << liquid_molar_density, vapor_molar_density;

    for (int iteration = 0; iteration < max_iterations; ++iteration) {
        const auto errors = residual.call(rhovec);
        const auto update = residual.jacobian()
            .matrix()
            .colPivHouseholderQr()
            .solve(-errors.matrix())
            .array()
            .eval();
        const auto next = (rhovec + update).eval();
        if (!std::isfinite(next[0]) || !std::isfinite(next[1])
            || next[0] <= 0 || next[1] <= 0) {
            throw std::runtime_error("teqp pure-CO2 saturation solve produced non-finite densities.");
        }
        if (((next - rhovec).cwiseAbs()
                < std::numeric_limits<double>::epsilon()).all()
            || (errors.cwiseAbs()
                < std::numeric_limits<double>::epsilon()).all()) {
            return next;
        }
        rhovec = next;
    }
    return rhovec;
}

class CarbonDioxideModel {
public:
    using Model = decltype(teqp::build_multifluid_JSONstr(
        std::vector<std::string>{std::string{}},
        std::string{},
        std::string{}
    ));

    CarbonDioxideModel()
        : json_(nlohmann::json::parse(kPhaseXpertTeqpCarbonDioxideJson)),
          model_(teqp::build_multifluid_JSONstr(
              std::vector<std::string>{std::string(kPhaseXpertTeqpCarbonDioxideJson)},
              "{}",
              "{}"
          )),
          ancillaries_(json_.at("ANCILLARIES")),
          molar_mass_kg_mol_(json_.at("EOS").at(0).at("molar_mass")),
          critical_temperature_k_(json_.at("STATES").at("critical").at("T")),
          critical_pressure_pa_(json_.at("STATES").at("critical").at("p")) {}

    double molarMassKilogramsPerMole() const { return molar_mass_kg_mol_; }
    double criticalTemperatureK() const { return critical_temperature_k_; }
    double criticalPressurePa() const { return critical_pressure_pa_; }

    double pressurePa(double temperature_k, double molar_density_mol_m3) const {
        Eigen::Array<double, 1, 1> rhovec;
        rhovec << molar_density_mol_m3;
        Eigen::Array<double, 1, 1> z;
        z << 1.0;
        return rhovec.sum() * model_.R(z) * temperature_k
            + teqp::IsochoricDerivatives<Model, double, decltype(rhovec)>::get_pr(
                model_,
                temperature_k,
                rhovec
            );
    }

    struct SaturationState {
        double pressure_pa;
        double liquid_molar_density_mol_m3;
        double vapor_molar_density_mol_m3;
    };

    SaturationState saturationState(double temperature_k) const {
        if (temperature_k >= critical_temperature_k_) {
            throw std::invalid_argument("Pure-CO2 saturation is defined only below the critical temperature.");
        }
        auto densities = solve_pure_co2_vle(
            model_,
            temperature_k,
            ancillaries_.rhoL(temperature_k),
            ancillaries_.rhoV(temperature_k),
            30
        );
        const double liquid_density = densities[0];
        const double vapor_density = densities[1];
        if (!std::isfinite(liquid_density) || !std::isfinite(vapor_density)
            || liquid_density <= 0 || vapor_density <= 0
            || liquid_density <= vapor_density) {
            throw std::runtime_error("teqp pure-CO2 saturation solve did not converge to ordered finite densities.");
        }
        const double liquid_pressure = pressurePa(temperature_k, liquid_density);
        const double vapor_pressure = pressurePa(temperature_k, vapor_density);
        const double pressure_scale = std::max({
            1.0,
            std::abs(liquid_pressure),
            std::abs(vapor_pressure)
        });
        if (!std::isfinite(liquid_pressure) || !std::isfinite(vapor_pressure)
            || std::abs(liquid_pressure - vapor_pressure)
                > 1e-7 * pressure_scale) {
            throw std::runtime_error("teqp pure-CO2 saturation solve did not satisfy pressure equality.");
        }
        return {
            0.5 * (liquid_pressure + vapor_pressure),
            liquid_density,
            vapor_density
        };
    }

private:
    nlohmann::json json_;
    Model model_;
    teqp::MultiFluidVLEAncillaries ancillaries_;
    double molar_mass_kg_mol_;
    double critical_temperature_k_;
    double critical_pressure_pa_;
};

CarbonDioxideModel &co2_model() {
    static CarbonDioxideModel model;
    return model;
}

struct Root {
    double molar_density_mol_m3;
};

enum class StableBranch {
    vapor,
    liquid,
    supercritical
};

struct SelectedRoot {
    Root root;
    StableBranch branch;
};

bool brackets_root(double left_residual, double right_residual) {
    if (!std::isfinite(left_residual) || !std::isfinite(right_residual)) {
        return false;
    }
    return left_residual == 0.0 || right_residual == 0.0
        || std::signbit(left_residual) != std::signbit(right_residual);
}

bool is_duplicate_root(const std::vector<Root> &roots, double candidate) {
    constexpr double kRelativeRootMergeTolerance = 1e-10;
    for (const auto &root : roots) {
        const double scale = std::max({
            1.0,
            std::abs(root.molar_density_mol_m3),
            std::abs(candidate)
        });
        if (std::abs(candidate - root.molar_density_mol_m3)
            <= kRelativeRootMergeTolerance * scale) {
            return true;
        }
    }
    return false;
}

std::vector<Root> density_roots(
    const CarbonDioxideModel &model,
    double pressure_pa,
    double temperature_k
) {
    std::vector<Root> roots;
    roots.reserve(3);

    const double log_min = std::log(1e-9);
    const double log_max = std::log(kMaximumMolarDensity);
    auto residual = [&](double rho) {
        return model.pressurePa(temperature_k, rho) - pressure_pa;
    };

    double previous_rho = std::exp(log_min);
    double previous_f = residual(previous_rho);
    for (int i = 1; i <= kScanPointCount; ++i) {
        const double fraction = static_cast<double>(i) / kScanPointCount;
        const double rho = std::exp(log_min + fraction * (log_max - log_min));
        const double f = residual(rho);
        if (!std::isfinite(f)) {
            previous_rho = rho;
            previous_f = f;
            continue;
        }
        if (brackets_root(previous_f, f)) {
            double lo = previous_rho;
            double hi = rho;
            double flo = previous_f;
            for (int step = 0; step < kBisectionIterations; ++step) {
                const double mid = 0.5 * (lo + hi);
                const double fmid = residual(mid);
                if (!std::isfinite(fmid)) {
                    break;
                }
                if (brackets_root(flo, fmid)) {
                    hi = mid;
                } else {
                    lo = mid;
                    flo = fmid;
                }
            }
            const double root = 0.5 * (lo + hi);
            if (!is_duplicate_root(roots, root)) {
                roots.push_back({root});
            }
        }
        previous_rho = rho;
        previous_f = f;
    }
    return roots;
}

double saturation_pressure_tolerance(double saturation_pressure_pa) {
    return std::max(
        kMinimumSaturationPressureTolerancePa,
        kRelativeSaturationPressureTolerance * std::abs(saturation_pressure_pa)
    );
}

const Root &closest_root_to(
    const std::vector<Root> &roots,
    double target_molar_density
) {
    return *std::min_element(
        roots.begin(),
        roots.end(),
        [target_molar_density](const Root &lhs, const Root &rhs) {
            return std::abs(lhs.molar_density_mol_m3 - target_molar_density)
                < std::abs(rhs.molar_density_mol_m3 - target_molar_density);
        }
    );
}

SelectedRoot select_stable_root(
    const CarbonDioxideModel &model,
    const std::vector<Root> &roots,
    double pressure_pa,
    double temperature_k
) {
    if (temperature_k > model.criticalTemperatureK()) {
        if (roots.empty()) {
            throw std::runtime_error("teqp did not find a finite pure-CO2 density root.");
        }
        if (roots.size() != 1) {
            throw std::runtime_error("teqp did not find exactly one supercritical density root.");
        }
        return {roots[0], StableBranch::supercritical};
    }

    const auto saturation = model.saturationState(temperature_k);
    const double pressure_delta = pressure_pa - saturation.pressure_pa;
    const double pressure_tolerance = saturation_pressure_tolerance(
        saturation.pressure_pa
    );
    if (std::abs(pressure_delta) <= pressure_tolerance) {
        throw std::runtime_error(
            "teqp state is on or too close to pure-CO2 saturation; a unique homogeneous bulk density is not reported."
        );
    }
    if (roots.empty()) {
        throw std::runtime_error("teqp did not find a finite pure-CO2 density root.");
    }
    if (pressure_delta < 0) {
        return {
            closest_root_to(roots, saturation.vapor_molar_density_mol_m3),
            StableBranch::vapor
        };
    }
    return {
        closest_root_to(roots, saturation.liquid_molar_density_mol_m3),
        StableBranch::liquid
    };
}

PXTeqpPhase phase_for_branch(StableBranch branch) {
    switch (branch) {
    case StableBranch::vapor:
        return PXTeqpPhaseGas;
    case StableBranch::liquid:
        return PXTeqpPhaseLiquid;
    case StableBranch::supercritical:
        return PXTeqpPhaseSupercritical;
    }
}

}  // namespace

int px_teqp_calculate_pure_co2(
    double pressure_pa,
    double temperature_k,
    PXTeqpResult *result,
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
        const auto &model = co2_model();
        const auto roots = density_roots(model, pressure_pa, temperature_k);
        const auto selected = select_stable_root(
            model,
            roots,
            pressure_pa,
            temperature_k
        );
        const double molar_density = selected.root.molar_density_mol_m3;
        const double density = molar_density * model.molarMassKilogramsPerMole();
        if (!std::isfinite(density) || density <= 0) {
            copy_text("teqp returned a non-finite or non-positive density.", error_buffer, error_buffer_size);
            return 5;
        }

        result->molar_density_mol_m3 = molar_density;
        result->density_kg_m3 = density;
        result->density_root_count = static_cast<int>(roots.size());
        result->phase = phase_for_branch(selected.branch);
        copy_text("", error_buffer, error_buffer_size);
        return 0;
    } catch (const std::exception &error) {
        copy_text(error.what(), error_buffer, error_buffer_size);
        return 6;
    } catch (...) {
        copy_text("teqp failed with an unknown native exception.", error_buffer, error_buffer_size);
        return 7;
    }
}

int px_teqp_copy_version(char *version_buffer, size_t version_buffer_size) {
    copy_text("teqp 0.23.1 (usnistgov/teqp a68eb9cabf47af2c4aba0d272ac10fbca4c10eca)", version_buffer, version_buffer_size);
    return 0;
}

int px_teqp_saturation_pure_co2(
    double temperature_k,
    PXTeqpSaturationResult *result,
    char *error_buffer,
    size_t error_buffer_size
) {
    if (result == nullptr) {
        copy_text("Result pointer is null.", error_buffer, error_buffer_size);
        return 1;
    }
    if (!std::isfinite(temperature_k) || temperature_k <= 0) {
        copy_text("Temperature must be finite and positive.", error_buffer, error_buffer_size);
        return 2;
    }

    try {
        const auto &model = co2_model();
        const auto saturation = model.saturationState(temperature_k);
        result->pressure_pa = saturation.pressure_pa;
        result->liquid_molar_density_mol_m3 = saturation.liquid_molar_density_mol_m3;
        result->vapor_molar_density_mol_m3 = saturation.vapor_molar_density_mol_m3;
        result->liquid_density_kg_m3 = saturation.liquid_molar_density_mol_m3
            * model.molarMassKilogramsPerMole();
        result->vapor_density_kg_m3 = saturation.vapor_molar_density_mol_m3
            * model.molarMassKilogramsPerMole();
        copy_text("", error_buffer, error_buffer_size);
        return 0;
    } catch (const std::exception &error) {
        copy_text(error.what(), error_buffer, error_buffer_size);
        return 6;
    } catch (...) {
        copy_text("teqp saturation calculation failed with an unknown native exception.", error_buffer, error_buffer_size);
        return 7;
    }
}
