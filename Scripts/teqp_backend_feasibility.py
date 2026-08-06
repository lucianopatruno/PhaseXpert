#!/usr/bin/env python3
"""Generate the PhaseXpert teqp backend feasibility report.

The report is intentionally evidence-led. It records the native teqp API and
model-data blockers found before any PhaseXpert-owned continuation solver was
implemented, and therefore emits no fabricated phase-boundary points.
"""

from __future__ import annotations

import argparse
import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


TEQP_TAG = "v0.23.2"
TEQP_COMMIT = "5f62a6f515d517e39c3fb035c11a03524ffa3ad6"

REQUIRED_COMPONENTS = [
    "CO2",
    "N2",
    "O2",
    "Ar",
    "H2",
    "CH4",
    "CO",
    "H2S",
    "H2O",
]

GERG2008_NAMES = {
    "CO2": "carbondioxide",
    "N2": "nitrogen",
    "O2": "oxygen",
    "Ar": "argon",
    "H2": "hydrogen",
    "CH4": "methane",
    "CO": "carbonmonoxide",
    "H2S": "hydrogensulfide",
    "H2O": "water",
}


@dataclass(frozen=True)
class CompositionCase:
    identifier: str
    components: tuple[str, ...]
    mole_fractions: tuple[float, ...]
    category: str
    normalized_input: bool
    safely_normalizable: bool = False


PRIMARY_CASES = [
    CompositionCase("pure-co2", ("CO2",), (1.0,), "primary", True),
    CompositionCase("co2-97-n2-3", ("CO2", "N2"), (0.97, 0.03), "primary", True),
    CompositionCase("co2-90-n2-10", ("CO2", "N2"), (0.90, 0.10), "primary", True),
]

ADDITIONAL_CASES = [
    CompositionCase("near-pure-co2-n2", ("CO2", "N2"), (0.999, 0.001), "additional", True),
    CompositionCase("ppm-n2-in-co2", ("CO2", "N2"), (0.999999, 0.000001), "additional", True),
    CompositionCase("co2-n2-o2-ar", ("CO2", "N2", "O2", "Ar"), (0.96, 0.02, 0.01, 0.01), "additional", True),
    CompositionCase("co2-ch4-h2-co", ("CO2", "CH4", "H2", "CO"), (0.95, 0.03, 0.01, 0.01), "additional", True),
    CompositionCase("co2-h2s-h2o-n2", ("CO2", "H2S", "H2O", "N2"), (0.97, 0.01, 0.005, 0.015), "additional", True),
    CompositionCase("safely-normalizable", ("CO2", "N2"), (0.9700000000000001, 0.03), "additional", False, True),
]

INVALID_CASES = [
    CompositionCase("invalid-empty", tuple(), tuple(), "invalid", False),
    CompositionCase("invalid-negative", ("CO2", "N2"), (1.01, -0.01), "invalid", False),
    CompositionCase("invalid-nonnormalized", ("CO2", "N2"), (0.80, 0.10), "invalid", False),
    CompositionCase("invalid-duplicate", ("CO2", "CO2"), (0.5, 0.5), "invalid", False),
    CompositionCase("invalid-unsupported", ("CO2", "Xe"), (0.99, 0.01), "invalid", False),
    CompositionCase("invalid-nonfinite", ("CO2", "N2"), (math.nan, 0.03), "invalid", False),
    CompositionCase("invalid-out-of-domain", ("CO2", "N2"), (1.0, 0.0), "invalid", False),
]

ALL_CASES = PRIMARY_CASES + ADDITIONAL_CASES + INVALID_CASES


def validate_composition(case: CompositionCase) -> dict[str, object]:
    if not case.components:
        return {"valid": False, "reason": "empty composition"}
    if len(case.components) != len(case.mole_fractions):
        return {"valid": False, "reason": "component and mole fraction counts differ"}
    if len(set(case.components)) != len(case.components):
        return {"valid": False, "reason": "duplicate component"}
    for component in case.components:
        if component not in REQUIRED_COMPONENTS:
            return {"valid": False, "reason": f"unsupported component: {component}"}
    for value in case.mole_fractions:
        if not math.isfinite(value):
            return {"valid": False, "reason": "non-finite mole fraction"}
        if value < 0:
            return {"valid": False, "reason": "negative mole fraction"}
    total = math.fsum(case.mole_fractions)
    if not math.isfinite(total) or total <= 0:
        return {"valid": False, "reason": "non-positive composition sum"}
    if any(value == 0 for value in case.mole_fractions):
        return {"valid": False, "reason": "boundary-pinned composition"}
    normalized = abs(total - 1.0) <= 1e-12
    if not normalized and not case.safely_normalizable:
        return {"valid": False, "reason": "composition is not normalized"}
    if case.safely_normalizable:
        return {
            "valid": True,
            "reason": "accepted only after explicit caller normalization",
            "requires_explicit_normalization": True,
        }
    return {"valid": True, "reason": "composition accepted", "requires_explicit_normalization": False}


def json_mole_fractions(case: CompositionCase) -> list[float | str]:
    values: list[float | str] = []
    for value in case.mole_fractions:
        if math.isfinite(value):
            values.append(value)
        elif math.isnan(value):
            values.append("non-finite:nan")
        elif value > 0:
            values.append("Infinity")
        else:
            values.append("-Infinity")
    return values


def model_support_matrix() -> list[dict[str, object]]:
    return [
        {
            "identifier": "teqp-gerg2008resid",
            "model_family": "GERG-2008 residual model",
            "source_and_license": "Hard-coded in teqp source under the teqp NIST public-domain-style notice.",
            "supported_components": REQUIRED_COMPONENTS,
            "phase_equilibrium_apis": [
                "mix_VLE_Tx",
                "mix_VLE_Tp",
                "mixture_VLE_px",
                "trace_VLE_isotherm_binary",
                "trace_VLE_isobar_binary",
                "trace_critical_arclength_binary",
                "solve_pure_critical",
                "get_fugacity_coefficients",
                "get_chempotVLE_autodiff",
            ],
            "limitations": [
                "No turnkey public native multicomponent envelope tracer was found.",
                "Mixture bubble and dew routines require caller-provided starting densities and component specification.",
                "PhaseXpert would need bounded initialization, continuation, root tracking, stability checks, branch classification, and detached-segment rejection.",
                "Natural-gas GERG-2008 component coverage does not establish CCS phase-boundary accuracy.",
            ],
            "gate_status": "blocked_before_numerical_benchmark",
        },
        {
            "identifier": "teqp-multifluid-coolprop-format",
            "model_family": "teqp multifluid model using CoolProp-format fluid and mixture data",
            "source_and_license": "Requires a separately pinned CoolProp-format data tree and mixture files; not bundled with teqp.",
            "supported_components": "depends on pinned data tree and mixture/departure files",
            "phase_equilibrium_apis": [
                "mix_VLE_Tx",
                "mix_VLE_Tp",
                "mixture_VLE_px",
                "binary VLE tracing APIs",
                "critical APIs",
            ],
            "limitations": [
                "Open redistribution is plausible for MIT CoolProp data but must be pinned and packaged separately.",
                "Current PhaseXpert main does not carry a proven scoped teqp multifluid data bundle.",
                "Same caller-owned initialization and continuation responsibilities apply.",
            ],
            "gate_status": "model_data_unproven",
        },
        {
            "identifier": "teqp-canonical-srk",
            "model_family": "Soave-Redlich-Kwong cubic EOS",
            "source_and_license": "Requires caller-supplied pure critical data, acentric factors, alpha function choices, and binary interaction matrix.",
            "supported_components": "not accepted as complete for PhaseXpert without a pinned open parameter and BIP dataset",
            "phase_equilibrium_apis": [
                "cubic model construction",
                "bubble/dew state solves",
                "binary tracing APIs",
            ],
            "limitations": [
                "The repository main branch does not contain a complete vetted open BIP matrix for the required impurity set.",
                "Using zero or estimated BIPs would violate PhaseXpert scientific safeguards.",
                "PR #28 is preserved only as native-SRK feasibility evidence and is not reused here.",
            ],
            "gate_status": "required_parameters_absent",
        },
        {
            "identifier": "teqp-canonical-pr",
            "model_family": "Peng-Robinson cubic EOS",
            "source_and_license": "Requires caller-supplied pure critical data, acentric factors, alpha function choices, and binary interaction matrix.",
            "supported_components": "not accepted as complete for PhaseXpert without a pinned open parameter and BIP dataset",
            "phase_equilibrium_apis": [
                "cubic model construction",
                "bubble/dew state solves",
                "binary tracing APIs",
            ],
            "limitations": [
                "The repository main branch does not contain a complete vetted open BIP matrix for the required impurity set.",
                "Using zero or estimated BIPs would violate PhaseXpert scientific safeguards.",
                "No single PR model can be reported as a validated continuation backend from available evidence.",
            ],
            "gate_status": "required_parameters_absent",
        },
    ]


def result_for(model: dict[str, object], case: CompositionCase, branch: str) -> dict[str, object]:
    validation = validate_composition(case)
    invalid = not validation["valid"]
    if invalid:
        status = "rejected_before_teqp"
        termination = validation["reason"]
    else:
        status = model["gate_status"]
        termination = "stop condition reached before numerical benchmark: public native interface and data review require PhaseXpert-owned initialization and continuation solver development"
    return {
        "model": model["identifier"],
        "case": case.identifier,
        "branch": branch,
        "components": list(case.components),
        "mole_fractions": json_mole_fractions(case),
        "validation": validation,
        "attempted_points": 0,
        "converged_points": 0,
        "accepted_points": 0,
        "rejected_points": 0,
        "temperature_range_K": None,
        "pressure_range_Pa": None,
        "lowest_accepted_temperature_K": None,
        "highest_accepted_temperature_K": None,
        "last_accepted_state": None,
        "continuous_coverage": "none",
        "gaps": [],
        "detached_segments": [],
        "pressure_error_relative": {
            "mean": None,
            "median": None,
            "rms": None,
            "p95": None,
            "max": None,
            "sample_count": 0,
            "basis": "no genuine continuous accepted boundary interval",
        },
        "equilibrium_residuals": None,
        "critical_region_behavior": "not evaluated",
        "phase_compositions": None,
        "root_or_phase_identities": None,
        "status": status,
        "termination_reason": termination,
    }


def generate_report() -> dict[str, object]:
    models = model_support_matrix()
    case_results = [
        result_for(model, case, branch)
        for model in models
        for case in ALL_CASES
        for branch in ("bubble", "dew")
    ]
    return {
        "schema_version": 1,
        "created_by": "Scripts/teqp_backend_feasibility.py",
        "repository_context": {
            "accepted_main": "f75052489baf8efb798fffcb77137b730d4ceaa4",
            "protected_artifacts_preserved": [
                "PhaseXpert.xcodeproj/project.pbxproj",
                "Services/",
                "Vendor/ThermoPack/",
                "Vendor/CoolProp/ ignored artifacts",
                "Xcode, SwiftPM, pytest, .DS_Store, dependency, and cache artifacts",
            ],
            "prior_prs_preserved": {
                "28": {
                    "branch": "agent/native-srk-phase-envelope-prototype",
                    "head": "6537f82a5d894dc172270ff5d1cb153d405c30e1",
                    "status": "open draft, untouched",
                },
                "29": {
                    "branch": "agent/coolprop8-backend-feasibility",
                    "head": "1b0c39131e9a63ea05983b14532ce553e0f98467",
                    "status": "open draft, untouched",
                },
            },
        },
        "teqp_source": {
            "release": TEQP_TAG,
            "commit": TEQP_COMMIT,
            "repository": "https://github.com/usnistgov/teqp",
            "documentation": "https://teqp.readthedocs.io/",
            "license": "NIST public-domain-style notice with disclaimer in LICENSE.md",
            "language_standard": "C++20",
            "runtime_constraints": {
                "python_required": False,
                "java_required": False,
                "fortran_required": False,
                "network_required": False,
                "refprop_required": False,
            },
            "transitive_source_dependencies": [
                "Catch2 4e8d92bf02f7d1c8006a0e7a5ecabd8e62d98502",
                "Eigen da19f7a9105374958cad7f9ee17c4596a54be51c",
                "REFPROP-interop 07562a51241431ea6cccbaffb3dd5274364ae99e",
                "autodiff cb2d6e867b105cd0090ebcce8bddf05a4592b6ab",
                "json-schema-validator 920bddd7c0aeb26fa02f45f56743aef750cfcc89",
                "mcx bc5f996f090a93e7e4e9358c4ee20bf06db57afc",
                "pybind11 8862cd4ef96b16d17a66a81ecd3b6e1604362fd7",
            ],
        },
        "native_cpp_interface_findings": {
            "pure_saturation": "pure_VLE_T and solve_pure_critical are exposed",
            "mixture_bubble_dew": "mix_VLE_Tx, mix_VLE_Tp, and mixture_VLE_px are exposed but require caller-supplied initial liquid and vapor density vectors",
            "binary_vle_continuation": "trace_VLE_isotherm_binary and trace_VLE_isobar_binary are exposed for binary systems",
            "multicomponent_vle_continuation": "no turnkey public native multicomponent envelope tracer was found",
            "critical_locus": "trace_critical_arclength_binary and criticality condition APIs are exposed; general multicomponent locus tracing was not established",
            "stability_phase_identification": "fugacity coefficients, chemical-potential VLE residuals, and Hessian helpers are exposed; PhaseXpert would still own stability classification and branch/root tracking",
            "c_interface": "teqp can build an optional teqpc shared-library target, but this milestone did not establish a stable static C ABI suitable for Swift",
        },
        "cmake_compile_probe": {
            "host": "macOS",
            "compiler": "AppleClang 21.0.0.21000101",
            "command": "cmake -DTEQP_NO_PYTHON=ON -DTEQP_NO_TESTS=ON -DTEQP_NO_TEQPCPP=OFF -DTEQP_TEQPC=OFF",
            "result": "passed",
            "configure_seconds": 73.25,
            "build_seconds": 404.01,
            "source_size": "238M",
            "build_tree_size": "424M",
            "static_library": "libteqpcpp.a",
            "static_library_size": "62M",
            "apple_platform_blockers": [
                "No macOS C++ compile blocker found.",
                "iOS cross-compilation, symbol collision, binary footprint, and static C bridge feasibility remain unproven.",
            ],
        },
        "model_selection_matrix": models,
        "cases": [
            {
                "identifier": case.identifier,
                "category": case.category,
                "components": list(case.components),
                "mole_fractions": json_mole_fractions(case),
                "validation": validate_composition(case),
            }
            for case in ALL_CASES
        ],
        "case_results": case_results,
        "comparisons": {
            "neqsim_fixture": "Documentation/Feasibility/LocalPhaseDiagramNeqSimReferenceDataset.json used only as offline parity evidence; not used as a solver target",
            "production_coolprop": "No production CoolProp provider or XCFramework was modified or replaced",
            "pr28_native_srk": {
                "head": "6537f82a5d894dc172270ff5d1cb153d405c30e1",
                "result": "custom native SRK failed numerical gate",
                "lowest_90_10_bubble_temperature_K": 139.986665,
                "pure_co2_endpoint_gap_K": 14.096,
            },
            "pr29_coolprop8": {
                "head": "1b0c39131e9a63ea05983b14532ce553e0f98467",
                "result": "CoolProp 8 HEOS, SRK, and PR phase-envelope implementations failed macOS scientific gate",
            },
        },
        "runtime_and_safety": {
            "complete_teqp_numerical_benchmark_runs": 0,
            "normalized_json_deterministic": True,
            "timeout_strategy": "Required for any future numerical probe: isolate non-interruptible native calls in a killable subprocess with fixed deadline",
            "cancellation_strategy": "Only cooperative between caller-owned bounded operations was established; internal teqp call interruption was not established",
            "peak_memory": "Not measured for numerical benchmark because benchmark stopped before solver implementation",
            "no_process_remains_required": True,
        },
        "gates": {
            "scientific_gate": "failed_before_numerical_benchmark",
            "architectural_gate": "partially feasible on macOS C++ build only; native/offline iOS architecture remains unproven",
            "required_classification": "teqp requires excessive PhaseXpert-owned solver development",
            "ios_packaging_justified": False,
            "recommended_next_step": "Review whether PhaseXpert should reject teqp for phase-boundary work or authorize a separately bounded non-production prototype limited to proving one GERG2008 multicomponent bubble/dew continuation path with explicit initialization and stability criteria.",
        },
    }


def normalized_json(report: dict[str, object]) -> str:
    return json.dumps(report, indent=2, sort_keys=True, allow_nan=False) + "\n"


def write_report(output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(normalized_json(generate_report()), encoding="utf-8")


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("Documentation/Feasibility/TeqpComparisonResults.json"),
    )
    args = parser.parse_args(argv)
    write_report(args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
