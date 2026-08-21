#include "PhaseXpertTeqpBridge.h"

#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <string>

int main(int argc, char **argv) {
    if (argc < 5 || argc > 7) {
        std::cerr << "usage: probe <component-id> <bubble|dew> <T-K> <specified-component2-mole-fraction>\n"
                     "       probe <component-id> density <T-K> <component2-mole-fraction> <pressure-Pa> [gas|dense|supercritical]\n";
        return 64;
    }
    const int component_ids[2] = {
        PXTeqpComponentCarbonDioxide,
        std::atoi(argv[1])
    };
    const std::string observable = argv[2];
    if (observable == "density") {
        if (argc < 6) { return 64; }
        const double component2 = std::strtod(argv[4], nullptr);
        const double fractions[2] = {1.0 - component2, component2};
        PXTeqpNComponentDensityResult result{};
        char error[1024] = {};
        PXTeqpDensityRootSelectionHint hint = PXTeqpDensityRootSelectionAutomatic;
        if (argc == 7 && std::string(argv[6]) == "gas") { hint = PXTeqpDensityRootSelectionHomogeneousGas; }
        if (argc == 7 && std::string(argv[6]) == "dense") { hint = PXTeqpDensityRootSelectionHomogeneousLiquidOrDense; }
        if (argc == 7 && std::string(argv[6]) == "supercritical") { hint = PXTeqpDensityRootSelectionSupercritical; }
        const int code = px_teqp_calculate_ncomponent_density(
            component_ids, fractions, 2, std::strtod(argv[5], nullptr),
            std::strtod(argv[3], nullptr), hint,
            &result, error, sizeof(error)
        );
        std::cout << std::setprecision(17)
                  << code << ',' << result.converged << ',' << result.density_kg_m3 << ','
                  << result.density_root_count << ',' << result.selected_root_index << ','
                  << (result.selected_root_index >= 0
                      ? result.root_minimum_stability_eigenvalues[result.selected_root_index] : 0.0)
                  << ',' << error << '\n';
        return 0;
    }
    const auto specification = observable == "bubble"
        ? PXTeqpEquilibriumBubble : PXTeqpEquilibriumDew;
    const double component2 = std::strtod(argv[4], nullptr);
    const double specified[2] = {1.0 - component2, component2};
    double liquid[2] = {};
    double vapor[2] = {};
    PXTeqpNComponentVLEResult result{};
    char error[1024] = {};
    const int code = px_teqp_calculate_ncomponent_vle(
        component_ids,
        specified,
        2,
        std::strtod(argv[3], nullptr),
        specification,
        liquid,
        2,
        vapor,
        2,
        &result,
        error,
        sizeof(error)
    );
    std::cout << std::setprecision(17)
              << code << ',' << result.converged << ',' << result.status << ','
              << result.pressure_pa << ',' << liquid[1] << ',' << vapor[1] << ','
              << result.liquid_minimum_stability_eigenvalue << ','
              << result.vapor_minimum_stability_eigenvalue << ','
              << result.iteration_count << ',' << error << '\n';
    return 0;
}
