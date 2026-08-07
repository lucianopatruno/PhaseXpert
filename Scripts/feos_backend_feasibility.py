#!/usr/bin/env python3
"""Generate the PhaseXpert FeOs backend feasibility report."""

from __future__ import annotations

import argparse
import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


FEOS_TAG = "v0.10.1"
FEOS_COMMIT = "c658aeab484f7a7096bfbf5425e40effd60da167"
ACCEPTED_MAIN = "f75052489baf8efb798fffcb77137b730d4ceaa4"

PHASEXPERT_COMPONENTS = {
    "CO2": "carbon dioxide",
    "N2": "nitrogen",
    "O2": "oxygen",
    "Ar": "argon",
    "H2": "hydrogen",
    "CH4": "methane",
    "CO": "carbon monoxide",
    "H2S": "hydrogen sulfide",
    "H2O": "water",
}

ESPER2023_PURE_PARAMETERS = {
    "CO2": {
        "name": "carbon dioxide",
        "cas": "124-38-9",
        "molarweight": 43.99,
        "m": 2.53096,
        "sigma": 2.57855,
        "epsilon_k": 153.31864,
        "source": "parameters/pcsaft/esper2023.json",
    },
    "N2": {
        "name": "nitrogen",
        "cas": "7727-37-9",
        "molarweight": 28.006,
        "m": 1.23831,
        "sigma": 3.30009,
        "epsilon_k": 89.41358,
        "association_sites": [{"nb": 2.0}],
        "source": "parameters/pcsaft/esper2023.json",
    },
    "O2": {
        "name": "oxygen",
        "cas": "7782-44-7",
        "molarweight": 31.99,
        "m": 1.14702,
        "sigma": 3.17933,
        "epsilon_k": 113.62724,
        "association_sites": [{"nb": 2.0}],
        "source": "parameters/pcsaft/esper2023.json",
    },
    "Ar": {
        "name": "argon",
        "cas": "7440-37-1",
        "molarweight": 39.962,
        "m": 1.0,
        "sigma": 3.37751,
        "epsilon_k": 117.80903,
        "source": "parameters/pcsaft/esper2023.json",
    },
    "H2": {
        "name": "hydrogen",
        "cas": "1333-74-0",
        "molarweight": 2.016,
        "m": 1.0,
        "sigma": 3.002,
        "epsilon_k": 51.343,
        "source": "parameters/pcsaft/eller2022.json",
        "limitation": "not in the primary Esper 2023 set; mixing with Esper 2023 would change parameter provenance",
    },
    "CH4": {
        "name": "methane",
        "cas": "74-82-8",
        "molarweight": 16.031,
        "m": 1.0,
        "sigma": 3.70051,
        "epsilon_k": 150.07147,
        "source": "parameters/pcsaft/esper2023.json",
    },
    "CO": {
        "name": "carbon monoxide",
        "cas": "630-08-0",
        "molarweight": 27.995,
        "m": 1.32286,
        "sigma": 3.24532,
        "epsilon_k": 91.17087,
        "source": "parameters/pcsaft/esper2023.json",
    },
    "H2S": {
        "name": "hydrogen sulfide",
        "cas": "7783-06-4",
        "molarweight": 33.988,
        "m": 1.63175,
        "sigma": 3.06168,
        "epsilon_k": 227.15574,
        "mu": 0.97,
        "source": "parameters/pcsaft/esper2023.json",
    },
    "H2O": {
        "name": "water",
        "cas": "7732-18-5",
        "molarweight": 18.011,
        "m": 2.36948,
        "sigma": 2.15072,
        "epsilon_k": 230.71557,
        "association_sites": [{"na": 1.0, "nb": 1.0, "kappa_ab": 0.35319, "epsilon_k_ab": 2195.10176}],
        "source": "parameters/pcsaft/esper2023.json",
    },
}

REHNER2023_BINARY_PARAMETERS = {
    ("CO2", "CH4"): {
        "k_ij": 0.0597617573623017,
        "source": "parameters/pcsaft/rehner2023_binary.json",
    },
    ("CO2", "CO"): {
        "k_ij": -0.0347536475083231,
        "source": "parameters/pcsaft/rehner2023_binary.json",
    },
}


@dataclass(frozen=True)
class CompositionCase:
    identifier: str
    components: tuple[str, ...]
    mole_fractions: tuple[float, ...]
    category: str


CORE_CASES = [
    CompositionCase("pure-co2", ("CO2",), (1.0,), "core"),
    CompositionCase("co2-97-n2-3", ("CO2", "N2"), (0.97, 0.03), "core"),
    CompositionCase("co2-90-n2-10", ("CO2", "N2"), (0.90, 0.10), "core"),
]

ADDITIONAL_CASES = [
    CompositionCase("near-pure-co2-n2", ("CO2", "N2"), (0.999, 0.001), "additional"),
    CompositionCase("ppm-n2-in-co2", ("CO2", "N2"), (0.999999, 0.000001), "additional"),
    CompositionCase("co2-n2-o2-ar", ("CO2", "N2", "O2", "Ar"), (0.96, 0.02, 0.01, 0.01), "additional"),
    CompositionCase("co2-ch4-h2-co", ("CO2", "CH4", "H2", "CO"), (0.95, 0.03, 0.01, 0.01), "additional"),
    CompositionCase("co2-h2s-h2o-n2", ("CO2", "H2S", "H2O", "N2"), (0.97, 0.01, 0.005, 0.015), "additional"),
]

INVALID_CASES = [
    CompositionCase("invalid-empty", tuple(), tuple(), "invalid"),
    CompositionCase("invalid-negative", ("CO2", "N2"), (1.01, -0.01), "invalid"),
    CompositionCase("invalid-nonnormalized", ("CO2", "N2"), (0.8, 0.1), "invalid"),
    CompositionCase("invalid-duplicate", ("CO2", "CO2"), (0.5, 0.5), "invalid"),
    CompositionCase("invalid-unsupported", ("CO2", "Xe"), (0.99, 0.01), "invalid"),
    CompositionCase("invalid-nonfinite", ("CO2", "N2"), (math.nan, 0.03), "invalid"),
]

ALL_CASES = CORE_CASES + ADDITIONAL_CASES + INVALID_CASES


def validate_composition(case: CompositionCase) -> dict[str, object]:
    if not case.components:
        return {"valid": False, "reason": "empty composition"}
    if len(case.components) != len(case.mole_fractions):
        return {"valid": False, "reason": "component and mole fraction counts differ"}
    if len(set(case.components)) != len(case.components):
        return {"valid": False, "reason": "duplicate component"}
    for component in case.components:
        if component not in PHASEXPERT_COMPONENTS:
            return {"valid": False, "reason": f"unsupported component: {component}"}
    for value in case.mole_fractions:
        if not math.isfinite(value):
            return {"valid": False, "reason": "non-finite mole fraction"}
        if value < 0:
            return {"valid": False, "reason": "negative mole fraction"}
    if abs(math.fsum(case.mole_fractions) - 1.0) > 1e-12:
        return {"valid": False, "reason": "composition is not normalized"}
    if any(value <= 0.0 for value in case.mole_fractions) and len(case.components) > 1:
        return {"valid": False, "reason": "boundary-pinned composition"}
    return {"valid": True, "reason": "composition accepted"}


def json_mole_fractions(case: CompositionCase) -> list[float | str]:
    values: list[float | str] = []
    for value in case.mole_fractions:
        values.append(value if math.isfinite(value) else "non-finite:nan")
    return values


def missing_binary_pairs(components: tuple[str, ...]) -> list[str]:
    missing: list[str] = []
    for i, left in enumerate(components):
        for right in components[i + 1 :]:
            pair = tuple(sorted((left, right)))
            available = {tuple(sorted(key)) for key in REHNER2023_BINARY_PARAMETERS}
            if pair not in available:
                missing.append(f"{left}/{right}")
    return missing


def result_for(case: CompositionCase, branch: str) -> dict[str, object]:
    validation = validate_composition(case)
    missing_pairs = [] if not validation["valid"] else missing_binary_pairs(case.components)
    if not validation["valid"]:
        status = "rejected_before_feos"
        termination = validation["reason"]
    elif case.identifier == "pure-co2":
        status = "not_run"
        termination = "native Rust benchmark could not run because cargo/rustc are unavailable in this environment"
    elif missing_pairs:
        status = "blocked_missing_binary_interaction_parameters"
        termination = "missing required PC-SAFT binary interaction parameters: " + ", ".join(missing_pairs)
    else:
        status = "not_run"
        termination = "native Rust benchmark could not run because cargo/rustc are unavailable in this environment"
    return {
        "case": case.identifier,
        "branch": branch,
        "components": list(case.components),
        "mole_fractions": json_mole_fractions(case),
        "validation": validation,
        "parameter_status": {
            "pure_parameters_available": all(component in ESPER2023_PURE_PARAMETERS for component in case.components),
            "missing_binary_interaction_parameters": missing_pairs,
        },
        "attempted_points": 0,
        "converged_points": 0,
        "accepted_points": 0,
        "rejected_points": 0,
        "temperature_range_K": None,
        "pressure_range_Pa": None,
        "lowest_accepted_temperature_K": None,
        "highest_accepted_temperature_K": None,
        "continuous_intervals": [],
        "gaps": [],
        "detached_segments": [],
        "last_accepted_state": None,
        "liquid_compositions": None,
        "vapor_compositions": None,
        "phase_distinction": "not evaluated",
        "equilibrium_residuals": None,
        "critical_region_behavior": "not evaluated",
        "pressure_error_relative": {
            "mean": None,
            "median": None,
            "rms": None,
            "p95": None,
            "max": None,
            "sample_count": 0,
            "basis": "no FeOs-calculated accepted boundary interval",
        },
        "runtime_seconds": None,
        "status": status,
        "termination_reason": termination,
    }


def generate_report() -> dict[str, object]:
    return {
        "schema_version": 1,
        "created_by": "Scripts/feos_backend_feasibility.py",
        "repository_context": {
            "branch": "agent/feos-backend-feasibility",
            "accepted_main": ACCEPTED_MAIN,
            "protected_artifacts_preserved": [
                "PhaseXpert.xcodeproj/project.pbxproj",
                "Services/",
                "Vendor/ThermoPack/",
                "Vendor/CoolProp/ ignored artifacts",
                "Xcode, SwiftPM, Rust, Cargo, Python, dependency, and cache artifacts",
            ],
            "prior_prs_preserved": {
                "28": {"head": "6537f82a5d894dc172270ff5d1cb153d405c30e1", "status": "open draft, untouched"},
                "29": {"head": "1b0c39131e9a63ea05983b14532ce553e0f98467", "status": "open draft, untouched"},
                "30": {"head": "e303c9d2b6e636727edaef92b1e867e4c5a77976", "status": "open draft, untouched"},
            },
        },
        "feos_source": {
            "repository": "https://github.com/feos-org/feos",
            "releases": "https://github.com/feos-org/feos/releases",
            "rust_docs": ["https://docs.rs/feos", "https://docs.rs/feos-core"],
            "release": FEOS_TAG,
            "commit": FEOS_COMMIT,
            "license": "MIT OR Apache-2.0",
            "workspace_edition": "Rust 2024",
            "dependency_tree_status": "Cargo metadata for the full dependency tree could not run because cargo is not installed",
            "workspace_dependencies_from_cargo_toml": [
                "quantity 0.14",
                "num-dual 0.14",
                "ndarray 0.17",
                "nalgebra 0.35",
                "thiserror 2.0",
                "conv 0.3",
                "num-traits 0.2",
                "serde 1.0",
                "serde_json 1.0",
                "indexmap 2.0",
                "itertools 0.15",
                "rayon 1.11",
                "petgraph 0.8",
                "rustdct 0.7",
                "rustfft 6.0",
                "libm 0.2",
                "gauss-quad 0.3",
                "approx 0.5",
                "criterion 0.8",
                "paste 1.0",
                "rusqlite 0.40",
                "csv 1.0",
            ],
        },
        "native_rust_api_findings": {
            "pure_saturation": "PhaseDiagram::pure and PhaseEquilibrium::pure exist",
            "bubble_point_state": "PhaseEquilibrium::bubble_point exists for generic composition dimensions",
            "dew_point_state": "PhaseEquilibrium::dew_point exists for generic composition dimensions",
            "fixed_composition_lines": "PhaseDiagram::bubble_point_line and PhaseDiagram::dew_point_line exist and iterate high-level bubble/dew solves",
            "binary_diagrams": "PhaseDiagram::binary_vle exists for binary diagrams",
            "tp_flash": "PhaseEquilibrium::tp_flash and State::tp_flash exist and initialize through stability analysis when needed",
            "stability": "State::stability_analysis exists and returns negative-TPD states",
            "critical": "State::critical_point_pure, critical_point_binary, and critical_point exist",
            "phase_compositions": "PhaseEquilibrium exposes liquid and vapor State mole fractions",
            "residuals": "State exposes chemical_potential, residual_chemical_potential, and ln_phi",
            "solver_limits": "SolverOptions exposes max_iter and tol",
        },
        "model_selection": {
            "primary_model": "PC-SAFT using Esper 2023 pure parameters plus Rehner 2023 binary parameters where available",
            "parameter_license": "Bundled in FeOs repository under MIT OR Apache-2.0 project licensing; publication provenance documented in parameters/pcsaft/README.md",
            "pure_parameters": ESPER2023_PURE_PARAMETERS,
            "binary_parameters_found": {"/".join(key): value for key, value in REHNER2023_BINARY_PARAMETERS.items()},
            "co2_n2_parameter_search": [
                {
                    "source": "FeOs v0.10.1 parameters/pcsaft/rehner2023_binary.json",
                    "result": "no nitrogen entries and no CO2/N2 entry found",
                    "usable": False,
                },
                {
                    "source": "FeOs main branch parameters/pcsaft/rehner2023_binary.json",
                    "result": "no nitrogen entries and no CO2/N2 entry found",
                    "usable": False,
                },
                {
                    "source": "FeOs historical commits b946c0ef, 0129c5a3, d7d99fdd for rehner2023_binary.json",
                    "result": "historical database sizes 7860, 7860, and 7848 records respectively; no nitrogen or CO2/N2 record found",
                    "usable": False,
                },
                {
                    "source": "FeOs parameters/pcsaft/README.md and literature.bib",
                    "result": "Esper 2023 pure parameters and Rehner 2023 binary-parameter provenance identified; no directly packaged CO2/N2 BIP",
                    "usable": False,
                },
                {
                    "source": "Rehner, Bardow, Gross, International Journal of Thermophysics 44, 179 (2023), DOI 10.1007/s10765-023-03290-3",
                    "result": "publication is the source of FeOs Rehner 2023 parameter files; no redistributable CO2/N2 entry found in the FeOs dataset derived from it",
                    "usable": False,
                },
                {
                    "source": "Nikolaidis, Privat, Jaubert, Economou, Journal of Chemical & Engineering Data 69, 320-337 (2024), DOI 10.1021/acs.jced.2c00781",
                    "result": "relevant PC-SAFT BIP benchmark publication found; redistribution and FeOs Esper/Rehner compatibility for a CO2/N2 value remain unproven from accessible authoritative metadata",
                    "usable": False,
                },
                {
                    "source": "CO2 impurity / CCS PC-SAFT literature search",
                    "result": "papers discuss CO2/N2 and PC-SAFT, including cases with kij = 0 or fitted values, but no directly compatible, pinned, redistributable FeOs PC-SAFT CO2/N2 parameter was established",
                    "usable": False,
                },
            ],
            "required_missing_binary_parameters": [
                "CO2/N2",
                "CO2/O2",
                "CO2/Ar",
                "CO2/H2",
                "CO2/H2S",
                "CO2/H2O",
            ],
            "parameter_selection_decision": "The core CO2/N2 matrix is blocked because a required CO2/N2 PC-SAFT binary interaction parameter was not found in the pinned FeOs parameter files.",
        },
        "toolchain_probe": {
            "cargo": "not found",
            "rustc": "not evaluated because cargo command was unavailable in the shell path",
            "rust_benchmark_built": False,
            "rust_benchmark_ran": False,
        },
        "case_results": [
            result_for(case, branch)
            for case in ALL_CASES
            for branch in ("bubble", "dew")
        ],
        "comparisons": {
            "neqsim_fixture": "Documentation/Feasibility/LocalPhaseDiagramNeqSimReferenceDataset.json was not used as a solver target",
            "pr28_native_srk": {
                "head": "6537f82a5d894dc172270ff5d1cb153d405c30e1",
                "lowest_90_10_bubble_temperature_K": 139.986665,
                "pure_co2_endpoint_gap_K": 14.096,
                "result": "failed numerical gate",
            },
            "pr29_coolprop8": {
                "head": "1b0c39131e9a63ea05983b14532ce553e0f98467",
                "result": "HEOS, SRK, and PR failed macOS scientific gate",
            },
            "pr30_teqp": {
                "head": "e303c9d2b6e636727edaef92b1e867e4c5a77976",
                "result": "requires excessive PhaseXpert-owned solver development",
            },
        },
        "runtime_and_safety": {
            "complete_benchmark_runs": 0,
            "normalized_json_deterministic": True,
            "timing": "No FeOs numerical runtime because cargo/rustc are unavailable and CO2/N2 BIP provenance is missing.",
            "peak_memory": "Not measured; native benchmark did not run.",
            "timeout_strategy": "Future Rust harness must isolate non-interruptible calculations in a killable subprocess with a fixed deadline.",
            "cancellation_strategy": "Only planned cooperative cancellation between bounded grid points is documented; no native FeOs cancellation was executed.",
            "process_cleanup": "No FeOs benchmark process was started by this harness.",
        },
        "gates": {
            "scientific_gate": "failed_before_numerical_benchmark",
            "classification": "FeOs lacks the required parameters or component coverage",
            "phase_4_reached": False,
            "ios_compilation_gate": "not reached",
            "ios_packaging_justified": False,
            "recommended_next_step": "Ask FeOs maintainers or the literature owner for a pinned openly redistributable PC-SAFT CO2/N2 binary interaction parameter set before any further FeOs benchmark work.",
        },
    }


def normalized_json(report: dict[str, object]) -> str:
    return json.dumps(report, indent=2, sort_keys=True, allow_nan=False) + "\n"


def write_report(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(normalized_json(generate_report()), encoding="utf-8")


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("Documentation/Feasibility/FeOsComparisonResults.json"),
    )
    args = parser.parse_args(argv)
    write_report(args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
