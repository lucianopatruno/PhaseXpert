#include "PhaseXpertTeqpBridge.h"

#include "PhaseXpertTeqpModelData.hpp"

#include "teqp/derivs.hpp"
#include "teqp/ideal_eosterms.hpp"
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
#include <set>
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
constexpr double kHydrogenMolarMassKgMol = 0.00201588;
constexpr double kMethaneMolarMassKgMol = 0.0160428;
constexpr double kBinaryVLEAbsoluteTolerance = 1e-8;
constexpr double kBinaryVLERelativeTolerance = 1e-8;
constexpr int kBinaryVLEMaximumIterations = 50;
constexpr double kGasConstantJMolK = 8.31446261815324;

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
          ideal_model_(idealTerms(json_)),
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

    struct ThermodynamicProperties {
        double cv_j_kg_k;
        double cp_j_kg_k;
        double heat_capacity_ratio;
        double speed_of_sound_m_s;
    };

    ThermodynamicProperties thermodynamicProperties(
        double temperature_k,
        double molar_density_mol_m3
    ) const {
        Eigen::Array<double, 1, 1> z;
        z << 1.0;
        using ResidualDerivatives =
            teqp::TDXDerivatives<Model, double, Eigen::ArrayXd>;
        using IdealDerivatives =
            teqp::TDXDerivatives<teqp::IdealHelmholtz, double, Eigen::ArrayXd>;
        const Eigen::ArrayXd molefractions = Eigen::ArrayXd::Ones(1);
        const auto residual_density_derivatives =
            ResidualDerivatives::template get_Ar0n<2, teqp::ADBackends::autodiff>(
                model_,
                temperature_k,
                molar_density_mol_m3,
                molefractions
            );
        const double ar01 = residual_density_derivatives[1];
        const double ar02 = residual_density_derivatives[2];
        const double ar11 =
            ResidualDerivatives::template get_Arxy<1, 1, teqp::ADBackends::autodiff>(
                model_,
                temperature_k,
                molar_density_mol_m3,
                molefractions
            );
        const double ar20 =
            ResidualDerivatives::template get_Arxy<2, 0, teqp::ADBackends::autodiff>(
                model_,
                temperature_k,
                molar_density_mol_m3,
                molefractions
            );
        const double a020 =
            IdealDerivatives::template get_Arxy<2, 0, teqp::ADBackends::autodiff>(
                ideal_model_,
                temperature_k,
                molar_density_mol_m3,
                molefractions
            );

        const double cv_over_r = -(a020 + ar20);
        const double pressure_derivative = 1.0 + 2.0 * ar01 + ar02;
        const double temperature_density_coupling = 1.0 + ar01 - ar11;
        if (!std::isfinite(cv_over_r) || !std::isfinite(pressure_derivative)
            || !std::isfinite(temperature_density_coupling)
            || cv_over_r <= 0.0 || pressure_derivative <= 0.0) {
            throw std::runtime_error("teqp returned non-physical pure-CO2 heat-capacity derivatives.");
        }
        const double cp_over_r = cv_over_r
            + temperature_density_coupling * temperature_density_coupling
                / pressure_derivative;
        const double speed_dimensionless = pressure_derivative
            + temperature_density_coupling * temperature_density_coupling
                / cv_over_r;
        if (!std::isfinite(cp_over_r) || !std::isfinite(speed_dimensionless)
            || cp_over_r <= cv_over_r || speed_dimensionless <= 0.0) {
            throw std::runtime_error("teqp returned non-physical pure-CO2 Cp or speed-of-sound derivatives.");
        }

        const double gas_constant = model_.R(z);
        const double cv_molar = cv_over_r * gas_constant;
        const double cp_molar = cp_over_r * gas_constant;
        const double speed_of_sound = std::sqrt(
            speed_dimensionless * gas_constant * temperature_k
                / molar_mass_kg_mol_
        );
        return {
            cv_molar / molar_mass_kg_mol_,
            cp_molar / molar_mass_kg_mol_,
            cp_over_r / cv_over_r,
            speed_of_sound
        };
    }

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
    static nlohmann::json idealTerms(const nlohmann::json &fluid_json) {
        const auto eos = fluid_json.at("EOS").at(0);
        const double reducing_temperature = eos.at("STATES").at("reducing").at("T");
        const double reducing_molar_density =
            eos.at("STATES").at("reducing").at("rhomolar");
        const double gas_constant = eos.at("gas_constant");
        nlohmann::json terms = nlohmann::json::array();
        for (const auto &term : eos.at("alpha0")) {
            auto converted = teqp::CoolProp2teqp_alphaig_term_reformatter(
                term,
                reducing_temperature,
                reducing_molar_density,
                gas_constant
            );
            for (const auto &converted_term : converted) {
                terms.push_back(converted_term);
            }
        }
        return nlohmann::json::array({
            {
                {"terms", terms},
                {"R", gas_constant}
            }
        });
    }

    nlohmann::json json_;
    Model model_;
    teqp::MultiFluidVLEAncillaries ancillaries_;
    teqp::IdealHelmholtz ideal_model_;
    double molar_mass_kg_mol_;
    double critical_temperature_k_;
    double critical_pressure_pa_;
    double critical_molar_density_mol_m3_;
};

CarbonDioxideModel &co2_model() {
    static CarbonDioxideModel model;
    return model;
}

teqp::IdealHelmholtz ideal_terms_for_components(
    const std::vector<std::string> &component_json_strings
) {
    nlohmann::json mixture_terms = nlohmann::json::array();
    for (const auto &component_json_string : component_json_strings) {
        const auto fluid_json = nlohmann::json::parse(component_json_string);
        const auto eos = fluid_json.at("EOS").at(0);
        const double reducing_temperature =
            eos.at("STATES").at("reducing").at("T");
        const double reducing_molar_density =
            eos.at("STATES").at("reducing").at("rhomolar");
        const double gas_constant = eos.at("gas_constant");
        nlohmann::json terms = nlohmann::json::array();
        for (const auto &term : eos.at("alpha0")) {
            auto converted = teqp::CoolProp2teqp_alphaig_term_reformatter(
                term,
                reducing_temperature,
                reducing_molar_density,
                gas_constant
            );
            for (const auto &converted_term : converted) {
                terms.push_back(converted_term);
            }
        }
        mixture_terms.push_back({
            {"terms", terms},
            {"R", gas_constant}
        });
    }
    return teqp::IdealHelmholtz(mixture_terms);
}

std::string component_json_for_id(int component_id) {
    switch (component_id) {
    case PXTeqpComponentCarbonDioxide:
        return std::string(kPhaseXpertTeqpCarbonDioxideJson);
    case PXTeqpComponentNitrogen:
        return std::string(kPhaseXpertTeqpNitrogenJson);
    case PXTeqpComponentMethane:
        return std::string(kPhaseXpertTeqpMethaneJson);
    case PXTeqpComponentHydrogen:
        return std::string(kPhaseXpertTeqpHydrogenJson);
    case PXTeqpComponentOxygen:
        return std::string(kPhaseXpertTeqpOxygenJson);
    case PXTeqpComponentArgon:
        return std::string(kPhaseXpertTeqpArgonJson);
    case PXTeqpComponentCarbonMonoxide:
        return std::string(kPhaseXpertTeqpCarbonMonoxideJson);
    case PXTeqpComponentHydrogenSulfide:
        return std::string(kPhaseXpertTeqpHydrogenSulfideJson);
    case PXTeqpComponentWater:
        return std::string(kPhaseXpertTeqpWaterJson);
    default:
        throw std::invalid_argument("Unsupported teqp component identifier.");
    }
}

double molar_mass_from_component_json(const std::string &component_json) {
    const auto fluid_json = nlohmann::json::parse(component_json);
    return fluid_json.at("EOS").at(0).at("molar_mass").get<double>();
}

template<typename Model>
double minimum_stability_eigenvalue(
    const Model &model,
    double temperature_k,
    const Eigen::ArrayXd &rhovec
);

class NComponentMultifluidModel {
public:
    using Model = decltype(teqp::build_multifluid_JSONstr(
        std::vector<std::string>{std::string{}},
        std::string{},
        std::string{}
    ));

    explicit NComponentMultifluidModel(
        const std::vector<int> &component_ids
    ) : component_json_strings_(componentJsonStrings(component_ids)),
        molar_masses_kg_mol_(molarMasses(component_json_strings_)),
        model_(teqp::build_multifluid_JSONstr(
            component_json_strings_,
            std::string(kPhaseXpertTeqpBinaryPairsJson),
            std::string(kPhaseXpertTeqpDepartureFunctionsJson)
        )) {}

    double pressurePa(
        double temperature_k,
        const Eigen::ArrayXd &molefractions,
        double total_molar_density_mol_m3
    ) const {
        const Eigen::ArrayXd rhovec = total_molar_density_mol_m3 * molefractions;
        using Derivatives = teqp::IsochoricDerivatives<Model, double, Eigen::ArrayXd>;
        auto derivatives = Derivatives::build_Psir_fgradHessian_autodiff(
            model_,
            temperature_k,
            rhovec
        );
        const double residual_pressure =
            -std::get<0>(derivatives)
            + (rhovec * std::get<1>(derivatives).array()).sum();
        return rhovec.sum() * model_.R(molefractions) * temperature_k
            + residual_pressure;
    }

    double mixtureMolarMassKgMol(const Eigen::ArrayXd &molefractions) const {
        if (molefractions.size()
            != static_cast<Eigen::Index>(molar_masses_kg_mol_.size())) {
            throw std::runtime_error("Mole-fraction vector does not match component count.");
        }
        double molar_mass = 0.0;
        for (Eigen::Index index = 0; index < molefractions.size(); ++index) {
            molar_mass += molefractions[index]
                * molar_masses_kg_mol_[static_cast<std::size_t>(index)];
        }
        return molar_mass;
    }

    auto psirDerivatives(double temperature_k, const Eigen::ArrayXd &rhovec) const {
        using Derivatives = teqp::IsochoricDerivatives<Model, double, Eigen::ArrayXd>;
        return Derivatives::build_Psir_fgradHessian_autodiff(
            model_, temperature_k, rhovec
        );
    }

    double gasConstant(const Eigen::ArrayXd &molefractions) const {
        return model_.R(molefractions);
    }

    Eigen::ArrayXd chemicalPotentials(
        double temperature_k,
        const Eigen::ArrayXd &rhovec
    ) const {
        if ((rhovec <= 0.0).any() || !rhovec.isFinite().all()) {
            throw std::runtime_error("Chemical potentials require finite positive partial densities.");
        }
        const auto derivatives = psirDerivatives(temperature_k, rhovec);
        const Eigen::ArrayXd composition = (rhovec / rhovec.sum()).eval();
        return (std::get<1>(derivatives).array()
            + gasConstant(composition) * temperature_k * rhovec.log()).eval();
    }

    double minimumStabilityEigenvalue(
        double temperature_k,
        const Eigen::ArrayXd &rhovec
    ) const {
        return minimum_stability_eigenvalue(model_, temperature_k, rhovec);
    }

private:
    static std::vector<std::string> componentJsonStrings(
        const std::vector<int> &component_ids
    ) {
        std::vector<std::string> strings;
        strings.reserve(component_ids.size());
        for (const int component_id : component_ids) {
            strings.push_back(component_json_for_id(component_id));
        }
        return strings;
    }

    static std::vector<double> molarMasses(
        const std::vector<std::string> &component_json_strings
    ) {
        std::vector<double> molar_masses;
        molar_masses.reserve(component_json_strings.size());
        for (const auto &component_json : component_json_strings) {
            molar_masses.push_back(molar_mass_from_component_json(component_json));
        }
        return molar_masses;
    }

    std::vector<std::string> component_json_strings_;
    std::vector<double> molar_masses_kg_mol_;
    Model model_;
};

struct BinaryThermodynamicProperties {
    double cv_j_kg_k;
    double cp_j_kg_k;
    double heat_capacity_ratio;
    double speed_of_sound_m_s;
    double speed_of_sound_squared_m2_s2;
    double dp_drho_molar_j_mol;
    double dp_dt_pa_k;
    double minimum_stability_eigenvalue;
};

template<typename Operation>
auto derivative_step(const char *label, Operation operation) {
    try {
        return operation();
    } catch (const std::exception &error) {
        std::string message = label;
        if (std::string(error.what()).empty()) {
            message += " failed with empty native exception.";
        } else {
            message += " failed: ";
            message += error.what();
        }
        throw std::runtime_error(message);
    } catch (...) {
        std::string message = label;
        message += " failed with unknown native exception.";
        throw std::runtime_error(message);
    }
}

struct BinaryCriticalPoint {
    bool converged;
    int iteration_count;
    double temperature_k;
    double pressure_pa;
    double molar_density_mol_m3;
    double density_kg_m3;
    double component2_mole_fraction;
    double minimum_stability_eigenvalue;
    double third_order_residual;
};

template<typename Model>
Eigen::MatrixXd total_psi_hessian(
    const Model &model,
    double temperature_k,
    const Eigen::ArrayXd &rhovec
) {
    const Eigen::ArrayXd molefractions = (rhovec / rhovec.sum()).eval();
    using Derivatives = teqp::IsochoricDerivatives<Model, double, Eigen::ArrayXd>;
    auto derivatives = Derivatives::build_Psir_fgradHessian_autodiff(
        model,
        temperature_k,
        rhovec
    );
    Eigen::MatrixXd hessian = std::get<2>(derivatives);
    const double gas_constant_temperature = model.R(molefractions) * temperature_k;
    for (Eigen::Index index = 0; index < rhovec.size(); ++index) {
        if (rhovec[index] <= 0 || !std::isfinite(rhovec[index])) {
            throw std::runtime_error("teqp mixture Hessian requires positive molar concentrations.");
        }
        hessian(index, index) += gas_constant_temperature / rhovec[index];
    }
    return hessian;
}

template<typename Model>
double minimum_stability_eigenvalue(
    const Model &model,
    double temperature_k,
    const Eigen::ArrayXd &rhovec
) {
    Eigen::SelfAdjointEigenSolver<Eigen::MatrixXd> eigen(
        total_psi_hessian(model, temperature_k, rhovec)
    );
    if (eigen.info() != Eigen::Success || eigen.eigenvalues().size() == 0) {
        return -std::numeric_limits<double>::infinity();
    }
    return eigen.eigenvalues()[0];
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

class EOSCGCarbonDioxideHydrogenModel {
public:
    using Model = decltype(teqp::build_multifluid_JSONstr(
        std::vector<std::string>{std::string{}, std::string{}},
        std::string{},
        std::string{}
    ));

    EOSCGCarbonDioxideHydrogenModel()
        : model_(teqp::build_multifluid_JSONstr(
              std::vector<std::string>{
                  std::string(kPhaseXpertTeqpCarbonDioxideJson),
                  std::string(kPhaseXpertTeqpHydrogenJson)
              },
              binaryPairsJson(),
              departureFunctionsJson()
          )) {}

    double gasConstant(const Eigen::ArrayXd &molefractions) const {
        return model_.R(molefractions);
    }

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

    double pressurePa(
        double temperature_k,
        const Eigen::ArrayXd &molefractions,
        double total_molar_density_mol_m3
    ) const {
        Eigen::ArrayXd rhovec = total_molar_density_mol_m3 * molefractions;
        using Derivatives = teqp::IsochoricDerivatives<Model, double, Eigen::ArrayXd>;
        auto derivatives = Derivatives::build_Psir_fgradHessian_autodiff(
            model_,
            temperature_k,
            rhovec
        );
        const double psir = std::get<0>(derivatives);
        const Eigen::ArrayXd gradient = std::get<1>(derivatives);
        return total_molar_density_mol_m3 * model_.R(molefractions) * temperature_k
            - psir + (rhovec * gradient).sum();
    }

    double mixtureMolarMassKgMol(double hydrogen_mole_fraction) const {
        return (1.0 - hydrogen_mole_fraction) * kCarbonDioxideMolarMassKgMol
            + hydrogen_mole_fraction * kHydrogenMolarMassKgMol;
    }

    BinaryThermodynamicProperties thermodynamicProperties(
        double temperature_k,
        double total_molar_density_mol_m3,
        double hydrogen_mole_fraction
    ) const {
        Eigen::ArrayXd molefractions(2);
        molefractions << 1.0 - hydrogen_mole_fraction, hydrogen_mole_fraction;
        return thermodynamicPropertiesForMolefractions(
            temperature_k,
            total_molar_density_mol_m3,
            molefractions,
            mixtureMolarMassKgMol(hydrogen_mole_fraction)
        );
    }

    Eigen::Array<double, 2, 1> criticalityConditions(
        double temperature_k,
        double total_molar_density_mol_m3,
        double hydrogen_mole_fraction
    ) const {
        Eigen::ArrayXd rhovec(2);
        rhovec << (1.0 - hydrogen_mole_fraction) * total_molar_density_mol_m3,
            hydrogen_mole_fraction * total_molar_density_mol_m3;
        const Eigen::ArrayXd molefractions = (rhovec / rhovec.sum()).eval();
        const double gas_constant_temperature =
            model_.R(molefractions) * temperature_k;
        Eigen::SelfAdjointEigenSolver<Eigen::MatrixXd> eigen(
            total_psi_hessian(model_, temperature_k, rhovec)
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

    BinaryCriticalPoint criticalPoint(double hydrogen_mole_fraction) const {
        return criticalPointForComposition(
            hydrogen_mole_fraction,
            mixtureMolarMassKgMol(hydrogen_mole_fraction)
        );
    }

private:
    BinaryCriticalPoint criticalPointForComposition(
        double component2_mole_fraction,
        double molar_mass_kg_mol
    ) const {
        const double critical_temperature_seed = co2_model().criticalTemperatureK();
        const double critical_density_seed = co2_model().criticalMolarDensityMolM3();
        std::vector<Eigen::Array<double, 2, 1>> seeds;
        for (double temperature_offset : {10.0, 5.0, 0.0, -2.0, -5.0, -10.0, -20.0}) {
            for (double density_factor : {0.65, 0.85, 1.0, 1.15, 1.35}) {
                seeds.push_back(
                    (Eigen::Array<double, 2, 1>()
                        << critical_temperature_seed + temperature_offset,
                        critical_density_seed * density_factor
                    ).finished()
                );
            }
        }

        BinaryCriticalPoint best{
            false,
            0,
            std::numeric_limits<double>::quiet_NaN(),
            std::numeric_limits<double>::quiet_NaN(),
            std::numeric_limits<double>::quiet_NaN(),
            std::numeric_limits<double>::quiet_NaN(),
            component2_mole_fraction,
            std::numeric_limits<double>::quiet_NaN(),
            std::numeric_limits<double>::quiet_NaN()
        };
        double best_norm = std::numeric_limits<double>::infinity();
        for (auto state : seeds) {
            int iteration_count = 0;
            for (int iteration = 0; iteration < 35; ++iteration) {
                if (!std::isfinite(state[0]) || !std::isfinite(state[1])
                    || state[0] <= 0 || state[1] <= 0) {
                    break;
                }
                Eigen::Array<double, 2, 1> residual;
                try {
                    residual = criticalityConditions(
                        state[0],
                        state[1],
                        component2_mole_fraction
                    );
                } catch (...) {
                    break;
                }
                const double residual_norm = residual.matrix().norm();
                if (std::isfinite(residual_norm) && residual_norm < best_norm) {
                    best_norm = residual_norm;
                    best.temperature_k = state[0];
                    best.molar_density_mol_m3 = state[1];
                    best.minimum_stability_eigenvalue = residual[0];
                    best.third_order_residual = residual[1];
                    best.iteration_count = iteration_count;
                }
                const double temperature_step = std::max(1e-4, 1e-6 * state[0]);
                const double density_step = std::max(1e-3, 1e-6 * state[1]);
                Eigen::Matrix2d jacobian;
                try {
                    jacobian.col(0) =
                        ((criticalityConditions(
                            state[0] + temperature_step,
                            state[1],
                            component2_mole_fraction
                        ) - criticalityConditions(
                            state[0] - temperature_step,
                            state[1],
                            component2_mole_fraction
                        )) / (2.0 * temperature_step)).matrix();
                    jacobian.col(1) =
                        ((criticalityConditions(
                            state[0],
                            state[1] + density_step,
                            component2_mole_fraction
                        ) - criticalityConditions(
                            state[0],
                            state[1] - density_step,
                            component2_mole_fraction
                        )) / (2.0 * density_step)).matrix();
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
                iteration_count = iteration + 1;
                if (std::abs(update[0]) < 1e-6
                    && std::abs(update[1]) < 1e-6 * std::max(1.0, state[1])) {
                    break;
                }
            }
            if (!std::isfinite(state[0]) || !std::isfinite(state[1])
                || state[0] <= 0 || state[1] <= 0
                || state[0] < 150.0 || state[0] > 600.0) {
                continue;
            }
            try {
                const auto residual = criticalityConditions(
                    state[0],
                    state[1],
                    component2_mole_fraction
                );
                if (std::abs(residual[0]) < 1e-5
                    && std::abs(residual[1]) < 1e-7) {
                    Eigen::ArrayXd molefractions(2);
                    molefractions << 1.0 - component2_mole_fraction,
                        component2_mole_fraction;
                    best.converged = true;
                    best.temperature_k = state[0];
                    best.molar_density_mol_m3 = state[1];
                    best.density_kg_m3 = state[1] * molar_mass_kg_mol;
                    best.pressure_pa = pressurePa(
                        state[0],
                        molefractions,
                        state[1]
                    );
                    best.component2_mole_fraction = component2_mole_fraction;
                    best.minimum_stability_eigenvalue = residual[0];
                    best.third_order_residual = residual[1];
                    return best;
                }
            } catch (...) {
                continue;
            }
        }
        return best;
    }

    BinaryThermodynamicProperties thermodynamicPropertiesForMolefractions(
        double temperature_k,
        double total_molar_density_mol_m3,
        const Eigen::ArrayXd &molefractions,
        double molar_mass_kg_mol
    ) const {
        // Fixed-composition homogeneous multifluid Helmholtz relations.
        // teqp's TDXDerivatives evaluate residual and ideal Helmholtz
        // derivatives at fixed z, including composition-dependent reducing
        // density/temperature functions in the residual EOS.
        using ResidualDerivatives =
            teqp::TDXDerivatives<Model, double, Eigen::ArrayXd>;
        using IdealDerivatives =
            teqp::TDXDerivatives<teqp::IdealHelmholtz, double, Eigen::ArrayXd>;
        const auto residual_density_derivatives = derivative_step(
            "residual density derivatives",
            [&]() {
                return ResidualDerivatives::template get_Ar0n<2, teqp::ADBackends::autodiff>(
                model_,
                temperature_k,
                total_molar_density_mol_m3,
                molefractions
                );
            }
        );
        const double ar01 = residual_density_derivatives[1];
        const double ar02 = residual_density_derivatives[2];
        const double ar11 = derivative_step(
            "residual mixed temperature-density derivative",
            [&]() {
                return ResidualDerivatives::template get_Arxy<1, 1, teqp::ADBackends::autodiff>(
                model_,
                temperature_k,
                total_molar_density_mol_m3,
                molefractions
                );
            }
        );
        const double ar20 = derivative_step(
            "residual second temperature derivative",
            [&]() {
                return ResidualDerivatives::template get_Arxy<2, 0, teqp::ADBackends::autodiff>(
                model_,
                temperature_k,
                total_molar_density_mol_m3,
                molefractions
                );
            }
        );
        const double a020 = derivative_step(
            "ideal second temperature derivative",
            [&]() {
                return IdealDerivatives::template get_Arxy<2, 0, teqp::ADBackends::autodiff>(
                ideal_model_,
                temperature_k,
                total_molar_density_mol_m3,
                molefractions
                );
            }
        );

        const double cv_over_r = -(a020 + ar20);
        const double pressure_derivative_dimensionless = 1.0 + 2.0 * ar01 + ar02;
        const double temperature_density_coupling = 1.0 + ar01 - ar11;
        const Eigen::ArrayXd rhovec = total_molar_density_mol_m3 * molefractions;
        const double minimum_eigenvalue =
            minimum_stability_eigenvalue(model_, temperature_k, rhovec);
        if (!std::isfinite(cv_over_r)
            || !std::isfinite(pressure_derivative_dimensionless)
            || !std::isfinite(temperature_density_coupling)
            || !std::isfinite(minimum_eigenvalue)
            || cv_over_r <= 0.0
            || pressure_derivative_dimensionless <= 0.0
            || minimum_eigenvalue <= 0.0) {
            throw std::runtime_error("teqp returned non-physical mixture Helmholtz derivatives.");
        }
        const double cp_over_r = cv_over_r
            + temperature_density_coupling * temperature_density_coupling
                / pressure_derivative_dimensionless;
        const double speed_dimensionless = pressure_derivative_dimensionless
            + temperature_density_coupling * temperature_density_coupling
                / cv_over_r;
        if (!std::isfinite(cp_over_r)
            || !std::isfinite(speed_dimensionless)
            || cp_over_r <= cv_over_r
            || speed_dimensionless <= 0.0) {
            throw std::runtime_error("teqp returned non-physical mixture Cp or speed-of-sound derivatives.");
        }

        const double gas_constant = model_.R(molefractions);
        const double cv_molar = cv_over_r * gas_constant;
        const double cp_molar = cp_over_r * gas_constant;
        const double speed_squared =
            speed_dimensionless * gas_constant * temperature_k / molar_mass_kg_mol;
        const double dp_drho_molar =
            gas_constant * temperature_k * pressure_derivative_dimensionless;
        const double dp_dt =
            total_molar_density_mol_m3 * gas_constant
                * temperature_density_coupling;
        return {
            cv_molar / molar_mass_kg_mol,
            cp_molar / molar_mass_kg_mol,
            cp_over_r / cv_over_r,
            std::sqrt(speed_squared),
            speed_squared,
            dp_drho_molar,
            dp_dt,
            minimum_eigenvalue
        };
    }

    static std::string binaryPairsJson() {
        return R"PXTEQPJSON([
            {
                "Name1": "CarbonDioxide",
                "Name2": "Hydrogen",
                "CAS1": "124-38-9",
                "CAS2": "1333-74-0",
                "BibTeX": "Neumann-IJT-2023",
                "betaT": 0.979,
                "gammaT": 1.961,
                "betaV": 1.198,
                "gammaV": 0.842,
                "F": 1.0,
                "function": "EOSCG-CarbonDioxide-Hydrogen"
            }
        ])PXTEQPJSON";
    }

    static std::string departureFunctionsJson() {
        return R"PXTEQPJSON([
            {
                "Name": "EOSCG-CarbonDioxide-Hydrogen",
                "BibTeX": "Neumann-IJT-2023",
                "type": "Gaussian+Exponential",
                "Npower": 2,
                "d": [1, 2, 1, 2, 3, 1],
                "t": [1.47, 1.17, 1.95, 0.31, 1.412, 2.28],
                "n": [3.56, -1.036, -4.835, 12.38, -2.65, -3.3],
                "eta": [0.0, 0.0, 0.58, 0.2, 0.292, 0.12],
                "beta": [0.0, 0.0, 0.465, 0.82, 0.52, 1.0],
                "gamma": [0.0, 0.0, 0.17, 2.11, 1.49, 1.73],
                "epsilon": [0.0, 0.0, 0.52, 0.15, 0.24, 0.15]
            }
        ])PXTEQPJSON";
    }

    Model model_;
    teqp::IdealHelmholtz ideal_model_ = ideal_terms_for_components({
        std::string(kPhaseXpertTeqpCarbonDioxideJson),
        std::string(kPhaseXpertTeqpHydrogenJson)
    });
};

EOSCGCarbonDioxideHydrogenModel &eoscg_co2_h2_model() {
    static EOSCGCarbonDioxideHydrogenModel model;
    return model;
}

class EOSCGCarbonDioxideMethaneModel {
public:
    using Model = decltype(teqp::build_multifluid_JSONstr(
        std::vector<std::string>{std::string{}, std::string{}},
        std::string{},
        std::string{}
    ));

    EOSCGCarbonDioxideMethaneModel()
        : model_(teqp::build_multifluid_JSONstr(
              std::vector<std::string>{
                  std::string(kPhaseXpertTeqpCarbonDioxideJson),
                  std::string(kPhaseXpertTeqpMethaneJson)
              },
              binaryPairsJson(),
              departureFunctionsJson()
          )) {}

    double gasConstant(const Eigen::ArrayXd &molefractions) const {
        return model_.R(molefractions);
    }

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

    double pressurePa(
        double temperature_k,
        const Eigen::ArrayXd &molefractions,
        double total_molar_density_mol_m3
    ) const {
        Eigen::ArrayXd rhovec = total_molar_density_mol_m3 * molefractions;
        using Derivatives = teqp::IsochoricDerivatives<Model, double, Eigen::ArrayXd>;
        auto derivatives = Derivatives::build_Psir_fgradHessian_autodiff(
            model_,
            temperature_k,
            rhovec
        );
        const double psir = std::get<0>(derivatives);
        const Eigen::ArrayXd gradient = std::get<1>(derivatives);
        return total_molar_density_mol_m3 * model_.R(molefractions) * temperature_k
            - psir + (rhovec * gradient).sum();
    }

    double mixtureMolarMassKgMol(double methane_mole_fraction) const {
        return (1.0 - methane_mole_fraction) * kCarbonDioxideMolarMassKgMol
            + methane_mole_fraction * kMethaneMolarMassKgMol;
    }

    BinaryThermodynamicProperties thermodynamicProperties(
        double temperature_k,
        double total_molar_density_mol_m3,
        double methane_mole_fraction
    ) const {
        Eigen::ArrayXd molefractions(2);
        molefractions << 1.0 - methane_mole_fraction, methane_mole_fraction;
        return thermodynamicPropertiesForMolefractions(
            temperature_k,
            total_molar_density_mol_m3,
            molefractions,
            mixtureMolarMassKgMol(methane_mole_fraction)
        );
    }

    Eigen::Array<double, 2, 1> criticalityConditions(
        double temperature_k,
        double total_molar_density_mol_m3,
        double methane_mole_fraction
    ) const {
        Eigen::ArrayXd rhovec(2);
        rhovec << (1.0 - methane_mole_fraction) * total_molar_density_mol_m3,
            methane_mole_fraction * total_molar_density_mol_m3;
        const Eigen::ArrayXd molefractions = (rhovec / rhovec.sum()).eval();
        const double gas_constant_temperature =
            model_.R(molefractions) * temperature_k;
        Eigen::SelfAdjointEigenSolver<Eigen::MatrixXd> eigen(
            total_psi_hessian(model_, temperature_k, rhovec)
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

    BinaryCriticalPoint criticalPoint(double methane_mole_fraction) const {
        return criticalPointForComposition(
            methane_mole_fraction,
            mixtureMolarMassKgMol(methane_mole_fraction)
        );
    }

private:
    BinaryCriticalPoint criticalPointForComposition(
        double component2_mole_fraction,
        double molar_mass_kg_mol
    ) const {
        const double critical_temperature_seed = co2_model().criticalTemperatureK();
        const double critical_density_seed = co2_model().criticalMolarDensityMolM3();
        std::vector<Eigen::Array<double, 2, 1>> seeds;
        for (double temperature_offset : {10.0, 5.0, 0.0, -2.0, -5.0, -10.0, -20.0}) {
            for (double density_factor : {0.65, 0.85, 1.0, 1.15, 1.35}) {
                seeds.push_back(
                    (Eigen::Array<double, 2, 1>()
                        << critical_temperature_seed + temperature_offset,
                        critical_density_seed * density_factor
                    ).finished()
                );
            }
        }

        BinaryCriticalPoint best{
            false,
            0,
            std::numeric_limits<double>::quiet_NaN(),
            std::numeric_limits<double>::quiet_NaN(),
            std::numeric_limits<double>::quiet_NaN(),
            std::numeric_limits<double>::quiet_NaN(),
            component2_mole_fraction,
            std::numeric_limits<double>::quiet_NaN(),
            std::numeric_limits<double>::quiet_NaN()
        };
        double best_norm = std::numeric_limits<double>::infinity();
        for (auto state : seeds) {
            int iteration_count = 0;
            for (int iteration = 0; iteration < 35; ++iteration) {
                if (!std::isfinite(state[0]) || !std::isfinite(state[1])
                    || state[0] <= 0 || state[1] <= 0) {
                    break;
                }
                Eigen::Array<double, 2, 1> residual;
                try {
                    residual = criticalityConditions(
                        state[0],
                        state[1],
                        component2_mole_fraction
                    );
                } catch (...) {
                    break;
                }
                const double residual_norm = residual.matrix().norm();
                if (std::isfinite(residual_norm) && residual_norm < best_norm) {
                    best_norm = residual_norm;
                    best.temperature_k = state[0];
                    best.molar_density_mol_m3 = state[1];
                    best.minimum_stability_eigenvalue = residual[0];
                    best.third_order_residual = residual[1];
                    best.iteration_count = iteration_count;
                }
                const double temperature_step = std::max(1e-4, 1e-6 * state[0]);
                const double density_step = std::max(1e-3, 1e-6 * state[1]);
                Eigen::Matrix2d jacobian;
                try {
                    jacobian.col(0) =
                        ((criticalityConditions(
                            state[0] + temperature_step,
                            state[1],
                            component2_mole_fraction
                        ) - criticalityConditions(
                            state[0] - temperature_step,
                            state[1],
                            component2_mole_fraction
                        )) / (2.0 * temperature_step)).matrix();
                    jacobian.col(1) =
                        ((criticalityConditions(
                            state[0],
                            state[1] + density_step,
                            component2_mole_fraction
                        ) - criticalityConditions(
                            state[0],
                            state[1] - density_step,
                            component2_mole_fraction
                        )) / (2.0 * density_step)).matrix();
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
                iteration_count = iteration + 1;
                if (std::abs(update[0]) < 1e-6
                    && std::abs(update[1]) < 1e-6 * std::max(1.0, state[1])) {
                    break;
                }
            }
            if (!std::isfinite(state[0]) || !std::isfinite(state[1])
                || state[0] <= 0 || state[1] <= 0
                || state[0] < 150.0 || state[0] > 600.0) {
                continue;
            }
            try {
                const auto residual = criticalityConditions(
                    state[0],
                    state[1],
                    component2_mole_fraction
                );
                if (std::abs(residual[0]) < 1e-5
                    && std::abs(residual[1]) < 1e-7) {
                    Eigen::ArrayXd molefractions(2);
                    molefractions << 1.0 - component2_mole_fraction,
                        component2_mole_fraction;
                    best.converged = true;
                    best.temperature_k = state[0];
                    best.molar_density_mol_m3 = state[1];
                    best.density_kg_m3 = state[1] * molar_mass_kg_mol;
                    best.pressure_pa = pressurePa(
                        state[0],
                        molefractions,
                        state[1]
                    );
                    best.component2_mole_fraction = component2_mole_fraction;
                    best.minimum_stability_eigenvalue = residual[0];
                    best.third_order_residual = residual[1];
                    return best;
                }
            } catch (...) {
                continue;
            }
        }
        return best;
    }

    BinaryThermodynamicProperties thermodynamicPropertiesForMolefractions(
        double temperature_k,
        double total_molar_density_mol_m3,
        const Eigen::ArrayXd &molefractions,
        double molar_mass_kg_mol
    ) const {
        // Fixed-composition homogeneous multifluid Helmholtz relations.
        // teqp supplies the analytic residual derivatives; the ideal mixture
        // contribution is built from the component ideal-gas Helmholtz terms.
        using ResidualDerivatives =
            teqp::TDXDerivatives<Model, double, Eigen::ArrayXd>;
        using IdealDerivatives =
            teqp::TDXDerivatives<teqp::IdealHelmholtz, double, Eigen::ArrayXd>;
        const auto residual_density_derivatives = derivative_step(
            "residual density derivatives",
            [&]() {
                return ResidualDerivatives::template get_Ar0n<2, teqp::ADBackends::autodiff>(
                model_,
                temperature_k,
                total_molar_density_mol_m3,
                molefractions
                );
            }
        );
        const double ar01 = residual_density_derivatives[1];
        const double ar02 = residual_density_derivatives[2];
        const double ar11 = derivative_step(
            "residual mixed temperature-density derivative",
            [&]() {
                return ResidualDerivatives::template get_Arxy<1, 1, teqp::ADBackends::autodiff>(
                model_,
                temperature_k,
                total_molar_density_mol_m3,
                molefractions
                );
            }
        );
        const double ar20 = derivative_step(
            "residual second temperature derivative",
            [&]() {
                return ResidualDerivatives::template get_Arxy<2, 0, teqp::ADBackends::autodiff>(
                model_,
                temperature_k,
                total_molar_density_mol_m3,
                molefractions
                );
            }
        );
        const double a020 = derivative_step(
            "ideal second temperature derivative",
            [&]() {
                return IdealDerivatives::template get_Arxy<2, 0, teqp::ADBackends::autodiff>(
                ideal_model_,
                temperature_k,
                total_molar_density_mol_m3,
                molefractions
                );
            }
        );

        const double cv_over_r = -(a020 + ar20);
        const double pressure_derivative_dimensionless = 1.0 + 2.0 * ar01 + ar02;
        const double temperature_density_coupling = 1.0 + ar01 - ar11;
        const Eigen::ArrayXd rhovec = total_molar_density_mol_m3 * molefractions;
        const double minimum_eigenvalue =
            minimum_stability_eigenvalue(model_, temperature_k, rhovec);
        if (!std::isfinite(cv_over_r)
            || !std::isfinite(pressure_derivative_dimensionless)
            || !std::isfinite(temperature_density_coupling)
            || !std::isfinite(minimum_eigenvalue)
            || cv_over_r <= 0.0
            || pressure_derivative_dimensionless <= 0.0
            || minimum_eigenvalue <= 0.0) {
            throw std::runtime_error("teqp returned non-physical mixture Helmholtz derivatives.");
        }
        const double cp_over_r = cv_over_r
            + temperature_density_coupling * temperature_density_coupling
                / pressure_derivative_dimensionless;
        const double speed_dimensionless = pressure_derivative_dimensionless
            + temperature_density_coupling * temperature_density_coupling
                / cv_over_r;
        if (!std::isfinite(cp_over_r)
            || !std::isfinite(speed_dimensionless)
            || cp_over_r <= cv_over_r
            || speed_dimensionless <= 0.0) {
            throw std::runtime_error("teqp returned non-physical mixture Cp or speed-of-sound derivatives.");
        }

        const double gas_constant = model_.R(molefractions);
        const double cv_molar = cv_over_r * gas_constant;
        const double cp_molar = cp_over_r * gas_constant;
        const double speed_squared =
            speed_dimensionless * gas_constant * temperature_k / molar_mass_kg_mol;
        const double dp_drho_molar =
            gas_constant * temperature_k * pressure_derivative_dimensionless;
        const double dp_dt =
            total_molar_density_mol_m3 * gas_constant
                * temperature_density_coupling;
        return {
            cv_molar / molar_mass_kg_mol,
            cp_molar / molar_mass_kg_mol,
            cp_over_r / cv_over_r,
            std::sqrt(speed_squared),
            speed_squared,
            dp_drho_molar,
            dp_dt,
            minimum_eigenvalue
        };
    }

    static std::string binaryPairsJson() {
        return R"PXTEQPJSON([
            {
                "Name1": "CarbonDioxide",
                "Name2": "Methane",
                "CAS1": "124-38-9",
                "CAS2": "74-82-8",
                "BibTeX": "Neumann-IJT-2023",
                "betaT": 0.9778765215758676,
                "gammaT": 0.975665,
                "betaV": 1.000482232436034,
                "gammaV": 1.002807,
                "F": 1.0,
                "function": "EOSCG-Methane-CarbonDioxide"
            }
        ])PXTEQPJSON";
    }

    static std::string departureFunctionsJson() {
        return R"PXTEQPJSON([
            {
                "Name": "EOSCG-Methane-CarbonDioxide",
                "BibTeX": "Neumann-IJT-2023",
                "type": "GERG-2008",
                "Npower": 3,
                "d": [1, 2, 3, 1, 2, 3],
                "t": [2.6, 1.95, 0.0, 3.95, 7.95, 8.0],
                "n": [-0.10859387354942, 0.080228576727389, -0.0093303985115717, 0.040989274005848, -0.24338019772494, 0.23855347281124],
                "eta": [0.0, 0.0, 0.0, 1.0, 0.5, 0.0],
                "beta": [0.0, 0.0, 0.0, 1.0, 2.0, 3.0],
                "gamma": [0.0, 0.0, 0.0, 0.5, 0.5, 0.5],
                "epsilon": [0.0, 0.0, 0.0, 0.5, 0.5, 0.5]
            }
        ])PXTEQPJSON";
    }

    Model model_;
    teqp::IdealHelmholtz ideal_model_ = ideal_terms_for_components({
        std::string(kPhaseXpertTeqpCarbonDioxideJson),
        std::string(kPhaseXpertTeqpMethaneJson)
    });
};

EOSCGCarbonDioxideMethaneModel &eoscg_co2_ch4_model() {
    static EOSCGCarbonDioxideMethaneModel model;
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

bool valid_binary_fraction(double component2_mole_fraction) {
    return std::isfinite(component2_mole_fraction)
        && component2_mole_fraction > 0.0
        && component2_mole_fraction < 1.0;
}

template<typename BinaryModel>
BinaryVLEState solve_binary_vle_tx_once(
    const BinaryModel &model,
    double temperature_k,
    Eigen::ArrayXd liquid_initial,
    Eigen::ArrayXd vapor_initial,
    double liquid_component2_mole_fraction
) {
    constexpr int kComponentCount = 2;
    Eigen::ArrayXd xspec(kComponentCount);
    xspec << 1.0 - liquid_component2_mole_fraction,
        liquid_component2_mole_fraction;

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

template<typename Model>
std::vector<Root> density_roots_for_molefractions(
    const Model &model,
    double pressure_pa,
    double temperature_k,
    const Eigen::ArrayXd &molefractions
) {
    std::vector<Root> roots;
    auto residual = [&](double molar_density) {
        return model.pressurePa(
            temperature_k,
            molefractions,
            molar_density
        ) - pressure_pa;
    };

    double previous_density = 1e-6;
    double previous_residual = residual(previous_density);
    for (int index = 1; index <= kScanPointCount * 3; ++index) {
        const double fraction = static_cast<double>(index)
            / static_cast<double>(kScanPointCount * 3);
        const double log_density = std::log(1e-6)
            + (std::log(kMaximumMolarDensity) - std::log(1e-6)) * fraction;
        const double density = std::exp(log_density);
        const double current_residual = residual(density);
        if (std::isfinite(previous_residual) && std::isfinite(current_residual)
            && previous_residual * current_residual <= 0.0) {
            double lower = previous_density;
            double upper = density;
            double lower_residual = previous_residual;
            for (int iteration = 0; iteration < kBisectionIterations; ++iteration) {
                const double midpoint = 0.5 * (lower + upper);
                const double midpoint_residual = residual(midpoint);
                if (!std::isfinite(midpoint_residual)) {
                    upper = midpoint;
                    continue;
                }
                if (std::abs(midpoint_residual)
                    < 1e-8 * std::max(1.0, pressure_pa)) {
                    lower = midpoint;
                    upper = midpoint;
                    break;
                }
                if (lower_residual * midpoint_residual <= 0.0) {
                    upper = midpoint;
                } else {
                    lower = midpoint;
                    lower_residual = midpoint_residual;
                }
            }
            const double root = 0.5 * (lower + upper);
            if (roots.empty()
                || std::abs(root - roots.back().molar_density_mol_m3)
                    > 1e-5 * std::max(1.0, root)) {
                roots.push_back({root});
            }
        }
        previous_density = density;
        previous_residual = current_residual;
    }
    return roots;
}


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

template<typename BinaryModel>
BinaryVLEState solve_binary_vle_tx(
    const BinaryModel &model,
    double temperature_k,
    double liquid_component2_mole_fraction
) {
    if (!std::isfinite(temperature_k) || temperature_k <= 0) {
        throw std::invalid_argument("Temperature must be finite and positive.");
    }
    if (!valid_binary_fraction(liquid_component2_mole_fraction)) {
        throw std::invalid_argument("Liquid component-2 mole fraction must be finite and in (0, 1).");
    }
    const auto pure_saturation = co2_model().saturationState(temperature_k);

    constexpr double kInitialComponent2Seed = 1e-8;
    Eigen::ArrayXd liquid(2), vapor(2);
    liquid << pure_saturation.liquid_molar_density_mol_m3 * (1.0 - kInitialComponent2Seed),
        pure_saturation.liquid_molar_density_mol_m3 * kInitialComponent2Seed;
    vapor << pure_saturation.vapor_molar_density_mol_m3 * (1.0 - kInitialComponent2Seed),
        pure_saturation.vapor_molar_density_mol_m3 * kInitialComponent2Seed;

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
            [liquid_component2_mole_fraction](double value) {
                return value >= liquid_component2_mole_fraction;
            }
        ),
        targets.end()
    );
    targets.push_back(liquid_component2_mole_fraction);
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
            throw std::runtime_error("teqp binary mix_VLE_Tx did not converge during continuation.");
        }
        liquid = state.rhovec_liquid;
        vapor = state.rhovec_vapor;
    }
    return state;
}

template<typename BinaryModel>
BinaryVLEState solve_binary_vle_tx_with_initial_guess(
    const BinaryModel &model,
    double temperature_k,
    double liquid_component2_mole_fraction,
    double liquid_molar_density_mol_m3,
    double vapor_molar_density_mol_m3,
    double vapor_component2_mole_fraction
) {
    if (!std::isfinite(temperature_k) || temperature_k <= 0) {
        throw std::invalid_argument("Temperature must be finite and positive.");
    }
    if (!valid_binary_fraction(liquid_component2_mole_fraction)) {
        throw std::invalid_argument("Liquid component-2 mole fraction must be finite and in (0, 1).");
    }
    if (!valid_binary_fraction(vapor_component2_mole_fraction)) {
        throw std::invalid_argument("Vapor component-2 mole fraction must be finite and in (0, 1).");
    }
    if (!std::isfinite(liquid_molar_density_mol_m3)
        || !std::isfinite(vapor_molar_density_mol_m3)
        || liquid_molar_density_mol_m3 <= 0.0
        || vapor_molar_density_mol_m3 <= 0.0) {
        throw std::invalid_argument("Initial molar densities must be finite and positive.");
    }

    Eigen::ArrayXd liquid(2), vapor(2);
    liquid << liquid_molar_density_mol_m3 * (1.0 - liquid_component2_mole_fraction),
        liquid_molar_density_mol_m3 * liquid_component2_mole_fraction;
    vapor << vapor_molar_density_mol_m3 * (1.0 - vapor_component2_mole_fraction),
        vapor_molar_density_mol_m3 * vapor_component2_mole_fraction;

    auto state = solve_binary_vle_tx_once(
        model,
        temperature_k,
        liquid,
        vapor,
        liquid_component2_mole_fraction
    );
    if (!state.converged) {
        throw std::runtime_error(
            "teqp binary mix_VLE_Tx did not converge from the supplied initial guess."
        );
    }
    return state;
}

BinaryVLEState solve_binary_vle_tx(
    double temperature_k,
    double liquid_nitrogen_mole_fraction
) {
    return solve_binary_vle_tx(
        co2_n2_model(),
        temperature_k,
        liquid_nitrogen_mole_fraction
    );
}

template<typename BinaryModel>
BinaryVLEState solve_binary_dew_for_vapor_composition(
    const BinaryModel &model,
    double temperature_k,
    double vapor_component2_mole_fraction
) {
    if (!valid_binary_fraction(vapor_component2_mole_fraction)) {
        throw std::invalid_argument("Vapor component-2 mole fraction must be finite and in (0, 1).");
    }

    double lower = 1e-8;
    auto lower_state = solve_binary_vle_tx(model, temperature_k, lower);
    auto lower_y = lower_state.rhovec_vapor(1) / lower_state.rhovec_vapor.sum();
    if (lower_y > vapor_component2_mole_fraction) {
        return lower_state;
    }

    double upper = std::min(0.5, std::max(0.001, vapor_component2_mole_fraction));
    BinaryVLEState upper_state = solve_binary_vle_tx(model, temperature_k, upper);
    double upper_y = upper_state.rhovec_vapor(1) / upper_state.rhovec_vapor.sum();
    while (upper_y < vapor_component2_mole_fraction && upper < 0.95) {
        upper = std::min(0.95, upper * 1.5);
        upper_state = solve_binary_vle_tx(model, temperature_k, upper);
        upper_y = upper_state.rhovec_vapor(1) / upper_state.rhovec_vapor.sum();
    }
    if (upper_y < vapor_component2_mole_fraction) {
        throw std::runtime_error("teqp binary dew solve could not bracket the vapor composition.");
    }

    BinaryVLEState mid_state = upper_state;
    for (int iteration = 0; iteration < 40; ++iteration) {
        const double mid = 0.5 * (lower + upper);
        mid_state = solve_binary_vle_tx(model, temperature_k, mid);
        const double mid_y = mid_state.rhovec_vapor(1) / mid_state.rhovec_vapor.sum();
        if (std::abs(mid_y - vapor_component2_mole_fraction) <= 1e-8) {
            return mid_state;
        }
        if (mid_y < vapor_component2_mole_fraction) {
            lower = mid;
            lower_state = mid_state;
        } else {
            upper = mid;
            upper_state = mid_state;
        }
    }
    return mid_state;
}

BinaryVLEState solve_binary_dew_for_vapor_composition(
    double temperature_k,
    double vapor_nitrogen_mole_fraction
) {
    return solve_binary_dew_for_vapor_composition(
        co2_n2_model(),
        temperature_k,
        vapor_nitrogen_mole_fraction
    );
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

void fill_generic_binary_vle_result(
    const BinaryVLEState &state,
    PXTeqpGenericBinaryVLEResult *result
) {
    result->converged = state.converged ? 1 : 0;
    result->iteration_count = state.iteration_count;
    result->return_code = state.return_code;
    result->pressure_pa = state.pressure_pa;
    result->liquid_molar_density_mol_m3 = state.rhovec_liquid.sum();
    result->vapor_molar_density_mol_m3 = state.rhovec_vapor.sum();
    result->liquid_component1_mole_fraction =
        state.rhovec_liquid(0) / state.rhovec_liquid.sum();
    result->liquid_component2_mole_fraction =
        state.rhovec_liquid(1) / state.rhovec_liquid.sum();
    result->vapor_component1_mole_fraction =
        state.rhovec_vapor(0) / state.rhovec_vapor.sum();
    result->vapor_component2_mole_fraction =
        state.rhovec_vapor(1) / state.rhovec_vapor.sum();
    result->pressure_residual_pa = state.residual(2);
    result->component1_chemical_potential_residual = state.residual(0);
    result->component2_chemical_potential_residual = state.residual(1);
}

template<typename BinaryModel>
void fill_binary_thermodynamic_result(
    const BinaryModel &model,
    double pressure_pa,
    double temperature_k,
    double component2_mole_fraction,
    PXTeqpPhase phase,
    PXTeqpMixtureThermodynamicResult *result
) {
    Eigen::ArrayXd molefractions(2);
    molefractions << 1.0 - component2_mole_fraction, component2_mole_fraction;
    const auto roots = density_roots_for_molefractions(
        model,
        pressure_pa,
        temperature_k,
        molefractions
    );
    if (roots.empty()) {
        throw std::runtime_error("teqp did not find a finite EOS-CG mixture density root.");
    }
    const auto selected = lowest_density_root(roots);
    const auto properties = derivative_step(
        "binary thermodynamic-property evaluation",
        [&]() {
            return model.thermodynamicProperties(
                temperature_k,
                selected.molar_density_mol_m3,
                component2_mole_fraction
            );
        }
    );
    const double density = selected.molar_density_mol_m3
        * model.mixtureMolarMassKgMol(component2_mole_fraction);
    if (!std::isfinite(density)
        || !std::isfinite(properties.cv_j_kg_k)
        || !std::isfinite(properties.cp_j_kg_k)
        || !std::isfinite(properties.heat_capacity_ratio)
        || !std::isfinite(properties.speed_of_sound_m_s)
        || !std::isfinite(properties.speed_of_sound_squared_m2_s2)
        || !std::isfinite(properties.dp_drho_molar_j_mol)
        || !std::isfinite(properties.dp_dt_pa_k)
        || density <= 0.0
        || properties.cv_j_kg_k <= 0.0
        || properties.cp_j_kg_k <= properties.cv_j_kg_k
        || properties.heat_capacity_ratio <= 1.0
        || properties.speed_of_sound_m_s <= 0.0
        || properties.speed_of_sound_squared_m2_s2 <= 0.0
        || properties.dp_drho_molar_j_mol <= 0.0) {
        throw std::runtime_error("teqp returned invalid EOS-CG mixture thermodynamic properties.");
    }

    result->density_kg_m3 = density;
    result->molar_density_mol_m3 = selected.molar_density_mol_m3;
    result->pressure_pa = pressure_pa;
    result->dp_drho_molar_j_mol = properties.dp_drho_molar_j_mol;
    result->dp_dt_pa_k = properties.dp_dt_pa_k;
    result->isochoric_heat_capacity_j_kg_k = properties.cv_j_kg_k;
    result->isobaric_heat_capacity_j_kg_k = properties.cp_j_kg_k;
    result->heat_capacity_ratio = properties.heat_capacity_ratio;
    result->speed_of_sound_m_s = properties.speed_of_sound_m_s;
    result->speed_of_sound_squared_m2_s2 =
        properties.speed_of_sound_squared_m2_s2;
    result->minimum_stability_eigenvalue =
        properties.minimum_stability_eigenvalue;
    result->density_root_count = static_cast<int>(roots.size());
    result->converged = 1;
    result->phase = phase;
}

BinaryVLEState solve_binary_vle_tx(
    PXTeqpBinaryFormulation formulation,
    double temperature_k,
    double liquid_component2_mole_fraction
) {
    switch (formulation) {
    case PXTeqpBinaryFormulationCO2N2:
        return solve_binary_vle_tx(
            co2_n2_model(),
            temperature_k,
            liquid_component2_mole_fraction
        );
    case PXTeqpBinaryFormulationEOSCGCO2H2:
        return solve_binary_vle_tx(
            eoscg_co2_h2_model(),
            temperature_k,
            liquid_component2_mole_fraction
        );
    case PXTeqpBinaryFormulationEOSCGCO2CH4:
        return solve_binary_vle_tx(
            eoscg_co2_ch4_model(),
            temperature_k,
            liquid_component2_mole_fraction
        );
    default:
        throw std::invalid_argument("Unsupported binary teqp formulation.");
    }
}

BinaryVLEState solve_binary_vle_tx_with_initial_guess(
    PXTeqpBinaryFormulation formulation,
    double temperature_k,
    double liquid_component2_mole_fraction,
    const PXTeqpBinaryVLEInitialGuess &initial_guess
) {
    switch (formulation) {
    case PXTeqpBinaryFormulationCO2N2:
        return solve_binary_vle_tx_with_initial_guess(
            co2_n2_model(),
            temperature_k,
            liquid_component2_mole_fraction,
            initial_guess.liquid_molar_density_mol_m3,
            initial_guess.vapor_molar_density_mol_m3,
            initial_guess.vapor_component2_mole_fraction
        );
    case PXTeqpBinaryFormulationEOSCGCO2H2:
        return solve_binary_vle_tx_with_initial_guess(
            eoscg_co2_h2_model(),
            temperature_k,
            liquid_component2_mole_fraction,
            initial_guess.liquid_molar_density_mol_m3,
            initial_guess.vapor_molar_density_mol_m3,
            initial_guess.vapor_component2_mole_fraction
        );
    case PXTeqpBinaryFormulationEOSCGCO2CH4:
        return solve_binary_vle_tx_with_initial_guess(
            eoscg_co2_ch4_model(),
            temperature_k,
            liquid_component2_mole_fraction,
            initial_guess.liquid_molar_density_mol_m3,
            initial_guess.vapor_molar_density_mol_m3,
            initial_guess.vapor_component2_mole_fraction
        );
    default:
        throw std::invalid_argument("Unsupported binary teqp formulation.");
    }
}

void fill_binary_thermodynamic_result(
    PXTeqpBinaryFormulation formulation,
    double pressure_pa,
    double temperature_k,
    double component2_mole_fraction,
    PXTeqpMixtureThermodynamicResult *result
) {
    switch (formulation) {
    case PXTeqpBinaryFormulationEOSCGCO2H2:
        fill_binary_thermodynamic_result(
            eoscg_co2_h2_model(),
            pressure_pa,
            temperature_k,
            component2_mole_fraction,
            PXTeqpPhaseGas,
            result
        );
        return;
    case PXTeqpBinaryFormulationEOSCGCO2CH4:
        fill_binary_thermodynamic_result(
            eoscg_co2_ch4_model(),
            pressure_pa,
            temperature_k,
            component2_mole_fraction,
            PXTeqpPhaseGas,
            result
        );
        return;
    case PXTeqpBinaryFormulationCO2N2:
    default:
        throw std::invalid_argument("Thermodynamic mixture properties are implemented only for EOS-CG CO2/H2 and CO2/CH4.");
    }
}

BinaryCriticalPoint binary_critical_point(
    PXTeqpBinaryFormulation formulation,
    double component2_mole_fraction
) {
    switch (formulation) {
    case PXTeqpBinaryFormulationEOSCGCO2H2:
        return eoscg_co2_h2_model().criticalPoint(component2_mole_fraction);
    case PXTeqpBinaryFormulationEOSCGCO2CH4:
        return eoscg_co2_ch4_model().criticalPoint(component2_mole_fraction);
    case PXTeqpBinaryFormulationCO2N2:
    default:
        throw std::invalid_argument("Critical diagnostics are implemented only for EOS-CG CO2/H2 and CO2/CH4.");
    }
}

void fill_binary_critical_result(
    const BinaryCriticalPoint &critical,
    PXTeqpBinaryCriticalResult *result
) {
    result->converged = critical.converged ? 1 : 0;
    result->iteration_count = critical.iteration_count;
    result->temperature_k = critical.temperature_k;
    result->pressure_pa = critical.pressure_pa;
    result->molar_density_mol_m3 = critical.molar_density_mol_m3;
    result->density_kg_m3 = critical.density_kg_m3;
    result->component2_mole_fraction = critical.component2_mole_fraction;
    result->minimum_stability_eigenvalue =
        critical.minimum_stability_eigenvalue;
    result->third_order_residual = critical.third_order_residual;
}

struct NComponentVLEState {
    bool converged = false;
    int iterations = 0;
    PXTeqpEquilibriumStatus status = PXTeqpEquilibriumMaximumIterations;
    double pressure_pa = std::numeric_limits<double>::quiet_NaN();
    Eigen::ArrayXd liquid_composition;
    Eigen::ArrayXd vapor_composition;
    double liquid_density = std::numeric_limits<double>::quiet_NaN();
    double vapor_density = std::numeric_limits<double>::quiet_NaN();
    double fugacity_residual = std::numeric_limits<double>::infinity();
    double pressure_residual = std::numeric_limits<double>::infinity();
    double liquid_stability = std::numeric_limits<double>::quiet_NaN();
    double vapor_stability = std::numeric_limits<double>::quiet_NaN();
};

Eigen::ArrayXd composition_from_log_ratios(const Eigen::VectorXd &ratios) {
    Eigen::ArrayXd weights(ratios.size() + 1);
    const double shift = std::max(0.0, ratios.maxCoeff());
    for (Eigen::Index i = 0; i < ratios.size(); ++i) {
        weights[i] = std::exp(std::clamp(ratios[i] - shift, -700.0, 700.0));
    }
    weights[ratios.size()] = std::exp(-shift);
    return (weights / weights.sum()).eval();
}

Eigen::VectorXd log_ratios_from_composition(const Eigen::ArrayXd &composition) {
    Eigen::VectorXd ratios(composition.size() - 1);
    const double reference = std::max(1e-14, composition[composition.size() - 1]);
    for (Eigen::Index i = 0; i < ratios.size(); ++i) {
        ratios[i] = std::log(std::max(1e-14, composition[i]) / reference);
    }
    return ratios;
}

Eigen::VectorXd ncomponent_vle_residual(
    const NComponentMultifluidModel &model,
    double temperature_k,
    const Eigen::ArrayXd &specified,
    PXTeqpEquilibriumSpecification specification,
    const Eigen::VectorXd &variables,
    Eigen::ArrayXd *liquid_out = nullptr,
    Eigen::ArrayXd *vapor_out = nullptr
) {
    const Eigen::Index count = specified.size();
    const double rho_liquid = std::exp(std::clamp(variables[0], -20.0, 12.0));
    const double rho_vapor = std::exp(std::clamp(variables[1], -20.0, 12.0));
    const Eigen::ArrayXd unknown = composition_from_log_ratios(
        variables.segment(2, count - 1)
    );
    const Eigen::ArrayXd liquid = specification == PXTeqpEquilibriumBubble
        ? specified : unknown;
    const Eigen::ArrayXd vapor = specification == PXTeqpEquilibriumBubble
        ? unknown : specified;
    const Eigen::ArrayXd rho_liquid_vector = rho_liquid * liquid;
    const Eigen::ArrayXd rho_vapor_vector = rho_vapor * vapor;
    const Eigen::ArrayXd mu_liquid = model.chemicalPotentials(
        temperature_k, rho_liquid_vector
    );
    const Eigen::ArrayXd mu_vapor = model.chemicalPotentials(
        temperature_k, rho_vapor_vector
    );
    const double pressure_liquid = model.pressurePa(
        temperature_k, liquid, rho_liquid
    );
    const double pressure_vapor = model.pressurePa(
        temperature_k, vapor, rho_vapor
    );
    const double rt = model.gasConstant(specified) * temperature_k;
    const double pressure_scale = std::max(
        1e5, 0.5 * (std::abs(pressure_liquid) + std::abs(pressure_vapor))
    );
    Eigen::VectorXd residual(count + 1);
    residual.head(count) = ((mu_liquid - mu_vapor) / rt).matrix();
    residual[count] = (pressure_liquid - pressure_vapor) / pressure_scale;
    if (liquid_out) { *liquid_out = liquid; }
    if (vapor_out) { *vapor_out = vapor; }
    return residual;
}

NComponentVLEState solve_ncomponent_vle(
    const NComponentMultifluidModel &model,
    double temperature_k,
    const Eigen::ArrayXd &specified,
    PXTeqpEquilibriumSpecification specification
) {
    const Eigen::Index variable_count = specified.size() + 1;
    NComponentVLEState best;
    double best_norm = std::numeric_limits<double>::infinity();
    const std::vector<double> liquid_seeds = {12000.0, 18000.0, 24000.0};
    const std::vector<double> vapor_seeds = {300.0, 1000.0, 3000.0};
    const std::vector<std::vector<double>> volatility_seeds = {
        {1.0, 4.0, 2.5}, {1.0, 8.0, 5.0}, {1.0, 15.0, 8.0},
        {1.0, 2.0, 6.0}, {1.0, 12.0, 3.0}
    };

    for (double liquid_seed : liquid_seeds) {
        for (double vapor_seed : vapor_seeds) {
            for (const auto &factors : volatility_seeds) {
                Eigen::ArrayXd unknown = specified;
                for (Eigen::Index i = 0; i < unknown.size(); ++i) {
                    const double factor = i < static_cast<Eigen::Index>(factors.size())
                        ? factors[static_cast<std::size_t>(i)] : 1.0;
                    unknown[i] *= specification == PXTeqpEquilibriumBubble
                        ? factor : 1.0 / factor;
                }
                unknown /= unknown.sum();
                Eigen::VectorXd variables(variable_count);
                variables[0] = std::log(liquid_seed);
                variables[1] = std::log(vapor_seed);
                variables.segment(2, specified.size() - 1) =
                    log_ratios_from_composition(unknown);
                double lambda = 1e-4;
                int stagnation = 0;
                for (int iteration = 0; iteration < 100; ++iteration) {
                    Eigen::VectorXd residual;
                    try {
                        residual = ncomponent_vle_residual(
                            model, temperature_k, specified, specification, variables
                        );
                    } catch (...) { break; }
                    if (!residual.array().isFinite().all()) { break; }
                    const double norm = residual.squaredNorm();
                    Eigen::MatrixXd jacobian(residual.size(), variables.size());
                    bool jacobian_ok = true;
                    for (Eigen::Index column = 0; column < variables.size(); ++column) {
                        const double step = 2e-5 * std::max(1.0, std::abs(variables[column]));
                        Eigen::VectorXd plus = variables;
                        Eigen::VectorXd minus = variables;
                        plus[column] += step;
                        minus[column] -= step;
                        try {
                            jacobian.col(column) = (
                                ncomponent_vle_residual(model, temperature_k, specified, specification, plus)
                                - ncomponent_vle_residual(model, temperature_k, specified, specification, minus)
                            ) / (2.0 * step);
                        } catch (...) { jacobian_ok = false; break; }
                    }
                    if (!jacobian_ok || !jacobian.array().isFinite().all()) { break; }
                    Eigen::MatrixXd normal = jacobian.transpose() * jacobian;
                    normal.diagonal().array() += lambda;
                    const Eigen::VectorXd step = normal.ldlt().solve(-jacobian.transpose() * residual);
                    if (!step.array().isFinite().all()) { break; }
                    bool accepted = false;
                    Eigen::VectorXd candidate = variables;
                    double candidate_norm = norm;
                    for (int line = 0; line < 14; ++line) {
                        const double scale = std::pow(0.5, line);
                        candidate = variables + scale * step;
                        candidate[0] = std::clamp(candidate[0], std::log(1000.0), std::log(80000.0));
                        candidate[1] = std::clamp(candidate[1], std::log(1.0), std::log(30000.0));
                        try {
                            candidate_norm = ncomponent_vle_residual(
                                model, temperature_k, specified, specification, candidate
                            ).squaredNorm();
                        } catch (...) { continue; }
                        if (std::isfinite(candidate_norm) && candidate_norm < norm) {
                            accepted = true; break;
                        }
                    }
                    if (accepted) {
                        variables = candidate;
                        lambda = std::max(1e-10, lambda * 0.3);
                        stagnation = 0;
                    } else {
                        lambda = std::min(1e10, lambda * 10.0);
                        ++stagnation;
                    }

                    Eigen::ArrayXd liquid, vapor;
                    const Eigen::VectorXd final_residual = ncomponent_vle_residual(
                        model, temperature_k, specified, specification, variables,
                        &liquid, &vapor
                    );
                    const double rho_liquid = std::exp(variables[0]);
                    const double rho_vapor = std::exp(variables[1]);
                    const bool distinct = rho_liquid > 1.02 * rho_vapor
                        && (liquid - vapor).matrix().norm() > 1e-5;
                    const double max_mu = final_residual.head(specified.size()).cwiseAbs().maxCoeff();
                    const double pressure_residual = std::abs(final_residual[specified.size()]);
                    if (distinct && final_residual.squaredNorm() < best_norm) {
                        best_norm = final_residual.squaredNorm();
                        best.iterations = iteration + 1;
                        best.liquid_composition = liquid;
                        best.vapor_composition = vapor;
                        best.liquid_density = rho_liquid;
                        best.vapor_density = rho_vapor;
                        best.fugacity_residual = max_mu;
                        best.pressure_residual = pressure_residual;
                    }
                    if (distinct && max_mu < 2e-7 && pressure_residual < 2e-7) {
                        best.converged = true;
                        best.status = PXTeqpEquilibriumConverged;
                        break;
                    }
                    if (stagnation >= 8 || step.norm() < 1e-10) { break; }
                }
                if (best.converged) { break; }
            }
            if (best.converged) { break; }
        }
        if (best.converged) { break; }
    }
    if (best.liquid_composition.size() == specified.size()) {
        try {
            const Eigen::ArrayXd rho_l = best.liquid_density * best.liquid_composition;
            const Eigen::ArrayXd rho_v = best.vapor_density * best.vapor_composition;
            const double pl = model.pressurePa(
                temperature_k, best.liquid_composition, best.liquid_density
            );
            const double pv = model.pressurePa(
                temperature_k, best.vapor_composition, best.vapor_density
            );
            best.pressure_pa = 0.5 * (pl + pv);
            best.liquid_stability = model.minimumStabilityEigenvalue(temperature_k, rho_l);
            best.vapor_stability = model.minimumStabilityEigenvalue(temperature_k, rho_v);
            if (!std::isfinite(best.pressure_pa) || best.pressure_pa <= 0.0
                || !std::isfinite(best.liquid_stability)
                || !std::isfinite(best.vapor_stability)
                || best.liquid_stability <= 0.0 || best.vapor_stability <= 0.0) {
                best.converged = false;
                best.status = PXTeqpEquilibriumThermodynamicFailure;
            }
        } catch (...) {
            best.converged = false;
            best.status = PXTeqpEquilibriumThermodynamicFailure;
        }
    } else {
        best.status = PXTeqpEquilibriumNoDistinctPhaseSplit;
    }
    return best;
}

struct TPDState {
    bool converged = false;
    PXTeqpStabilityStatus status = PXTeqpStabilityFailed;
    int iterations = 0;
    int root_evaluations = 0;
    int minimum_count = 0;
    double minimum = std::numeric_limits<double>::infinity();
    double trial_density = std::numeric_limits<double>::quiet_NaN();
    double reference_density = std::numeric_limits<double>::quiet_NaN();
    Eigen::ArrayXd composition;
};

struct StableRootState {
    double density;
    double gibbs;
    Eigen::ArrayXd chemical_potentials;
};

std::vector<Root> tpd_density_roots(
    const NComponentMultifluidModel &model,
    double pressure_pa,
    double temperature_k,
    const Eigen::ArrayXd &composition
) {
    std::vector<Root> roots;
    constexpr int scan_count = 180;
    const double log_min = std::log(1e-7), log_max = std::log(kMaximumMolarDensity);
    auto f = [&](double rho) { return model.pressurePa(temperature_k, composition, rho) - pressure_pa; };
    double previous_rho = std::exp(log_min), previous_f = f(previous_rho);
    for (int i = 1; i <= scan_count; ++i) {
        const double rho = std::exp(log_min + (log_max - log_min) * i / scan_count);
        const double value = f(rho);
        if (std::isfinite(value) && brackets_root(previous_f, value)) {
            double lo = previous_rho, hi = rho, flo = previous_f;
            for (int j = 0; j < 70; ++j) {
                const double mid = 0.5 * (lo + hi), fm = f(mid);
                if (!std::isfinite(fm)) { break; }
                if (brackets_root(flo, fm)) { hi = mid; } else { lo = mid; flo = fm; }
            }
            const double root = 0.5 * (lo + hi);
            if (!is_duplicate_root(roots, root)) { roots.push_back({root}); }
        }
        previous_rho = rho; previous_f = value;
    }
    return roots;
}

std::vector<StableRootState> stable_root_states(
    const NComponentMultifluidModel &model,
    double temperature_k,
    double pressure_pa,
    const Eigen::ArrayXd &composition,
    int *root_counter = nullptr,
    bool require_compositional_stability = true
) {
    std::vector<StableRootState> states;
    const auto roots = tpd_density_roots(
        model, pressure_pa, temperature_k, composition
    );
    if (root_counter) { *root_counter += static_cast<int>(roots.size()); }
    for (const auto &root : roots) {
        const Eigen::ArrayXd rhovec = root.molar_density_mol_m3 * composition;
        try {
            const double h = std::max(1e-3, 1e-5 * root.molar_density_mol_m3);
            const double dpdrho = (
                model.pressurePa(temperature_k, composition, root.molar_density_mol_m3 + h)
                - model.pressurePa(temperature_k, composition, std::max(1e-9, root.molar_density_mol_m3 - h))
            ) / (2.0 * h);
            if (!std::isfinite(dpdrho) || dpdrho <= 0.0
                || (require_compositional_stability
                    && model.minimumStabilityEigenvalue(temperature_k, rhovec) <= 0.0)) {
                continue;
            }
            const Eigen::ArrayXd mu = model.chemicalPotentials(temperature_k, rhovec);
            states.push_back({root.molar_density_mol_m3, (composition * mu).sum(), mu});
        } catch (...) {}
    }
    return states;
}

TPDState solve_tpd(
    const NComponentMultifluidModel &model,
    double temperature_k,
    double pressure_pa,
    const Eigen::ArrayXd &feed
) {
    TPDState out;
    auto reference_roots = stable_root_states(
        model, temperature_k, pressure_pa, feed, &out.root_evaluations, false
    );
    if (reference_roots.empty()) { return out; }
    const auto reference = *std::min_element(
        reference_roots.begin(), reference_roots.end(),
        [](const auto &a, const auto &b) { return a.gibbs < b.gibbs; }
    );
    out.reference_density = reference.density;
    const double rt = model.gasConstant(feed) * temperature_k;
    auto objective = [&](const Eigen::VectorXd &logits, double *density) {
        const Eigen::ArrayXd w = composition_from_log_ratios(logits);
        auto roots = stable_root_states(
            model, temperature_k, pressure_pa, w, &out.root_evaluations
        );
        double value = std::numeric_limits<double>::infinity();
        for (const auto &root : roots) {
            const double tpd = (w * (root.chemical_potentials - reference.chemical_potentials)).sum() / rt;
            if (std::isfinite(tpd) && tpd < value) {
                value = tpd;
                if (density) { *density = root.density; }
            }
        }
        return value;
    };

    std::vector<Eigen::ArrayXd> starts = {feed};
    for (Eigen::Index i = 0; i < feed.size(); ++i) {
        Eigen::ArrayXd enriched = 0.15 * feed;
        enriched[i] += 0.85;
        enriched /= enriched.sum();
        starts.push_back(enriched);
    }
    std::vector<std::pair<double, Eigen::ArrayXd>> minima;
    for (const auto &start : starts) {
        Eigen::VectorXd logits = log_ratios_from_composition(start);
        double step = 2.0;
        double density = std::numeric_limits<double>::quiet_NaN();
        double value = objective(logits, &density);
        int iterations = 0;
        while (step > 5e-3 && iterations < 36) {
            bool improved = false;
            for (Eigen::Index i = 0; i < logits.size(); ++i) {
                for (double direction : {-1.0, 1.0}) {
                    Eigen::VectorXd candidate = logits;
                    candidate[i] += direction * step;
                    double candidate_density = 0.0;
                    const double candidate_value = objective(candidate, &candidate_density);
                    if (candidate_value + 1e-11 < value) {
                        logits = candidate;
                        value = candidate_value;
                        density = candidate_density;
                        improved = true;
                    }
                }
            }
            if (!improved) { step *= 0.5; }
            ++iterations;
        }
        out.iterations += iterations;
        if (!std::isfinite(value)) { continue; }
        const Eigen::ArrayXd composition = composition_from_log_ratios(logits);
        bool duplicate = false;
        for (const auto &minimum : minima) {
            if ((minimum.second - composition).matrix().norm() < 1e-4) {
                duplicate = true; break;
            }
        }
        if (!duplicate) { minima.push_back({value, composition}); }
        if (value < out.minimum) {
            out.minimum = value;
            out.composition = composition;
            out.trial_density = density;
        }
    }
    out.minimum_count = static_cast<int>(minima.size());
    out.converged = std::isfinite(out.minimum) && out.composition.size() == feed.size();
    if (!out.converged) { return out; }
    constexpr double neutral = 2e-6;
    out.status = out.minimum < -neutral ? PXTeqpStabilityUnstable
        : (out.minimum < -1e-9 ? PXTeqpStabilityNearNeutral
                               : PXTeqpStabilityStable);
    return out;
}

struct TPFlashState {
    bool converged = false;
    PXTeqpEquilibriumStatus status = PXTeqpEquilibriumMaximumIterations;
    int iterations = 0;
    double beta = std::numeric_limits<double>::quiet_NaN();
    double rho_l = std::numeric_limits<double>::quiet_NaN();
    double rho_v = std::numeric_limits<double>::quiet_NaN();
    Eigen::ArrayXd liquid;
    Eigen::ArrayXd vapor;
    double material_residual = std::numeric_limits<double>::infinity();
    double fugacity_residual = std::numeric_limits<double>::infinity();
    double pressure_l_residual = std::numeric_limits<double>::infinity();
    double pressure_v_residual = std::numeric_limits<double>::infinity();
    double stability_l = std::numeric_limits<double>::quiet_NaN();
    double stability_v = std::numeric_limits<double>::quiet_NaN();
    double post_tpd = std::numeric_limits<double>::quiet_NaN();
};

Eigen::VectorXd tp_flash_residual(
    const NComponentMultifluidModel &model,
    double temperature_k,
    double pressure_pa,
    const Eigen::ArrayXd &feed,
    const Eigen::VectorXd &u,
    Eigen::ArrayXd *liquid_out = nullptr,
    Eigen::ArrayXd *vapor_out = nullptr
) {
    const Eigen::Index n = feed.size();
    const double rho_l = std::exp(std::clamp(u[0], std::log(1.0), std::log(80000.0)));
    const double rho_v = std::exp(std::clamp(u[1], std::log(1.0), std::log(80000.0)));
    const Eigen::ArrayXd liquid = composition_from_log_ratios(u.segment(2, n - 1));
    const Eigen::ArrayXd vapor = composition_from_log_ratios(u.segment(n + 1, n - 1));
    const double beta = 1.0 / (1.0 + std::exp(-std::clamp(u[2 * n], -30.0, 30.0)));
    const Eigen::ArrayXd mu_l = model.chemicalPotentials(temperature_k, rho_l * liquid);
    const Eigen::ArrayXd mu_v = model.chemicalPotentials(temperature_k, rho_v * vapor);
    const double rt = model.gasConstant(feed) * temperature_k;
    Eigen::VectorXd residual(2 * n + 1);
    residual.head(n) = ((mu_l - mu_v) / rt).matrix();
    residual[n] = (model.pressurePa(temperature_k, liquid, rho_l) - pressure_pa) / pressure_pa;
    residual[n + 1] = (model.pressurePa(temperature_k, vapor, rho_v) - pressure_pa) / pressure_pa;
    residual.segment(n + 2, n - 1) =
        ((1.0 - beta) * liquid.head(n - 1) + beta * vapor.head(n - 1) - feed.head(n - 1)).matrix();
    if (liquid_out) { *liquid_out = liquid; }
    if (vapor_out) { *vapor_out = vapor; }
    return residual;
}

TPFlashState solve_tp_flash(
    const NComponentMultifluidModel &model,
    double temperature_k,
    double pressure_pa,
    const Eigen::ArrayXd &feed
) {
    TPFlashState out;
    const TPDState tpd = solve_tpd(model, temperature_k, pressure_pa, feed);
    out.post_tpd = tpd.minimum;
    if (!tpd.converged) { out.status = PXTeqpEquilibriumThermodynamicFailure; return out; }
    if (tpd.status != PXTeqpStabilityUnstable) {
        out.converged = true;
        out.status = tpd.status == PXTeqpStabilityNearNeutral
            ? PXTeqpEquilibriumNoDistinctPhaseSplit : PXTeqpEquilibriumConverged;
        out.beta = std::numeric_limits<double>::quiet_NaN();
        return out;
    }
    const bool trial_is_liquid = tpd.trial_density > tpd.reference_density;
    Eigen::ArrayXd liquid = trial_is_liquid ? tpd.composition : feed;
    Eigen::ArrayXd vapor = trial_is_liquid ? feed : tpd.composition;
    double beta_seed = 0.5;
    for (double beta : {0.5, 0.25, 0.75, 0.1, 0.9}) {
        Eigen::ArrayXd companion = trial_is_liquid
            ? (feed - (1.0 - beta) * liquid) / beta
            : (feed - beta * vapor) / (1.0 - beta);
        if ((companion > 1e-10).all() && companion.isFinite().all()) {
            if (trial_is_liquid) { vapor = companion; } else { liquid = companion; }
            beta_seed = beta;
            break;
        }
    }
    auto roots_l = stable_root_states(model, temperature_k, pressure_pa, liquid);
    auto roots_v = stable_root_states(model, temperature_k, pressure_pa, vapor);
    if (roots_l.empty() || roots_v.empty()) { out.status = PXTeqpEquilibriumThermodynamicFailure; return out; }
    const double rho_l_seed = std::max_element(roots_l.begin(), roots_l.end(), [](auto&a,auto&b){return a.density<b.density;})->density;
    const double rho_v_seed = std::min_element(roots_v.begin(), roots_v.end(), [](auto&a,auto&b){return a.density<b.density;})->density;
    const Eigen::Index n = feed.size();
    Eigen::VectorXd u(2 * n + 1);
    u[0] = std::log(rho_l_seed); u[1] = std::log(rho_v_seed);
    u.segment(2, n - 1) = log_ratios_from_composition(liquid);
    u.segment(n + 1, n - 1) = log_ratios_from_composition(vapor);
    u[2 * n] = std::log(beta_seed / (1.0 - beta_seed));
    double lambda = 1e-3;
    for (int iteration = 0; iteration < 80; ++iteration) {
        Eigen::VectorXd residual;
        try { residual = tp_flash_residual(model, temperature_k, pressure_pa, feed, u); }
        catch (...) { break; }
        Eigen::MatrixXd jacobian(residual.size(), u.size());
        bool ok = true;
        for (Eigen::Index j = 0; j < u.size(); ++j) {
            const double h = 2e-5 * std::max(1.0, std::abs(u[j]));
            Eigen::VectorXd plus=u, minus=u; plus[j]+=h; minus[j]-=h;
            try { jacobian.col(j)=(tp_flash_residual(model,temperature_k,pressure_pa,feed,plus)-tp_flash_residual(model,temperature_k,pressure_pa,feed,minus))/(2*h); }
            catch (...) { ok=false; break; }
        }
        if (!ok || !jacobian.array().isFinite().all()) { break; }
        Eigen::MatrixXd normal=jacobian.transpose()*jacobian;
        normal.diagonal().array() += lambda;
        const Eigen::VectorXd step=normal.ldlt().solve(-jacobian.transpose()*residual);
        bool accepted=false;
        for(int line=0;line<14;++line){
            Eigen::VectorXd candidate=u+std::pow(0.5,line)*step;
            try { if(tp_flash_residual(model,temperature_k,pressure_pa,feed,candidate).squaredNorm()<residual.squaredNorm()){u=candidate;accepted=true;break;} }
            catch (...) {}
        }
        lambda=accepted?std::max(1e-10,lambda*0.3):std::min(1e10,lambda*10);
        out.iterations=iteration+1;
        Eigen::ArrayXd x,y;
        const Eigen::VectorXd final=tp_flash_residual(model,temperature_k,pressure_pa,feed,u,&x,&y);
        const double beta=1.0/(1.0+std::exp(-std::clamp(u[2*n],-30.0,30.0)));
        const Eigen::ArrayXd mb=(1-beta)*x+beta*y-feed;
        const double maxmu=final.head(n).cwiseAbs().maxCoeff();
        if(maxmu<2e-7 && mb.abs().maxCoeff()<2e-8 && std::abs(final[n])<2e-7 && std::abs(final[n+1])<2e-7){
            out.converged=true; out.status=PXTeqpEquilibriumConverged; out.beta=beta;
            out.rho_l=std::exp(u[0]); out.rho_v=std::exp(u[1]); out.liquid=x; out.vapor=y;
            out.material_residual=mb.abs().maxCoeff(); out.fugacity_residual=maxmu;
            out.pressure_l_residual=std::abs(final[n]); out.pressure_v_residual=std::abs(final[n+1]);
            out.stability_l=model.minimumStabilityEigenvalue(temperature_k,out.rho_l*x);
            out.stability_v=model.minimumStabilityEigenvalue(temperature_k,out.rho_v*y);
            if(out.rho_l<=1.02*out.rho_v || (x-y).matrix().norm()<1e-5 || out.stability_l<=0 || out.stability_v<=0){out.converged=false;out.status=PXTeqpEquilibriumNoDistinctPhaseSplit;}
            break;
        }
        if(!accepted && lambda>=1e9){out.status=PXTeqpEquilibriumStagnated;break;}
    }
    return out;
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
        const auto properties = model.thermodynamicProperties(
            temperature_k,
            molar_density
        );
        if (!std::isfinite(properties.cv_j_kg_k)
            || !std::isfinite(properties.cp_j_kg_k)
            || !std::isfinite(properties.heat_capacity_ratio)
            || !std::isfinite(properties.speed_of_sound_m_s)
            || properties.cv_j_kg_k <= 0
            || properties.cp_j_kg_k <= properties.cv_j_kg_k
            || properties.heat_capacity_ratio <= 1.0
            || properties.speed_of_sound_m_s <= 0.0) {
            copy_text("teqp returned invalid pure-CO2 thermodynamic properties.", error_buffer, error_buffer_size);
            return 5;
        }

        result->molar_density_mol_m3 = molar_density;
        result->density_kg_m3 = density;
        result->isochoric_heat_capacity_j_kg_k = properties.cv_j_kg_k;
        result->isobaric_heat_capacity_j_kg_k = properties.cp_j_kg_k;
        result->heat_capacity_ratio = properties.heat_capacity_ratio;
        result->speed_of_sound_m_s = properties.speed_of_sound_m_s;
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

int px_teqp_calculate_binary_vle_tx(
    PXTeqpBinaryFormulation formulation,
    double temperature_k,
    double liquid_component2_mole_fraction,
    PXTeqpGenericBinaryVLEResult *result,
    char *error_buffer,
    size_t error_buffer_size
) {
    if (result == nullptr) {
        copy_text("Result pointer is null.", error_buffer, error_buffer_size);
        return 1;
    }
    try {
        const auto state = solve_binary_vle_tx(
            formulation,
            temperature_k,
            liquid_component2_mole_fraction
        );
        fill_generic_binary_vle_result(state, result);
        copy_text("", error_buffer, error_buffer_size);
        return state.converged ? 0 : 6;
    } catch (const std::exception &error) {
        copy_text(error.what(), error_buffer, error_buffer_size);
        return 6;
    } catch (...) {
        copy_text("teqp generic binary VLE calculation failed with an unknown native exception.", error_buffer, error_buffer_size);
        return 7;
    }
}

int px_teqp_calculate_binary_vle_tx_with_initial_guess(
    PXTeqpBinaryFormulation formulation,
    double temperature_k,
    double liquid_component2_mole_fraction,
    PXTeqpBinaryVLEInitialGuess initial_guess,
    PXTeqpGenericBinaryVLEResult *result,
    char *error_buffer,
    size_t error_buffer_size
) {
    if (result == nullptr) {
        copy_text("Result pointer is null.", error_buffer, error_buffer_size);
        return 1;
    }
    try {
        const auto state = solve_binary_vle_tx_with_initial_guess(
            formulation,
            temperature_k,
            liquid_component2_mole_fraction,
            initial_guess
        );
        fill_generic_binary_vle_result(state, result);
        copy_text("", error_buffer, error_buffer_size);
        return state.converged ? 0 : 6;
    } catch (const std::exception &error) {
        copy_text(error.what(), error_buffer, error_buffer_size);
        return 6;
    } catch (...) {
        copy_text("teqp generic binary VLE calculation with initial guess failed with an unknown native exception.", error_buffer, error_buffer_size);
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

int px_teqp_calculate_eoscg_co2_h2_gas_density(
    double pressure_pa,
    double temperature_k,
    double hydrogen_mole_fraction,
    PXTeqpMixtureDensityResult *result,
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
    if (!std::isfinite(hydrogen_mole_fraction)
        || hydrogen_mole_fraction <= 0.0
        || hydrogen_mole_fraction >= 1.0) {
        copy_text("Hydrogen mole fraction must be finite and in (0, 1).", error_buffer, error_buffer_size);
        return 3;
    }

    try {
        const auto &model = eoscg_co2_h2_model();
        Eigen::ArrayXd molefractions(2);
        molefractions << 1.0 - hydrogen_mole_fraction, hydrogen_mole_fraction;
        const auto roots = density_roots_for_molefractions(
            model,
            pressure_pa,
            temperature_k,
            molefractions
        );
        if (roots.empty()) {
            copy_text("teqp did not find a finite EOS-CG CO2/H2 gas-density root.", error_buffer, error_buffer_size);
            return 6;
        }
        const auto selected = lowest_density_root(roots);
        result->molar_density_mol_m3 = selected.molar_density_mol_m3;
        result->density_kg_m3 = selected.molar_density_mol_m3
            * model.mixtureMolarMassKgMol(hydrogen_mole_fraction);
        result->density_root_count = static_cast<int>(roots.size());
        result->phase = PXTeqpPhaseGas;
        copy_text("", error_buffer, error_buffer_size);
        return 0;
    } catch (const std::exception &error) {
        copy_text(error.what(), error_buffer, error_buffer_size);
        return 6;
    } catch (...) {
        copy_text("teqp EOS-CG CO2/H2 gas-density calculation failed with an unknown native exception.", error_buffer, error_buffer_size);
        return 7;
    }
}

int px_teqp_calculate_eoscg_co2_ch4_gas_density(
    double pressure_pa,
    double temperature_k,
    double methane_mole_fraction,
    PXTeqpMixtureDensityResult *result,
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
    if (!std::isfinite(methane_mole_fraction)
        || methane_mole_fraction <= 0.0
        || methane_mole_fraction >= 1.0) {
        copy_text("Methane mole fraction must be finite and in (0, 1).", error_buffer, error_buffer_size);
        return 3;
    }

    try {
        const auto &model = eoscg_co2_ch4_model();
        Eigen::ArrayXd molefractions(2);
        molefractions << 1.0 - methane_mole_fraction, methane_mole_fraction;
        const auto roots = density_roots_for_molefractions(
            model,
            pressure_pa,
            temperature_k,
            molefractions
        );
        if (roots.empty()) {
            copy_text("teqp did not find a finite EOS-CG CO2/CH4 gas-density root.", error_buffer, error_buffer_size);
            return 6;
        }
        const auto selected = lowest_density_root(roots);
        result->molar_density_mol_m3 = selected.molar_density_mol_m3;
        result->density_kg_m3 = selected.molar_density_mol_m3
            * model.mixtureMolarMassKgMol(methane_mole_fraction);
        result->density_root_count = static_cast<int>(roots.size());
        result->phase = PXTeqpPhaseGas;
        copy_text("", error_buffer, error_buffer_size);
        return 0;
    } catch (const std::exception &error) {
        copy_text(error.what(), error_buffer, error_buffer_size);
        return 6;
    } catch (...) {
        copy_text("teqp EOS-CG CO2/CH4 gas-density calculation failed with an unknown native exception.", error_buffer, error_buffer_size);
        return 7;
    }
}

int px_teqp_calculate_binary_thermodynamic_state(
    PXTeqpBinaryFormulation formulation,
    double pressure_pa,
    double temperature_k,
    double component2_mole_fraction,
    PXTeqpMixtureThermodynamicResult *result,
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
    if (!valid_binary_fraction(component2_mole_fraction)) {
        copy_text("Component-2 mole fraction must be finite and in (0, 1).", error_buffer, error_buffer_size);
        return 3;
    }

    try {
        fill_binary_thermodynamic_result(
            formulation,
            pressure_pa,
            temperature_k,
            component2_mole_fraction,
            result
        );
        copy_text("", error_buffer, error_buffer_size);
        return 0;
    } catch (const std::exception &error) {
        result->converged = 0;
        copy_text(error.what(), error_buffer, error_buffer_size);
        return 6;
    } catch (...) {
        result->converged = 0;
        copy_text("teqp EOS-CG binary thermodynamic-state calculation failed with an unknown native exception.", error_buffer, error_buffer_size);
        return 7;
    }
}

int px_teqp_calculate_binary_critical_point(
    PXTeqpBinaryFormulation formulation,
    double component2_mole_fraction,
    PXTeqpBinaryCriticalResult *result,
    char *error_buffer,
    size_t error_buffer_size
) {
    if (result == nullptr) {
        copy_text("Result pointer is null.", error_buffer, error_buffer_size);
        return 1;
    }
    if (!valid_binary_fraction(component2_mole_fraction)) {
        copy_text("Component-2 mole fraction must be finite and in (0, 1).", error_buffer, error_buffer_size);
        return 3;
    }

    try {
        const auto critical = binary_critical_point(
            formulation,
            component2_mole_fraction
        );
        fill_binary_critical_result(critical, result);
        if (!critical.converged) {
            copy_text("teqp EOS-CG binary critical-point solver did not converge.", error_buffer, error_buffer_size);
            return 6;
        }
        copy_text("", error_buffer, error_buffer_size);
        return 0;
    } catch (const std::exception &error) {
        result->converged = 0;
        copy_text(error.what(), error_buffer, error_buffer_size);
        return 6;
    } catch (...) {
        result->converged = 0;
        copy_text("teqp EOS-CG binary critical-point calculation failed with an unknown native exception.", error_buffer, error_buffer_size);
        return 7;
    }
}

int px_teqp_calculate_ncomponent_density(
    const int *component_ids,
    const double *mole_fractions,
    size_t component_count,
    double pressure_pa,
    double temperature_k,
    PXTeqpNComponentDensityResult *result,
    char *error_buffer,
    size_t error_buffer_size
) {
    if (result == nullptr) {
        copy_text("Result pointer is null.", error_buffer, error_buffer_size);
        return 1;
    }
    result->density_kg_m3 = std::numeric_limits<double>::quiet_NaN();
    result->molar_density_mol_m3 = std::numeric_limits<double>::quiet_NaN();
    result->density_root_count = 0;
    result->converged = 0;
    result->phase = PXTeqpPhaseUnknown;

    if (component_ids == nullptr || mole_fractions == nullptr) {
        copy_text("Component and mole-fraction pointers must be non-null.", error_buffer, error_buffer_size);
        return 1;
    }
    if (component_count == 0 || component_count > 9) {
        copy_text("N-component teqp density requires 1 to 9 components.", error_buffer, error_buffer_size);
        return 2;
    }
    if (!std::isfinite(pressure_pa) || !std::isfinite(temperature_k)
        || pressure_pa <= 0 || temperature_k <= 0) {
        copy_text("Pressure and temperature must be finite and positive.", error_buffer, error_buffer_size);
        return 3;
    }

    try {
        std::vector<int> ids;
        ids.reserve(component_count);
        std::set<int> seen_ids;
        Eigen::ArrayXd molefractions(static_cast<Eigen::Index>(component_count));
        double total = 0.0;
        for (size_t index = 0; index < component_count; ++index) {
            const int component_id = component_ids[index];
            component_json_for_id(component_id);
            if (!seen_ids.insert(component_id).second) {
                copy_text("Duplicate component identifier in N-component teqp density request.", error_buffer, error_buffer_size);
                return 4;
            }
            const double fraction = mole_fractions[index];
            if (!std::isfinite(fraction) || fraction <= 0.0) {
                copy_text("N-component teqp density requires finite positive active-component mole fractions.", error_buffer, error_buffer_size);
                return 5;
            }
            ids.push_back(component_id);
            molefractions[static_cast<Eigen::Index>(index)] = fraction;
            total += fraction;
        }
        if (std::abs(total - 1.0) > 1e-10) {
            copy_text("N-component teqp density mole fractions must sum exactly to one.", error_buffer, error_buffer_size);
            return 6;
        }

        NComponentMultifluidModel model(ids);
        const auto roots = density_roots_for_molefractions(
            model,
            pressure_pa,
            temperature_k,
            molefractions
        );
        result->density_root_count = static_cast<int>(roots.size());
        if (roots.empty()) {
            copy_text("teqp did not find a finite N-component density root.", error_buffer, error_buffer_size);
            return 7;
        }
        if (roots.size() != 1) {
            copy_text("teqp found multiple N-component density roots; homogeneous density is not unique.", error_buffer, error_buffer_size);
            return 8;
        }

        result->molar_density_mol_m3 = roots[0].molar_density_mol_m3;
        result->density_kg_m3 = roots[0].molar_density_mol_m3
            * model.mixtureMolarMassKgMol(molefractions);
        if (!std::isfinite(result->molar_density_mol_m3)
            || !std::isfinite(result->density_kg_m3)
            || result->molar_density_mol_m3 <= 0.0
            || result->density_kg_m3 <= 0.0) {
            copy_text("teqp returned invalid N-component density.", error_buffer, error_buffer_size);
            return 9;
        }

        result->converged = 1;
        result->phase = PXTeqpPhaseUnknown;
        copy_text("", error_buffer, error_buffer_size);
        return 0;
    } catch (const std::exception &error) {
        copy_text(error.what(), error_buffer, error_buffer_size);
        return 10;
    } catch (...) {
        copy_text("teqp N-component density calculation failed with an unknown native exception.", error_buffer, error_buffer_size);
        return 11;
    }
}

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
) {
    if (result == nullptr || component_ids == nullptr
        || specified_mole_fractions == nullptr
        || liquid_mole_fractions == nullptr || vapor_mole_fractions == nullptr) {
        copy_text("N-component VLE received a null pointer.", error_buffer, error_buffer_size);
        return 1;
    }
    if (component_count < 2 || component_count > 9
        || liquid_mole_fractions_length < component_count
        || vapor_mole_fractions_length < component_count) {
        copy_text("N-component VLE requires 2...9 components and matching output buffers.", error_buffer, error_buffer_size);
        return 2;
    }
    if (!std::isfinite(temperature_k) || temperature_k <= 0.0
        || (specification != PXTeqpEquilibriumBubble
            && specification != PXTeqpEquilibriumDew)) {
        copy_text("N-component VLE requires positive temperature and a valid specification.", error_buffer, error_buffer_size);
        return 3;
    }
    try {
        std::vector<int> ids(component_ids, component_ids + component_count);
        if (std::set<int>(ids.begin(), ids.end()).size() != component_count) {
            copy_text("N-component VLE component identifiers must be unique.", error_buffer, error_buffer_size);
            return 4;
        }
        Eigen::ArrayXd specified(static_cast<Eigen::Index>(component_count));
        double sum = 0.0;
        for (std::size_t i = 0; i < component_count; ++i) {
            specified[static_cast<Eigen::Index>(i)] = specified_mole_fractions[i];
            if (!std::isfinite(specified_mole_fractions[i])
                || specified_mole_fractions[i] <= 0.0) {
                copy_text("N-component VLE mole fractions must be finite and positive.", error_buffer, error_buffer_size);
                return 5;
            }
            sum += specified_mole_fractions[i];
        }
        if (std::abs(sum - 1.0) > 1e-10) {
            copy_text("N-component VLE mole fractions must sum to one; no normalization is applied.", error_buffer, error_buffer_size);
            return 6;
        }
        NComponentMultifluidModel model(ids);
        const auto state = solve_ncomponent_vle(
            model, temperature_k, specified, specification
        );
        result->converged = state.converged ? 1 : 0;
        result->iteration_count = state.iterations;
        result->status = state.status;
        result->pressure_pa = state.pressure_pa;
        result->liquid_molar_density_mol_m3 = state.liquid_density;
        result->vapor_molar_density_mol_m3 = state.vapor_density;
        result->maximum_log_fugacity_residual = state.fugacity_residual;
        result->relative_pressure_residual = state.pressure_residual;
        result->liquid_minimum_stability_eigenvalue = state.liquid_stability;
        result->vapor_minimum_stability_eigenvalue = state.vapor_stability;
        if (state.liquid_composition.size() == static_cast<Eigen::Index>(component_count)) {
            for (std::size_t i = 0; i < component_count; ++i) {
                liquid_mole_fractions[i] = state.liquid_composition[static_cast<Eigen::Index>(i)];
                vapor_mole_fractions[i] = state.vapor_composition[static_cast<Eigen::Index>(i)];
            }
        }
        if (!state.converged) {
            copy_text("N-component VLE did not converge to a distinct stable phase split.", error_buffer, error_buffer_size);
            return 7;
        }
        copy_text("", error_buffer, error_buffer_size);
        return 0;
    } catch (const std::exception &error) {
        copy_text(error.what(), error_buffer, error_buffer_size);
        return 8;
    } catch (...) {
        copy_text("N-component VLE failed with an unknown native exception.", error_buffer, error_buffer_size);
        return 9;
    }
}

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
) {
    if (component_ids == nullptr || partial_molar_densities_mol_m3 == nullptr
        || chemical_potentials_j_mol == nullptr || result == nullptr) {
        copy_text("Phase evaluation received a null pointer.", error_buffer, error_buffer_size);
        return 1;
    }
    if (component_count < 2 || component_count > 9
        || chemical_potentials_length < component_count
        || !std::isfinite(temperature_k) || temperature_k <= 0.0) {
        copy_text("Phase evaluation requires 2...9 components, matching buffers, and positive temperature.", error_buffer, error_buffer_size);
        return 2;
    }
    try {
        const std::vector<int> ids(component_ids, component_ids + component_count);
        if (std::set<int>(ids.begin(), ids.end()).size() != component_count) {
            copy_text("Phase evaluation component identifiers must be unique.", error_buffer, error_buffer_size);
            return 3;
        }
        Eigen::ArrayXd rhovec(static_cast<Eigen::Index>(component_count));
        for (std::size_t i = 0; i < component_count; ++i) {
            const double value = partial_molar_densities_mol_m3[i];
            if (!std::isfinite(value) || value <= 0.0) {
                copy_text("Phase evaluation requires finite positive partial densities.", error_buffer, error_buffer_size);
                return 4;
            }
            rhovec[static_cast<Eigen::Index>(i)] = value;
        }
        NComponentMultifluidModel model(ids);
        const Eigen::ArrayXd composition = (rhovec / rhovec.sum()).eval();
        const Eigen::ArrayXd chemical_potentials = model.chemicalPotentials(
            temperature_k, rhovec
        );
        result->pressure_pa = model.pressurePa(
            temperature_k, composition, rhovec.sum()
        );
        result->minimum_stability_eigenvalue = model.minimumStabilityEigenvalue(
            temperature_k, rhovec
        );
        for (std::size_t i = 0; i < component_count; ++i) {
            chemical_potentials_j_mol[i] = chemical_potentials[static_cast<Eigen::Index>(i)];
        }
        if (!std::isfinite(result->pressure_pa)
            || !std::isfinite(result->minimum_stability_eigenvalue)
            || !chemical_potentials.isFinite().all()) {
            copy_text("Phase evaluation produced non-finite thermodynamic primitives.", error_buffer, error_buffer_size);
            return 5;
        }
        copy_text("", error_buffer, error_buffer_size);
        return 0;
    } catch (const std::exception &error) {
        copy_text(error.what(), error_buffer, error_buffer_size);
        return 6;
    } catch (...) {
        copy_text("Phase evaluation failed with an unknown native exception.", error_buffer, error_buffer_size);
        return 7;
    }
}

int px_teqp_calculate_ncomponent_tpd(
    const int *component_ids, const double *feed_mole_fractions,
    size_t component_count, double pressure_pa, double temperature_k,
    double *minimum_composition, size_t minimum_composition_length,
    PXTeqpTPDResult *result, char *error_buffer, size_t error_buffer_size
) {
    if(!component_ids||!feed_mole_fractions||!minimum_composition||!result){copy_text("TPD received a null pointer.",error_buffer,error_buffer_size);return 1;}
    if(component_count<2||component_count>9||minimum_composition_length<component_count||!std::isfinite(pressure_pa)||pressure_pa<=0||!std::isfinite(temperature_k)||temperature_k<=0){copy_text("TPD input dimensions or state are invalid.",error_buffer,error_buffer_size);return 2;}
    try{
        std::vector<int> ids(component_ids,component_ids+component_count);
        if(std::set<int>(ids.begin(),ids.end()).size()!=component_count){copy_text("TPD component identifiers must be unique.",error_buffer,error_buffer_size);return 3;}
        Eigen::ArrayXd feed(component_count); double sum=0;
        for(size_t i=0;i<component_count;++i){if(!std::isfinite(feed_mole_fractions[i])||feed_mole_fractions[i]<=0){copy_text("TPD composition must be finite and positive.",error_buffer,error_buffer_size);return 4;} feed[i]=feed_mole_fractions[i];sum+=feed[i];}
        if(std::abs(sum-1.0)>1e-10){copy_text("TPD composition must sum to one; no normalization is applied.",error_buffer,error_buffer_size);return 5;}
        NComponentMultifluidModel model(ids); const auto state=solve_tpd(model,temperature_k,pressure_pa,feed);
        result->status=state.status;result->converged=state.converged?1:0;result->iteration_count=state.iterations;result->density_root_evaluations=state.root_evaluations;result->distinct_minimum_count=state.minimum_count;result->minimum_tpd=state.minimum;result->trial_molar_density_mol_m3=state.trial_density;result->reference_molar_density_mol_m3=state.reference_density;
        if(state.composition.size()==static_cast<Eigen::Index>(component_count)){for(size_t i=0;i<component_count;++i)minimum_composition[i]=state.composition[i];}
        if(!state.converged){copy_text("TPD minimization failed.",error_buffer,error_buffer_size);return 6;} copy_text("",error_buffer,error_buffer_size);return 0;
    }catch(const std::exception&e){copy_text(e.what(),error_buffer,error_buffer_size);return 7;}catch(...){copy_text("TPD failed with unknown native exception.",error_buffer,error_buffer_size);return 8;}
}

int px_teqp_calculate_ncomponent_tp_flash(
    const int *component_ids, const double *feed_mole_fractions,
    size_t component_count, double pressure_pa, double temperature_k,
    double *liquid_mole_fractions, size_t liquid_length,
    double *vapor_mole_fractions, size_t vapor_length,
    PXTeqpTPFlashResult *result, char *error_buffer, size_t error_buffer_size
) {
    if(!component_ids||!feed_mole_fractions||!liquid_mole_fractions||!vapor_mole_fractions||!result){copy_text("TP flash received a null pointer.",error_buffer,error_buffer_size);return 1;}
    if(component_count<2||component_count>9||liquid_length<component_count||vapor_length<component_count||!std::isfinite(pressure_pa)||pressure_pa<=0||!std::isfinite(temperature_k)||temperature_k<=0){copy_text("TP flash input dimensions or state are invalid.",error_buffer,error_buffer_size);return 2;}
    try{
        std::vector<int> ids(component_ids,component_ids+component_count); if(std::set<int>(ids.begin(),ids.end()).size()!=component_count){copy_text("TP flash component identifiers must be unique.",error_buffer,error_buffer_size);return 3;}
        Eigen::ArrayXd feed(component_count);double sum=0;for(size_t i=0;i<component_count;++i){if(!std::isfinite(feed_mole_fractions[i])||feed_mole_fractions[i]<=0){copy_text("TP flash composition must be finite and positive.",error_buffer,error_buffer_size);return 4;}feed[i]=feed_mole_fractions[i];sum+=feed[i];}if(std::abs(sum-1.0)>1e-10){copy_text("TP flash composition must sum to one; no normalization is applied.",error_buffer,error_buffer_size);return 5;}
        NComponentMultifluidModel model(ids);const auto state=solve_tp_flash(model,temperature_k,pressure_pa,feed);
        result->converged=state.converged?1:0;result->status=state.status;result->iteration_count=state.iterations;result->vapor_fraction=state.beta;result->liquid_molar_density_mol_m3=state.rho_l;result->vapor_molar_density_mol_m3=state.rho_v;result->maximum_material_balance_residual=state.material_residual;result->maximum_log_fugacity_residual=state.fugacity_residual;result->relative_liquid_pressure_residual=state.pressure_l_residual;result->relative_vapor_pressure_residual=state.pressure_v_residual;result->liquid_minimum_stability_eigenvalue=state.stability_l;result->vapor_minimum_stability_eigenvalue=state.stability_v;result->postcheck_minimum_tpd=state.post_tpd;
        if(state.liquid.size()==static_cast<Eigen::Index>(component_count)){for(size_t i=0;i<component_count;++i){liquid_mole_fractions[i]=state.liquid[i];vapor_mole_fractions[i]=state.vapor[i];}}
        if(!state.converged){copy_text("TP flash did not converge to a defensible equilibrium state.",error_buffer,error_buffer_size);return 6;}copy_text("",error_buffer,error_buffer_size);return 0;
    }catch(const std::exception&e){copy_text(e.what(),error_buffer,error_buffer_size);return 7;}catch(...){copy_text("TP flash failed with unknown native exception.",error_buffer,error_buffer_size);return 8;}
}

int px_teqp_calculate_eoscg_co2_o2_gas_density(
    double pressure_pa,
    double temperature_k,
    double oxygen_mole_fraction,
    PXTeqpMixtureDensityResult *result,
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
    if (!std::isfinite(oxygen_mole_fraction)
        || oxygen_mole_fraction <= 0.0
        || oxygen_mole_fraction >= 1.0) {
        copy_text("Oxygen mole fraction must be finite and in (0, 1).", error_buffer, error_buffer_size);
        return 3;
    }

    try {
        const std::vector<int> ids = {
            PXTeqpComponentCarbonDioxide,
            PXTeqpComponentOxygen
        };
        NComponentMultifluidModel model(ids);
        Eigen::ArrayXd molefractions(2);
        molefractions << 1.0 - oxygen_mole_fraction, oxygen_mole_fraction;
        const auto roots = density_roots_for_molefractions(
            model,
            pressure_pa,
            temperature_k,
            molefractions
        );
        if (roots.empty()) {
            copy_text("teqp did not find a finite EOS-CG CO2/O2 gas-density root.", error_buffer, error_buffer_size);
            return 6;
        }
        const auto selected = lowest_density_root(roots);
        result->molar_density_mol_m3 = selected.molar_density_mol_m3;
        result->density_kg_m3 = selected.molar_density_mol_m3
            * model.mixtureMolarMassKgMol(molefractions);
        result->density_root_count = static_cast<int>(roots.size());
        result->phase = PXTeqpPhaseGas;
        copy_text("", error_buffer, error_buffer_size);
        return 0;
    } catch (const std::exception &error) {
        copy_text(error.what(), error_buffer, error_buffer_size);
        return 6;
    } catch (...) {
        copy_text("teqp EOS-CG CO2/O2 gas-density calculation failed with an unknown native exception.", error_buffer, error_buffer_size);
        return 7;
    }
}
