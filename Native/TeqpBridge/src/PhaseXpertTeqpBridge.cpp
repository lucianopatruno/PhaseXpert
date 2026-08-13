#include "PhaseXpertTeqpBridge.h"

#include "PhaseXpertTeqpModelData.hpp"

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
#include <optional>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

constexpr double kMaximumMolarDensity = 100000.0;
constexpr int kScanPointCount = 900;
constexpr int kBisectionIterations = 120;
constexpr double kMinimumSaturationPressureTolerancePa = 1.0;
constexpr double kRelativeSaturationPressureTolerance = 1e-8;
constexpr double kCarbonDioxideMolarMassKgMol = 0.0440098;
constexpr double kNitrogenMolarMassKgMol = 0.02801348;
constexpr double kBinaryVLEAbsoluteTolerance = 1e-8;
constexpr double kBinaryVLERelativeTolerance = 1e-8;
constexpr int kBinaryVLEMaximumIterations = 50;

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
          critical_pressure_pa_(json_.at("STATES").at("critical").at("p")),
          critical_molar_density_mol_m3_(
              json_.at("STATES").at("critical").at("rhomolar")
          ) {}

    double molarMassKilogramsPerMole() const { return molar_mass_kg_mol_; }
    double criticalTemperatureK() const { return critical_temperature_k_; }
    double criticalPressurePa() const { return critical_pressure_pa_; }
    double criticalMolarDensityMolM3() const { return critical_molar_density_mol_m3_; }

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
    double critical_molar_density_mol_m3_;
};

CarbonDioxideModel &co2_model() {
    static CarbonDioxideModel model;
    return model;
}

class CarbonDioxideNitrogenModel {
public:
    using Model = decltype(teqp::build_multifluid_JSONstr(
        std::vector<std::string>{std::string{}, std::string{}},
        std::string{},
        std::string{}
    ));

    CarbonDioxideNitrogenModel()
        : model_(teqp::build_multifluid_JSONstr(
              std::vector<std::string>{
                  std::string(kPhaseXpertTeqpCarbonDioxideJson),
                  std::string(kPhaseXpertTeqpNitrogenJson)
              },
              std::string(kPhaseXpertTeqpBinaryPairsJson),
              std::string(kPhaseXpertTeqpDepartureFunctionsJson)
          )) {}

    auto psirDerivatives(double temperature_k, const Eigen::ArrayXd &rhovec) const {
        using Derivatives = teqp::IsochoricDerivatives<Model, double, Eigen::ArrayXd>;
        return Derivatives::build_Psir_fgradHessian_autodiff(
            model_,
            temperature_k,
            rhovec
        );
    }

    double pressurePa(double temperature_k, const Eigen::ArrayXd &rhovec) const {
        const Eigen::ArrayXd molefractions = (rhovec / rhovec.sum()).eval();
        auto derivatives = psirDerivatives(temperature_k, rhovec);
        const double residual_pressure =
            -std::get<0>(derivatives)
            + (rhovec * std::get<1>(derivatives).array()).sum();
        return rhovec.sum() * model_.R(molefractions) * temperature_k
            + residual_pressure;
    }

    double gasConstant(const Eigen::ArrayXd &molefractions) const {
        return model_.R(molefractions);
    }

    Eigen::MatrixXd totalPsiHessian(
        double temperature_k,
        const Eigen::ArrayXd &rhovec
    ) const {
        const Eigen::ArrayXd molefractions = (rhovec / rhovec.sum()).eval();
        auto derivatives = psirDerivatives(temperature_k, rhovec);
        Eigen::MatrixXd hessian = std::get<2>(derivatives);
        const double gas_constant_temperature =
            model_.R(molefractions) * temperature_k;
        for (Eigen::Index index = 0; index < rhovec.size(); ++index) {
            if (rhovec[index] <= 0 || !std::isfinite(rhovec[index])) {
                throw std::runtime_error("teqp mixture Hessian requires positive molar concentrations.");
            }
            hessian(index, index) += gas_constant_temperature / rhovec[index];
        }
        return hessian;
    }

    bool isLocallyStable(double temperature_k, const Eigen::ArrayXd &rhovec) const {
        Eigen::SelfAdjointEigenSolver<Eigen::MatrixXd> eigen(
            totalPsiHessian(temperature_k, rhovec)
        );
        if (eigen.info() != Eigen::Success || eigen.eigenvalues().size() == 0) {
            return false;
        }
        const double minimum_eigenvalue = eigen.eigenvalues()[0];
        return std::isfinite(minimum_eigenvalue) && minimum_eigenvalue > 0.0;
    }

    Eigen::Array<double, 2, 1> criticalityConditions(
        double temperature_k,
        double total_molar_density_mol_m3,
        double nitrogen_mole_fraction
    ) const {
        Eigen::ArrayXd rhovec(2);
        rhovec << (1.0 - nitrogen_mole_fraction) * total_molar_density_mol_m3,
            nitrogen_mole_fraction * total_molar_density_mol_m3;
        const Eigen::ArrayXd molefractions = (rhovec / rhovec.sum()).eval();
        const double gas_constant_temperature =
            model_.R(molefractions) * temperature_k;

        Eigen::SelfAdjointEigenSolver<Eigen::MatrixXd> eigen(
            totalPsiHessian(temperature_k, rhovec)
        );
        if (eigen.info() != Eigen::Success || eigen.eigenvalues().size() < 2) {
            throw std::runtime_error("teqp mixture critical Hessian eigenproblem failed.");
        }
        const Eigen::ArrayXd critical_direction = eigen.eigenvectors().col(0).array();

        using Derivatives = teqp::IsochoricDerivatives<Model, double, Eigen::ArrayXd>;
        const Eigen::ArrayXd residual_sigma_derivatives =
            Derivatives::get_Psir_sigma_derivs(
                model_,
                temperature_k,
                rhovec,
                critical_direction
            );
        double ideal_third_derivative = 0.0;
        for (Eigen::Index index = 0; index < rhovec.size(); ++index) {
            ideal_third_derivative += -gas_constant_temperature
                * std::pow(critical_direction[index], 3)
                / std::pow(rhovec[index], 2);
        }
        return (Eigen::Array<double, 2, 1>()
            << eigen.eigenvalues()[0],
            residual_sigma_derivatives[3] + ideal_third_derivative
        ).finished();
    }

    std::optional<double> criticalTemperatureForComposition(
        double nitrogen_mole_fraction
    ) const {
        const double critical_temperature_seed = co2_model().criticalTemperatureK();
        const double critical_density_seed = co2_model().criticalMolarDensityMolM3();
        std::vector<Eigen::Array<double, 2, 1>> seeds;
        for (double temperature_offset : {0.0, -2.0, -5.0, -10.0, -20.0}) {
            for (double density_factor : {0.75, 1.0, 1.25}) {
                seeds.push_back(
                    (Eigen::Array<double, 2, 1>()
                        << critical_temperature_seed + temperature_offset,
                        critical_density_seed * density_factor
                    ).finished()
                );
            }
        }

        for (auto state : seeds) {
            for (int iteration = 0; iteration < 25; ++iteration) {
                if (!std::isfinite(state[0]) || !std::isfinite(state[1])
                    || state[0] <= 0 || state[1] <= 0) {
                    break;
                }
                Eigen::Array<double, 2, 1> residual;
                try {
                    residual = criticalityConditions(
                        state[0],
                        state[1],
                        nitrogen_mole_fraction
                    );
                } catch (...) {
                    break;
                }
                if (!std::isfinite(residual[0]) || !std::isfinite(residual[1])) {
                    break;
                }
                const double temperature_step = std::max(1e-4, 1e-6 * state[0]);
                const double density_step = std::max(1e-3, 1e-6 * state[1]);
                Eigen::Matrix2d jacobian;
                try {
                    const auto plus_temperature = criticalityConditions(
                        state[0] + temperature_step,
                        state[1],
                        nitrogen_mole_fraction
                    );
                    const auto minus_temperature = criticalityConditions(
                        state[0] - temperature_step,
                        state[1],
                        nitrogen_mole_fraction
                    );
                    const auto plus_density = criticalityConditions(
                        state[0],
                        state[1] + density_step,
                        nitrogen_mole_fraction
                    );
                    const auto minus_density = criticalityConditions(
                        state[0],
                        state[1] - density_step,
                        nitrogen_mole_fraction
                    );
                    jacobian.col(0) =
                        ((plus_temperature - minus_temperature)
                            / (2.0 * temperature_step)).matrix();
                    jacobian.col(1) =
                        ((plus_density - minus_density)
                            / (2.0 * density_step)).matrix();
                } catch (...) {
                    break;
                }
                const Eigen::Vector2d update =
                    jacobian.colPivHouseholderQr().solve(-residual.matrix());
                if (!std::isfinite(update[0]) || !std::isfinite(update[1])) {
                    break;
                }
                state[0] += update[0];
                state[1] += update[1];
                if (std::abs(update[0]) < 1e-6
                    && std::abs(update[1]) < 1e-6 * std::max(1.0, state[1])) {
                    break;
                }
            }
            if (!std::isfinite(state[0]) || !std::isfinite(state[1])
                || state[0] <= 0 || state[1] <= 0) {
                continue;
            }
            try {
                const auto residual = criticalityConditions(
                    state[0],
                    state[1],
                    nitrogen_mole_fraction
                );
                if (std::abs(residual[0]) < 1e-5
                    && std::abs(residual[1]) < 1e-7
                    && state[0] > 150.0
                    && state[0] < 500.0) {
                    return state[0];
                }
            } catch (...) {
                continue;
            }
        }
        return std::nullopt;
    }

    double mixtureMolarMassKgMol(double nitrogen_mole_fraction) const {
        return (1.0 - nitrogen_mole_fraction) * kCarbonDioxideMolarMassKgMol
            + nitrogen_mole_fraction * kNitrogenMolarMassKgMol;
    }

private:
    Model model_;
};

CarbonDioxideNitrogenModel &co2_n2_model() {
    static CarbonDioxideNitrogenModel model;
    return model;
}

struct BinaryVLEState {
    bool converged;
    int iteration_count;
    int return_code;
    double pressure_pa;
    Eigen::ArrayXd rhovec_liquid;
    Eigen::ArrayXd rhovec_vapor;
    Eigen::VectorXd residual;
};

bool valid_binary_fraction(double nitrogen_mole_fraction) {
    return std::isfinite(nitrogen_mole_fraction)
        && nitrogen_mole_fraction > 0.0
        && nitrogen_mole_fraction < 1.0;
}

BinaryVLEState solve_binary_vle_tx_once(
    const CarbonDioxideNitrogenModel &model,
    double temperature_k,
    Eigen::ArrayXd liquid_initial,
    Eigen::ArrayXd vapor_initial,
    double liquid_nitrogen_mole_fraction
) {
    constexpr int kComponentCount = 2;
    Eigen::ArrayXd xspec(kComponentCount);
    xspec << 1.0 - liquid_nitrogen_mole_fraction, liquid_nitrogen_mole_fraction;

    Eigen::MatrixXd jacobian(2 * kComponentCount, 2 * kComponentCount);
    Eigen::VectorXd residual(2 * kComponentCount);
    Eigen::VectorXd x(2 * kComponentCount);
    x.head(kComponentCount) = liquid_initial.matrix();
    x.tail(kComponentCount) = vapor_initial.matrix();

    int return_code = 4;
    int iteration_count = 0;
    for (int iteration = 0; iteration < kBinaryVLEMaximumIterations; ++iteration) {
        Eigen::Map<Eigen::ArrayXd> rhovec_liquid(&(x(0)), kComponentCount);
        Eigen::Map<Eigen::ArrayXd> rhovec_vapor(&(x(kComponentCount)), kComponentCount);
        const double gas_constant_temperature =
            model.gasConstant(xspec) * temperature_k;
        auto liquid_derivatives = model.psirDerivatives(temperature_k, rhovec_liquid);
        auto vapor_derivatives = model.psirDerivatives(temperature_k, rhovec_vapor);
        const double psir_liquid = std::get<0>(liquid_derivatives);
        const Eigen::ArrayXd gradient_liquid = std::get<1>(liquid_derivatives);
        const Eigen::MatrixXd hessian_liquid = std::get<2>(liquid_derivatives);
        const double psir_vapor = std::get<0>(vapor_derivatives);
        const Eigen::ArrayXd gradient_vapor = std::get<1>(vapor_derivatives);
        const Eigen::MatrixXd hessian_vapor = std::get<2>(vapor_derivatives);

        const double rho_liquid = rhovec_liquid.sum();
        const double rho_vapor = rhovec_vapor.sum();
        const double pressure_liquid = rho_liquid * gas_constant_temperature
            - psir_liquid + (rhovec_liquid * gradient_liquid).sum();
        const double pressure_vapor = rho_vapor * gas_constant_temperature
            - psir_vapor + (rhovec_vapor * gradient_vapor).sum();
        const Eigen::ArrayXd dpdrho_liquid =
            (gas_constant_temperature
                + (hessian_liquid * rhovec_liquid.matrix()).array()).eval();
        const Eigen::ArrayXd dpdrho_vapor =
            (gas_constant_temperature
                + (hessian_vapor * rhovec_vapor.matrix()).array()).eval();

        const bool co2_nonzero = rhovec_liquid(0) > 0 && rhovec_vapor(0) > 0;
        const bool n2_nonzero = rhovec_liquid(1) > 0 && rhovec_vapor(1) > 0;
        residual(0) = gradient_liquid(0)
            + (co2_nonzero ? gas_constant_temperature * std::log(rhovec_liquid(0)) : 0.0)
            - gradient_vapor(0)
            - (co2_nonzero ? gas_constant_temperature * std::log(rhovec_vapor(0)) : 0.0);
        residual(1) = gradient_liquid(1)
            + (n2_nonzero ? gas_constant_temperature * std::log(rhovec_liquid(1)) : 0.0)
            - gradient_vapor(1)
            - (n2_nonzero ? gas_constant_temperature * std::log(rhovec_vapor(1)) : 0.0);
        residual(2) = pressure_liquid - pressure_vapor;
        residual(3) = rhovec_liquid(0) / rho_liquid - xspec(0);

        jacobian(0, 0) = hessian_liquid(0, 0)
            + (co2_nonzero ? gas_constant_temperature / rhovec_liquid(0) : 0.0);
        jacobian(0, 1) = hessian_liquid(0, 1);
        jacobian(1, 0) = hessian_liquid(1, 0);
        jacobian(1, 1) = hessian_liquid(1, 1)
            + (n2_nonzero ? gas_constant_temperature / rhovec_liquid(1) : 0.0);
        jacobian(0, 2) = -(hessian_vapor(0, 0)
            + (co2_nonzero ? gas_constant_temperature / rhovec_vapor(0) : 0.0));
        jacobian(0, 3) = -hessian_vapor(0, 1);
        jacobian(1, 2) = -hessian_vapor(1, 0);
        jacobian(1, 3) = -(hessian_vapor(1, 1)
            + (n2_nonzero ? gas_constant_temperature / rhovec_vapor(1) : 0.0));
        jacobian(2, 0) = dpdrho_liquid(0);
        jacobian(2, 1) = dpdrho_liquid(1);
        jacobian(2, 2) = -dpdrho_vapor(0);
        jacobian(2, 3) = -dpdrho_vapor(1);
        jacobian.row(3).array() = 0.0;
        jacobian(3, 0) = (rho_liquid - rhovec_liquid(0)) / (rho_liquid * rho_liquid);
        jacobian(3, 1) = -rhovec_liquid(0) / (rho_liquid * rho_liquid);

        Eigen::VectorXd step = jacobian.colPivHouseholderQr().solve(-residual);
        if (!step.array().isFinite().all()) {
            return_code = 5;
            break;
        }
        if ((x.array() + step.array() < 0).any()) {
            Eigen::ArrayXd maximum_step = -x.array();
            const double limiter = (step.array() / maximum_step).minCoeff();
            step *= limiter / 2.0;
        }
        x += step;
        iteration_count = iteration + 1;

        const Eigen::ArrayXd step_threshold =
            (kBinaryVLEAbsoluteTolerance
                + kBinaryVLERelativeTolerance * x.array().abs()).eval();
        if ((step.array().abs() < step_threshold).all()) {
            return_code = 1;
            break;
        }
        const Eigen::ArrayXd residual_threshold =
            (kBinaryVLEAbsoluteTolerance
                + kBinaryVLERelativeTolerance * residual.array().abs()).eval();
        if ((residual.array().abs() < residual_threshold).all()) {
            return_code = 2;
            break;
        }
    }

    Eigen::ArrayXd rhovec_liquid = x.head(kComponentCount).array();
    Eigen::ArrayXd rhovec_vapor = x.tail(kComponentCount).array();
    const double pressure_liquid = model.pressurePa(temperature_k, rhovec_liquid);
    const double pressure_vapor = model.pressurePa(temperature_k, rhovec_vapor);
    const double pressure_scale = std::max({
        1.0,
        std::abs(pressure_liquid),
        std::abs(pressure_vapor)
    });
    const bool converged = (return_code == 1 || return_code == 2)
        && rhovec_liquid.isFinite().all()
        && rhovec_vapor.isFinite().all()
        && (rhovec_liquid > 0).all()
        && (rhovec_vapor > 0).all()
        && std::abs(pressure_liquid - pressure_vapor) <= 1e-7 * pressure_scale
        && std::abs(residual(0)) <= 1e-5
        && std::abs(residual(1)) <= 1e-5;

    return {
        converged,
        iteration_count,
        return_code,
        0.5 * (pressure_liquid + pressure_vapor),
        rhovec_liquid,
        rhovec_vapor,
        residual
    };
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

BinaryVLEState solve_binary_vle_tx(
    double temperature_k,
    double liquid_nitrogen_mole_fraction
) {
    if (!std::isfinite(temperature_k) || temperature_k <= 0) {
        throw std::invalid_argument("Temperature must be finite and positive.");
    }
    if (!valid_binary_fraction(liquid_nitrogen_mole_fraction)) {
        throw std::invalid_argument("Liquid nitrogen mole fraction must be finite and in (0, 1).");
    }
    const auto pure_saturation = co2_model().saturationState(temperature_k);
    const auto &model = co2_n2_model();

    constexpr double kInitialNitrogenSeed = 1e-8;
    Eigen::ArrayXd liquid(2), vapor(2);
    liquid << pure_saturation.liquid_molar_density_mol_m3 * (1.0 - kInitialNitrogenSeed),
        pure_saturation.liquid_molar_density_mol_m3 * kInitialNitrogenSeed;
    vapor << pure_saturation.vapor_molar_density_mol_m3 * (1.0 - kInitialNitrogenSeed),
        pure_saturation.vapor_molar_density_mol_m3 * kInitialNitrogenSeed;

    std::vector<double> targets = {
        1e-6,
        1e-5,
        1e-4,
        1e-3,
        0.005,
        0.01,
        0.03,
        0.05,
        0.10
    };
    targets.erase(
        std::remove_if(
            targets.begin(),
            targets.end(),
            [liquid_nitrogen_mole_fraction](double value) {
                return value >= liquid_nitrogen_mole_fraction;
            }
        ),
        targets.end()
    );
    targets.push_back(liquid_nitrogen_mole_fraction);
    std::sort(targets.begin(), targets.end());

    BinaryVLEState state{};
    for (double target : targets) {
        state = solve_binary_vle_tx_once(
            model,
            temperature_k,
            liquid,
            vapor,
            target
        );
        if (!state.converged) {
            throw std::runtime_error("teqp CO2/N2 mix_VLE_Tx did not converge during continuation.");
        }
        liquid = state.rhovec_liquid;
        vapor = state.rhovec_vapor;
    }
    return state;
}

BinaryVLEState solve_binary_dew_for_vapor_composition(
    double temperature_k,
    double vapor_nitrogen_mole_fraction
) {
    if (!valid_binary_fraction(vapor_nitrogen_mole_fraction)) {
        throw std::invalid_argument("Vapor nitrogen mole fraction must be finite and in (0, 1).");
    }

    double lower = 1e-8;
    auto lower_state = solve_binary_vle_tx(temperature_k, lower);
    auto lower_y = lower_state.rhovec_vapor(1) / lower_state.rhovec_vapor.sum();
    if (lower_y > vapor_nitrogen_mole_fraction) {
        return lower_state;
    }

    double upper = std::min(0.5, std::max(0.001, vapor_nitrogen_mole_fraction));
    BinaryVLEState upper_state = solve_binary_vle_tx(temperature_k, upper);
    double upper_y = upper_state.rhovec_vapor(1) / upper_state.rhovec_vapor.sum();
    while (upper_y < vapor_nitrogen_mole_fraction && upper < 0.95) {
        upper = std::min(0.95, upper * 1.5);
        upper_state = solve_binary_vle_tx(temperature_k, upper);
        upper_y = upper_state.rhovec_vapor(1) / upper_state.rhovec_vapor.sum();
    }
    if (upper_y < vapor_nitrogen_mole_fraction) {
        throw std::runtime_error("teqp CO2/N2 dew solve could not bracket the vapor composition.");
    }

    BinaryVLEState mid_state = upper_state;
    for (int iteration = 0; iteration < 40; ++iteration) {
        const double mid = 0.5 * (lower + upper);
        mid_state = solve_binary_vle_tx(temperature_k, mid);
        const double mid_y = mid_state.rhovec_vapor(1) / mid_state.rhovec_vapor.sum();
        if (std::abs(mid_y - vapor_nitrogen_mole_fraction) <= 1e-8) {
            return mid_state;
        }
        if (mid_y < vapor_nitrogen_mole_fraction) {
            lower = mid;
            lower_state = mid_state;
        } else {
            upper = mid;
            upper_state = mid_state;
        }
    }
    return mid_state;
}

std::vector<Root> binary_density_roots(
    const CarbonDioxideNitrogenModel &model,
    double pressure_pa,
    double temperature_k,
    double nitrogen_mole_fraction
) {
    std::vector<Root> roots;
    roots.reserve(3);
    Eigen::ArrayXd composition(2);
    composition << 1.0 - nitrogen_mole_fraction, nitrogen_mole_fraction;
    const double log_min = std::log(1e-9);
    const double log_max = std::log(kMaximumMolarDensity);
    auto residual = [&](double total_molar_density) {
        return model.pressurePa(
            temperature_k,
            total_molar_density * composition
        ) - pressure_pa;
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

Root lowest_density_root(const std::vector<Root> &roots) {
    return *std::min_element(
        roots.begin(),
        roots.end(),
        [](const Root &lhs, const Root &rhs) {
            return lhs.molar_density_mol_m3 < rhs.molar_density_mol_m3;
        }
    );
}

Root highest_density_root(const std::vector<Root> &roots) {
    return *std::max_element(
        roots.begin(),
        roots.end(),
        [](const Root &lhs, const Root &rhs) {
            return lhs.molar_density_mol_m3 < rhs.molar_density_mol_m3;
        }
    );
}

int fill_homogeneous_binary_density_result(
    const CarbonDioxideNitrogenModel &model,
    const std::vector<Root> &roots,
    double nitrogen_mole_fraction,
    PXTeqpPhase phase,
    const Root &selected,
    PXTeqpBinaryPointResult *result,
    char *error_buffer,
    size_t error_buffer_size
) {
    if (roots.empty()) {
        copy_text("teqp did not find a finite CO2/N2 density root.", error_buffer, error_buffer_size);
        return 6;
    }
    const double molar_mass =
        model.mixtureMolarMassKgMol(nitrogen_mole_fraction);
    const double density = selected.molar_density_mol_m3 * molar_mass;
    if (!std::isfinite(density) || density <= 0) {
        copy_text("teqp returned a non-finite or non-positive CO2/N2 density.", error_buffer, error_buffer_size);
        return 6;
    }

    result->density_kg_m3 = density;
    result->molar_density_mol_m3 = selected.molar_density_mol_m3;
    result->density_root_count = static_cast<int>(roots.size());
    result->phase = phase;
    copy_text("", error_buffer, error_buffer_size);
    return 0;
}

void fill_binary_vle_result(
    const BinaryVLEState &state,
    PXTeqpBinaryVLEResult *result
) {
    result->converged = state.converged ? 1 : 0;
    result->iteration_count = state.iteration_count;
    result->return_code = state.return_code;
    result->pressure_pa = state.pressure_pa;
    result->liquid_molar_density_mol_m3 = state.rhovec_liquid.sum();
    result->vapor_molar_density_mol_m3 = state.rhovec_vapor.sum();
    result->liquid_co2_mole_fraction =
        state.rhovec_liquid(0) / state.rhovec_liquid.sum();
    result->liquid_n2_mole_fraction =
        state.rhovec_liquid(1) / state.rhovec_liquid.sum();
    result->vapor_co2_mole_fraction =
        state.rhovec_vapor(0) / state.rhovec_vapor.sum();
    result->vapor_n2_mole_fraction =
        state.rhovec_vapor(1) / state.rhovec_vapor.sum();
    result->pressure_residual_pa = state.residual(2);
    result->co2_chemical_potential_residual = state.residual(0);
    result->n2_chemical_potential_residual = state.residual(1);
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
    copy_text("teqp 0.23.1 (usnistgov/teqp a68eb9cabf47af2c4aba0d272ac10fbca4c10eca; CO2 Span-JPCRD-1996; N2 Span-JPCRD-2000; CO2/N2 Gernert-Thesis-2013 betaT=0.994140013 gammaT=1.107654104 betaV=1.022709642 gammaV=1.047578256 + Kunz-JCED-2012)", version_buffer, version_buffer_size);
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

int px_teqp_calculate_co2_n2_vle_tx(
    double temperature_k,
    double liquid_nitrogen_mole_fraction,
    PXTeqpBinaryVLEResult *result,
    char *error_buffer,
    size_t error_buffer_size
) {
    if (result == nullptr) {
        copy_text("Result pointer is null.", error_buffer, error_buffer_size);
        return 1;
    }
    try {
        const auto state = solve_binary_vle_tx(
            temperature_k,
            liquid_nitrogen_mole_fraction
        );
        fill_binary_vle_result(state, result);
        copy_text("", error_buffer, error_buffer_size);
        return state.converged ? 0 : 6;
    } catch (const std::exception &error) {
        copy_text(error.what(), error_buffer, error_buffer_size);
        return 6;
    } catch (...) {
        copy_text("teqp CO2/N2 VLE calculation failed with an unknown native exception.", error_buffer, error_buffer_size);
        return 7;
    }
}

int px_teqp_calculate_co2_n2_point(
    double pressure_pa,
    double temperature_k,
    double nitrogen_mole_fraction,
    PXTeqpBinaryPointResult *result,
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
    if (!valid_binary_fraction(nitrogen_mole_fraction)) {
        copy_text("Nitrogen mole fraction must be finite and in (0, 1).", error_buffer, error_buffer_size);
        return 3;
    }

    try {
        const auto &model = co2_n2_model();
        const auto roots = binary_density_roots(
            model,
            pressure_pa,
            temperature_k,
            nitrogen_mole_fraction
        );
        if (roots.empty()) {
            copy_text("teqp did not find a finite CO2/N2 density root.", error_buffer, error_buffer_size);
            return 6;
        }

        if (roots.size() == 1) {
            Eigen::ArrayXd rhovec(2);
            rhovec << (1.0 - nitrogen_mole_fraction)
                    * roots[0].molar_density_mol_m3,
                nitrogen_mole_fraction * roots[0].molar_density_mol_m3;
            const bool locally_stable =
                model.isLocallyStable(temperature_k, rhovec);
            const auto critical_temperature =
                model.criticalTemperatureForComposition(nitrogen_mole_fraction);
            if (locally_stable && critical_temperature
                && temperature_k > critical_temperature.value() + 1e-5) {
                result->dew_pressure_pa = std::numeric_limits<double>::quiet_NaN();
                result->bubble_pressure_pa = std::numeric_limits<double>::quiet_NaN();
                result->dew_converged = 0;
                result->bubble_converged = 0;
                return fill_homogeneous_binary_density_result(
                    model,
                    roots,
                    nitrogen_mole_fraction,
                    PXTeqpPhaseSupercritical,
                    roots[0],
                    result,
                    error_buffer,
                    error_buffer_size
                );
            }
            if (locally_stable && !critical_temperature) {
                result->dew_pressure_pa = std::numeric_limits<double>::quiet_NaN();
                result->bubble_pressure_pa = std::numeric_limits<double>::quiet_NaN();
                result->dew_converged = 0;
                result->bubble_converged = 0;
                return fill_homogeneous_binary_density_result(
                    model,
                    roots,
                    nitrogen_mole_fraction,
                    PXTeqpPhaseUnknown,
                    roots[0],
                    result,
                    error_buffer,
                    error_buffer_size
                );
            }
        }

        try {
            const auto bubble = solve_binary_vle_tx(
                temperature_k,
                nitrogen_mole_fraction
            );
            const auto dew = solve_binary_dew_for_vapor_composition(
                temperature_k,
                nitrogen_mole_fraction
            );
            const double lower_boundary = std::min(dew.pressure_pa, bubble.pressure_pa);
            const double upper_boundary = std::max(dew.pressure_pa, bubble.pressure_pa);
            const double boundary_scale = std::max({1.0, lower_boundary, upper_boundary});
            const double boundary_tolerance =
                std::max(1.0, 1e-7 * boundary_scale);

            result->dew_pressure_pa = dew.pressure_pa;
            result->bubble_pressure_pa = bubble.pressure_pa;
            result->dew_converged = dew.converged ? 1 : 0;
            result->bubble_converged = bubble.converged ? 1 : 0;

            if (pressure_pa >= lower_boundary - boundary_tolerance
                && pressure_pa <= upper_boundary + boundary_tolerance) {
                result->density_kg_m3 = std::numeric_limits<double>::quiet_NaN();
                result->molar_density_mol_m3 = std::numeric_limits<double>::quiet_NaN();
                result->density_root_count = 0;
                result->phase = PXTeqpPhaseTwoPhase;
                copy_text("", error_buffer, error_buffer_size);
                return 0;
            }

            const bool vapor_side = pressure_pa < lower_boundary - boundary_tolerance;
            return fill_homogeneous_binary_density_result(
                model,
                roots,
                nitrogen_mole_fraction,
                vapor_side ? PXTeqpPhaseGas : PXTeqpPhaseLiquid,
                vapor_side ? lowest_density_root(roots) : highest_density_root(roots),
                result,
                error_buffer,
                error_buffer_size
            );
        } catch (const std::exception &) {
            if (roots.size() == 1) {
                Eigen::ArrayXd rhovec(2);
                rhovec << (1.0 - nitrogen_mole_fraction)
                        * roots[0].molar_density_mol_m3,
                    nitrogen_mole_fraction * roots[0].molar_density_mol_m3;
                if (model.isLocallyStable(temperature_k, rhovec)) {
                    result->dew_pressure_pa = std::numeric_limits<double>::quiet_NaN();
                    result->bubble_pressure_pa = std::numeric_limits<double>::quiet_NaN();
                    result->dew_converged = 0;
                    result->bubble_converged = 0;
                    return fill_homogeneous_binary_density_result(
                        model,
                        roots,
                        nitrogen_mole_fraction,
                        PXTeqpPhaseUnknown,
                        roots[0],
                        result,
                        error_buffer,
                        error_buffer_size
                    );
                }
            }
            throw;
        }
    } catch (const std::exception &error) {
        copy_text(error.what(), error_buffer, error_buffer_size);
        return 6;
    } catch (...) {
        copy_text("teqp CO2/N2 point calculation failed with an unknown native exception.", error_buffer, error_buffer_size);
        return 7;
    }
}
