#include "PhaseXpertTeqpBridge.h"

#include "PhaseXpertTeqpCarbonDioxideData.hpp"

#include "teqp/derivs.hpp"
#include "teqp/models/multifluid.hpp"

#include <Eigen/Dense>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <exception>
#include <mutex>
#include <string>
#include <vector>

namespace {

constexpr double kMaximumMolarDensity = 100000.0;
constexpr int kScanPointCount = 900;
constexpr int kBisectionIterations = 120;

void copy_text(const std::string &text, char *buffer, size_t buffer_size) {
    if (buffer == nullptr || buffer_size == 0) {
        return;
    }
    std::snprintf(buffer, buffer_size, "%s", text.c_str());
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

private:
    nlohmann::json json_;
    Model model_;
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
        if (roots.empty()) {
            copy_text("teqp did not find a finite pure-CO2 density root.", error_buffer, error_buffer_size);
            return 3;
        }
        if (roots.size() > 1) {
            copy_text("teqp found multiple pure-CO2 density roots; PhaseXpert does not choose an arbitrary root.", error_buffer, error_buffer_size);
            return 4;
        }

        const double molar_density = roots[0].molar_density_mol_m3;
        const double density = molar_density * model.molarMassKilogramsPerMole();
        if (!std::isfinite(density) || density <= 0) {
            copy_text("teqp returned a non-finite or non-positive density.", error_buffer, error_buffer_size);
            return 5;
        }

        result->molar_density_mol_m3 = molar_density;
        result->density_kg_m3 = density;
        result->density_root_count = static_cast<int>(roots.size());
        result->phase = (
            temperature_k > model.criticalTemperatureK()
            && pressure_pa > model.criticalPressurePa()
        ) ? PXTeqpPhaseSupercritical : PXTeqpPhaseUnknown;
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
