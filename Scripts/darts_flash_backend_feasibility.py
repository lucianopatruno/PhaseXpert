#!/usr/bin/env python3
"""Generate the deterministic DARTS-flash feasibility report."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


CORE_CASES = [
    ("pure_co2", {"CO2": 1.0}),
    ("co2_n2_97_3", {"CO2": 0.97, "N2": 0.03}),
    ("co2_n2_90_10", {"CO2": 0.90, "N2": 0.10}),
]

BRANCHES = ("bubble", "dew")

PHASEXPERT_COMPONENTS = {
    "CO2": {"supported": True, "source": "dartsflash/components.py"},
    "N2": {"supported": True, "source": "dartsflash/components.py"},
    "O2": {"supported": False, "source": "not present in bundled component table"},
    "Ar": {"supported": False, "source": "not present in bundled component table"},
    "H2": {"supported": True, "source": "dartsflash/components.py"},
    "CH4": {"supported": True, "source": "DARTS component identifier C1"},
    "CO": {"supported": False, "source": "not present in bundled component table"},
    "H2S": {"supported": True, "source": "dartsflash/components.py"},
    "H2O": {"supported": True, "source": "dartsflash/components.py"},
}

CORE_RESULTS = [
    {
        "case": case_id,
        "composition": composition,
        "branches": [
            {
                "branch": branch,
                "attempted_points": 0,
                "converged_points": 0,
                "accepted_points": 0,
                "rejected_points": 0,
                "temperature_range_K": None,
                "pressure_range_bar": None,
                "continuous_intervals": [],
                "gaps": [],
                "lowest_accepted_temperature_K": None,
                "lowest_continuous_temperature_K": None,
                "termination_reason": (
                    "not_run: no public fixed-composition PT bubble/dew envelope API was found, "
                    "and constructing boundaries from PT flash grids would require PhaseXpert-owned "
                    "bracketing, phase classification, and continuation"
                ),
                "relative_pressure_error": {
                    "mean": None,
                    "median": None,
                    "rms": None,
                    "p95": None,
                    "max": None,
                },
                "phase_distinction": None,
                "equilibrium_residual": None,
                "critical_region": "not evaluated",
            }
            for branch in BRANCHES
        ],
    }
    for case_id, composition in CORE_CASES
]


def deterministic_report() -> dict[str, Any]:
    return {
        "schema_version": 1,
        "candidate": "DARTS-flash",
        "primary_classification": "DARTS-flash requires excessive PhaseXpert-owned solver development",
        "accepted_main_base": "f75052489baf8efb798fffcb77137b730d4ceaa4",
        "pinned_dependency": {
            "repository": "https://gitlab.com/open-darts/darts-flash.git",
            "release": "v0.13.0",
            "commit": "acf1e12db4b82c779462a81d911ead0e254b963b",
            "license": "Apache-2.0",
            "submodules": [
                {
                    "name": "Eigen",
                    "url": "https://gitlab.com/libeigen/eigen.git",
                    "commit": "e7248b26a1ed53fa030c5c459f7ea095dfd276ac",
                    "license": "MPL-2.0 for Eigen project; redistribution review required before bundling",
                },
                {
                    "name": "pybind11",
                    "url": "https://github.com/pybind/pybind11.git",
                    "commit": "f5fbe867d2d26e4a0a9177a51f6e568868ad3dc8",
                    "license": "BSD-style pybind11 license; configure-time dependency in upstream CMake",
                },
            ],
        },
        "native_build_probe": {
            "ran": True,
            "result": "passed",
            "compiler": "AppleClang 21.0.0.21000101",
            "cmake": "4.4.2",
            "standard": "C++17 project, cxx_std_11 target compile feature in upstream interface target",
            "configure_time_dependency": "Python 3.12 development module found by upstream CMake because pybind11 is always imported",
            "archives": [
                {"path": "cpp/libdarts-flash.a", "size": "1.4M"},
                {"path": "cpp/libdarts-eos.a", "size": "2.1M"},
                {"path": "cpp/libglobal.a", "size": "368K"},
            ],
            "warnings": [
                "CMake policy CMP0152 warning in thirdparty/thirdparty.cmake",
                "author warning for missing default thirdparty/install Eigen path before system Eigen was found",
            ],
        },
        "api_findings": {
            "pt_flash": True,
            "stability_analysis": True,
            "phase_split": True,
            "phase_properties": True,
            "fugacity_properties": True,
            "critical_point": "CubicEoS exposes mechanical critical point methods, but no accepted fixed-composition PT envelope benchmark used them",
            "phase_boundary": "Flash::locate_phase_boundary exists, but requires two bracketing FlashResults states and is not a turnkey PT envelope tracer",
            "fixed_composition_pt_bubble_dew_envelope": False,
            "cancellation": "no native cancellation hook found; killable subprocess isolation would be required for bounded app integration",
        },
        "model_and_parameter_findings": {
            "candidate_model": "DARTS-flash cubic Helmholtz-form PR/SRK implementation using critical properties, acentric factors, and kij table",
            "component_support": PHASEXPERT_COMPONENTS,
            "co2_n2_kij": {
                "value": -0.0462,
                "location": "dartsflash/components.py",
                "model": "cubic EOS table used by PR/SRK examples",
                "primary_source": None,
                "doi": None,
                "licence": "repository Apache-2.0, but scientific provenance for this pair is not established",
                "usable_for_phasexpert_acceptance": False,
            },
            "missing_or_blocking_components": ["O2", "Ar", "CO"],
            "scientific_overlap_with_rejected_routes": "The usable native model family is cubic PR/SRK-like and does not provide evidence of improved CO2/N2 envelope coverage over PR #28 or PR #29.",
        },
        "benchmark": {
            "actual_native_benchmark_ran": False,
            "reason_not_run": (
                "A continuous fixed-composition PT bubble/dew benchmark would require a new PhaseXpert-owned "
                "bracketing, continuation, gap detection, and branch classification solver around DARTS-flash PT flashes. "
                "That is a stop condition for this milestone."
            ),
            "core_results": CORE_RESULTS,
            "multicomponent_results": {
                "ran": False,
                "reason": "blocked by absent envelope API, missing PhaseXpert components O2/Ar/CO, and unproven parameter provenance",
            },
            "pure_co2_endpoint_gap_K": None,
            "lowest_continuous_90_10_bubble_temperature_K": None,
            "timing": {
                "configure_and_build_probe_wall_time_s": 49.2,
                "scientific_benchmark_wall_time_s": 0.0,
            },
            "memory": {
                "peak_memory": None,
                "measurement": "not measured for benchmark because benchmark did not run",
            },
            "determinism": {
                "normalized_json_byte_identical": True,
                "benchmark_byte_identical": None,
            },
            "timeouts_and_cancellation": {
                "timeout_paths_exercised": False,
                "cooperative_cancellation": "not available through inspected native API",
                "subprocess_termination": "documented as required for any future benchmark, not exercised",
            },
        },
        "comparison": {
            "neqsim_fixtures": "not compared numerically because no DARTS-flash boundary points were accepted",
            "pr_28_native_srk": "DARTS-flash would rely on the same rejected cubic-EOS model family unless a different validated model and envelope API are established",
            "pr_29_coolprop8": "DARTS-flash did not provide accepted HEOS/SRK/PR-style boundary results to improve on the failed CoolProp 8 gate",
            "pr_30_teqp": "Unlike teqp, DARTS-flash compiled natively on macOS, but the scientific envelope gate remains blocked",
        },
        "apple_gate": {
            "reached": False,
            "reason": "desktop scientific gate did not pass",
            "targets": {
                "aarch64-apple-ios": "not attempted",
                "aarch64-apple-ios-sim": "not attempted",
                "x86_64-apple-ios": "not attempted",
            },
        },
    }


def write_report(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(deterministic_report(), indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("Documentation/Feasibility/DartsFlashComparisonResults.json"))
    args = parser.parse_args()
    write_report(args.output)


if __name__ == "__main__":
    main()
