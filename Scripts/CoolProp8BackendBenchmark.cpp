#include "CoolProp/AbstractState.h"
#include "CoolProp/Configuration.h"
#include "CoolProp/CoolProp.h"

#include <cmath>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

struct Component {
    std::string id;
    std::string coolpropName;
    double fraction;
};

struct CaseDefinition {
    std::string id;
    std::vector<Component> components;
    bool valid;
    std::string invalidReason;
};

std::string escapeJSON(const std::string &value) {
    std::ostringstream escaped;
    for (const char character : value) {
        switch (character) {
        case '\\': escaped << "\\\\"; break;
        case '"': escaped << "\\\""; break;
        case '\n': escaped << "\\n"; break;
        case '\r': escaped << "\\r"; break;
        case '\t': escaped << "\\t"; break;
        default: escaped << character; break;
        }
    }
    return escaped.str();
}

void writeJSONString(const std::string &value) {
    std::cout << '"' << escapeJSON(value) << '"';
}

void writeJSONNumber(double value) {
    if (std::isfinite(value)) {
        std::cout << std::setprecision(17) << value;
    } else {
        std::cout << "null";
    }
}

const std::vector<CaseDefinition> &cases() {
    static const std::vector<CaseDefinition> definitions = {
        {
            "pure-co2",
            {{"co2", "CarbonDioxide", 1.0}},
            true,
            ""
        },
        {
            "co2-97-n2-3",
            {{"co2", "CarbonDioxide", 0.97}, {"n2", "Nitrogen", 0.03}},
            true,
            ""
        },
        {
            "co2-90-n2-10",
            {{"co2", "CarbonDioxide", 0.90}, {"n2", "Nitrogen", 0.10}},
            true,
            ""
        },
        {
            "co2-99999ppm-n2-1ppm",
            {{"co2", "CarbonDioxide", 0.999999}, {"n2", "Nitrogen", 0.000001}},
            true,
            ""
        },
        {
            "co2-999-n2-001",
            {{"co2", "CarbonDioxide", 0.999}, {"n2", "Nitrogen", 0.001}},
            true,
            ""
        },
        {
            "co2-96-n2-2-o2-1-ar-05-ch4-05",
            {
                {"co2", "CarbonDioxide", 0.96},
                {"n2", "Nitrogen", 0.02},
                {"o2", "Oxygen", 0.01},
                {"ar", "Argon", 0.005},
                {"ch4", "Methane", 0.005}
            },
            true,
            ""
        },
        {
            "co2-95-n2-3-ar-1-ch4-05-h2-05",
            {
                {"co2", "CarbonDioxide", 0.95},
                {"n2", "Nitrogen", 0.03},
                {"ar", "Argon", 0.01},
                {"ch4", "Methane", 0.005},
                {"h2", "Hydrogen", 0.005}
            },
            true,
            ""
        },
        {
            "co2-90-n2-4-o2-2-ar-2-ch4-1-h2-1",
            {
                {"co2", "CarbonDioxide", 0.90},
                {"n2", "Nitrogen", 0.04},
                {"o2", "Oxygen", 0.02},
                {"ar", "Argon", 0.02},
                {"ch4", "Methane", 0.01},
                {"h2", "Hydrogen", 0.01}
            },
            true,
            ""
        },
        {
            "invalid-nonnormalized",
            {{"co2", "CarbonDioxide", 0.90}, {"n2", "Nitrogen", 0.03}},
            false,
            "Composition sums to 0.93; PhaseXpert must not normalize it silently."
        },
        {
            "invalid-negative",
            {{"co2", "CarbonDioxide", 1.01}, {"n2", "Nitrogen", -0.01}},
            false,
            "Composition contains a negative mole fraction."
        },
        {
            "invalid-nonfinite",
            {{"co2", "CarbonDioxide", std::nan("")}, {"n2", "Nitrogen", 0.03}},
            false,
            "Composition contains a non-finite mole fraction."
        },
        {
            "invalid-unsupported-component",
            {{"co2", "CarbonDioxide", 0.99}, {"h2o", "Water", 0.01}},
            false,
            "Water is outside the current dry PhaseXpert CoolProp scope."
        },
        {
            "invalid-out-of-domain-impurity",
            {{"co2", "CarbonDioxide", 0.85}, {"n2", "Nitrogen", 0.15}},
            false,
            "Total impurity exceeds the current PhaseXpert 10 mol% guardrail."
        }
    };
    return definitions;
}

const CaseDefinition &findCase(const std::string &caseID) {
    for (const auto &candidate : cases()) {
        if (candidate.id == caseID) {
            return candidate;
        }
    }
    throw std::runtime_error("Unknown case: " + caseID);
}

std::string fluidList(const CaseDefinition &caseDefinition) {
    std::string fluids;
    bool first = true;
    for (const auto &component : caseDefinition.components) {
        if (!std::isfinite(component.fraction) || component.fraction <= 1e-14) {
            continue;
        }
        if (!first) {
            fluids += "&";
        }
        fluids += component.coolpropName;
        first = false;
    }
    return fluids;
}

std::vector<double> fractions(const CaseDefinition &caseDefinition) {
    std::vector<double> values;
    for (const auto &component : caseDefinition.components) {
        if (std::isfinite(component.fraction) && component.fraction > 1e-14) {
            values.push_back(component.fraction);
        }
    }
    return values;
}

std::shared_ptr<CoolProp::AbstractState> makeState(
    const std::string &backend,
    const CaseDefinition &caseDefinition
) {
    std::shared_ptr<CoolProp::AbstractState> state(
        CoolProp::AbstractState::factory(backend, fluidList(caseDefinition))
    );
    const auto moleFractions = fractions(caseDefinition);
    if (moleFractions.size() > 1) {
        state->set_mole_fractions(moleFractions);
    }
    return state;
}

std::string phaseName(CoolProp::phases phase) {
    switch (phase) {
    case CoolProp::iphase_liquid: return "liquid";
    case CoolProp::iphase_gas: return "gas";
    case CoolProp::iphase_twophase: return "twophase";
    case CoolProp::iphase_supercritical: return "supercritical";
    case CoolProp::iphase_supercritical_gas: return "supercritical_gas";
    case CoolProp::iphase_supercritical_liquid: return "supercritical_liquid";
    case CoolProp::iphase_critical_point: return "critical_point";
    case CoolProp::iphase_unknown: return "unknown";
    case CoolProp::iphase_not_imposed: return "not_imposed";
    default: return "other";
    }
}

void writeCaseHeader(
    const std::string &operation,
    const std::string &backend,
    const CaseDefinition &caseDefinition
) {
    std::cout << "{";
    std::cout << "\"schema_version\":\"phasexpert-coolprop8-raw.v1\",";
    std::cout << "\"coolprop_version\":";
    writeJSONString(CoolProp::get_global_param_string("version"));
    std::cout << ",\"coolprop_gitrevision\":";
    writeJSONString(CoolProp::get_global_param_string("gitrevision"));
    std::cout << ",\"backend\":";
    writeJSONString(backend);
    std::cout << ",\"operation\":";
    writeJSONString(operation);
    std::cout << ",\"case_id\":";
    writeJSONString(caseDefinition.id);
    std::cout << ",\"fluid_identifiers\":[";
    for (std::size_t index = 0; index < caseDefinition.components.size(); ++index) {
        if (index != 0) {
            std::cout << ",";
        }
        writeJSONString(caseDefinition.components[index].coolpropName);
    }
    std::cout << "],\"composition\":[";
    for (std::size_t index = 0; index < caseDefinition.components.size(); ++index) {
        if (index != 0) {
            std::cout << ",";
        }
        std::cout << "{\"component\":";
        writeJSONString(caseDefinition.components[index].id);
        std::cout << ",\"mole_fraction\":";
        writeJSONNumber(caseDefinition.components[index].fraction);
        std::cout << "}";
    }
    std::cout << "]";
}

void writeInvalidResult(
    const std::string &operation,
    const std::string &backend,
    const CaseDefinition &caseDefinition
) {
    writeCaseHeader(operation, backend, caseDefinition);
    std::cout << ",\"status\":\"rejected_before_coolprop\",";
    std::cout << "\"termination_reason\":";
    writeJSONString(caseDefinition.invalidReason);
    std::cout << "}\n";
}

void runEnvelope(const std::string &backend, const CaseDefinition &caseDefinition) {
    if (!caseDefinition.valid) {
        writeInvalidResult("build_phase_envelope", backend, caseDefinition);
        return;
    }
    writeCaseHeader("build_phase_envelope", backend, caseDefinition);
    try {
        auto state = makeState(backend, caseDefinition);
        state->build_phase_envelope("");
        const auto &envelope = state->get_phase_envelope_data();
        std::cout << ",\"status\":\"returned\",";
        std::cout << "\"is_complete\":" << (envelope.built ? "true" : "false") << ",";
        std::cout << "\"is_closed\":" << (envelope.closed ? "true" : "false") << ",";
        std::cout << "\"icrit\":" << envelope.icrit << ",";
        std::cout << "\"points\":[";
        for (std::size_t index = 0; index < envelope.T.size(); ++index) {
            if (index != 0) {
                std::cout << ",";
            }
            std::string branch = "unknown";
            if (static_cast<int>(index) == envelope.icrit) {
                branch = "critical";
            } else if (index < envelope.Q.size()) {
                branch = envelope.Q[index] < 0.5 ? "bubble" : "dew";
            }
            std::cout << "{\"provider_order\":" << index
                      << ",\"temperature_k\":";
            writeJSONNumber(envelope.T[index]);
            std::cout << ",\"pressure_pa\":";
            writeJSONNumber(envelope.p[index]);
            std::cout << ",\"quality\":";
            writeJSONNumber(index < envelope.Q.size() ? envelope.Q[index] : std::nan(""));
            std::cout << ",\"branch\":";
            writeJSONString(branch);
            std::cout << "}";
        }
        std::cout << "]}";
    } catch (const std::exception &error) {
        std::cout << ",\"status\":\"threw\",\"termination_reason\":";
        writeJSONString(error.what());
        std::cout << "}";
    }
    std::cout << "\n";
}

void runPTFlash(const std::string &backend, const CaseDefinition &caseDefinition) {
    if (!caseDefinition.valid) {
        writeInvalidResult("pt_flash", backend, caseDefinition);
        return;
    }
    writeCaseHeader("pt_flash", backend, caseDefinition);
    std::cout << ",\"status\":\"returned\",";
    std::cout << "\"stability_algorithm\":\"CoolProp default MIXTURE_STABILITY_ALGORITHM\",";
    std::cout << "\"samples\":[";
    const std::vector<double> temperaturesK = {190, 220, 250, 280, 300};
    const std::vector<double> pressuresPa = {100000, 1000000, 5000000, 8000000};
    bool first = true;
    for (double temperatureK : temperaturesK) {
        for (double pressurePa : pressuresPa) {
            if (!first) {
                std::cout << ",";
            }
            first = false;
            std::cout << "{\"temperature_k\":";
            writeJSONNumber(temperatureK);
            std::cout << ",\"pressure_pa\":";
            writeJSONNumber(pressurePa);
            try {
                auto state = makeState(backend, caseDefinition);
                state->update(CoolProp::PT_INPUTS, pressurePa, temperatureK);
                std::cout << ",\"status\":\"converged\",\"phase\":";
                writeJSONString(phaseName(state->phase()));
                std::cout << ",\"density_molar\":";
                writeJSONNumber(state->rhomolar());
                std::cout << ",\"quality\":";
                try {
                    writeJSONNumber(state->Q());
                } catch (...) {
                    std::cout << "null";
                }
            } catch (const std::exception &error) {
                std::cout << ",\"status\":\"failed\",\"termination_reason\":";
                writeJSONString(error.what());
            }
            std::cout << "}";
        }
    }
    std::cout << "]}\n";
}

void runCritical(const std::string &backend, const CaseDefinition &caseDefinition) {
    if (!caseDefinition.valid) {
        writeInvalidResult("critical_points", backend, caseDefinition);
        return;
    }
    writeCaseHeader("critical_points", backend, caseDefinition);
    try {
        auto state = makeState(backend, caseDefinition);
        const auto criticalPoints = state->all_critical_points();
        std::cout << ",\"status\":\"returned\",\"critical_points\":[";
        for (std::size_t index = 0; index < criticalPoints.size(); ++index) {
            if (index != 0) {
                std::cout << ",";
            }
            std::cout << "{\"temperature_k\":";
            writeJSONNumber(criticalPoints[index].T);
            std::cout << ",\"pressure_pa\":";
            writeJSONNumber(criticalPoints[index].p);
            std::cout << ",\"density_molar\":";
            writeJSONNumber(criticalPoints[index].rhomolar);
            std::cout << ",\"stable\":" << (criticalPoints[index].stable ? "true" : "false") << "}";
        }
        std::cout << "]}";
    } catch (const std::exception &error) {
        std::cout << ",\"status\":\"threw\",\"termination_reason\":";
        writeJSONString(error.what());
        std::cout << "}";
    }
    std::cout << "\n";
}

} // namespace

int main(int argc, char **argv) {
    if (argc != 4) {
        std::cerr << "Usage: coolprop8_backend_benchmark <operation> <backend> <case-id>\n";
        return 2;
    }
    const std::string operation = argv[1];
    const std::string backend = argv[2];
    const CaseDefinition &caseDefinition = findCase(argv[3]);
    if (operation == "build_phase_envelope") {
        runEnvelope(backend, caseDefinition);
    } else if (operation == "pt_flash") {
        runPTFlash(backend, caseDefinition);
    } else if (operation == "critical_points") {
        runCritical(backend, caseDefinition);
    } else {
        std::cerr << "Unknown operation: " << operation << "\n";
        return 2;
    }
    return 0;
}
