#include "PhaseXpertTeqpBridge.h"

#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <string>
#include <type_traits>
#include <vector>

template<typename Value>
std::vector<Value> split(const std::string &text) {
    std::vector<Value> values;
    std::stringstream stream(text);
    std::string token;
    while (std::getline(stream, token, ',')) {
        if constexpr (std::is_same_v<Value, int>) {
            values.push_back(std::stoi(token));
        } else {
            values.push_back(std::stod(token));
        }
    }
    return values;
}

int main(int argc, char **argv) {
    if (argc != 6) {
        std::cerr << "usage: probe <component-ids-csv> <fractions-csv> <T-K> <pressure-Pa> <gas|dense|supercritical>\n";
        return 64;
    }
    const auto component_ids = split<int>(argv[1]);
    const auto fractions = split<double>(argv[2]);
    if (component_ids.size() != fractions.size()) { return 64; }
    PXTeqpDensityRootSelectionHint hint = PXTeqpDensityRootSelectionAutomatic;
    const std::string phase = argv[5];
    if (phase == "gas") { hint = PXTeqpDensityRootSelectionHomogeneousGas; }
    if (phase == "dense") { hint = PXTeqpDensityRootSelectionHomogeneousLiquidOrDense; }
    if (phase == "supercritical") { hint = PXTeqpDensityRootSelectionSupercritical; }
    PXTeqpMixtureThermodynamicResult result{};
    char error[1024] = {};
    const int code = px_teqp_calculate_ncomponent_thermodynamic_state(
        component_ids.data(), fractions.data(), component_ids.size(),
        std::strtod(argv[4], nullptr), std::strtod(argv[3], nullptr), hint,
        &result, error, sizeof(error)
    );
    std::cout << std::setprecision(17)
              << code << ',' << result.converged << ',' << result.speed_of_sound_m_s << ','
              << result.density_kg_m3 << ',' << result.density_root_count << ','
              << result.minimum_stability_eigenvalue << ',' << result.phase << ','
              << error << '\n';
    return 0;
}
