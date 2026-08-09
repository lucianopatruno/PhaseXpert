#!/usr/bin/env python3
"""Offline validation-report generator for PhaseXpert calculation claims.

The runner intentionally does not call CoolProp or any network service. It
freezes reference provenance and acceptance criteria, verifies fixture
completeness, and records which scientific gates can and cannot yet be claimed
from committed evidence.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = ROOT / "Documentation" / "Validation" / "CalculationReferenceManifest.json"
DEFAULT_RESULTS = ROOT / "Documentation" / "Validation" / "CalculationValidationResults.json"


def canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False) + "\n"


def checksum(value: Any) -> str:
    return hashlib.sha256(canonical(value).encode("utf-8")).hexdigest()


def relative_tolerance_density(point: dict[str, Any]) -> float:
    absolute = point["expanded_uncertainty_kg_m3"] + 0.001 * point["density_kg_m3"]
    return absolute / point["density_kg_m3"]


def relative_tolerance_viscosity(point: dict[str, Any]) -> float:
    source = point["reference_id"]
    measured = point["viscosity_pa_s"]
    uncertainty = point["uncertainty_pa_s"]
    if source == "schaefer-2015-pure-co2-viscosity":
        absolute = max(uncertainty, 0.005 * measured)
    else:
        absolute = max(2 * uncertainty, 0.04 * measured)
    return absolute / measured


def count_by_region(points: list[dict[str, Any]]) -> dict[str, int]:
    counts: dict[str, int] = {}
    for point in points:
        region = point["region"]
        counts[region] = counts.get(region, 0) + 1
    return dict(sorted(counts.items()))


def validate_manifest(manifest: dict[str, Any]) -> list[str]:
    failures: list[str] = []
    references = {item["id"]: item for item in manifest["references"]}
    for section, points in manifest["fixtures"].items():
        for index, point in enumerate(points):
            reference_id = point.get("reference_id")
            if reference_id not in references:
                failures.append(f"{section}[{index}] has unknown reference_id {reference_id!r}")
            for key, value in point.items():
                if isinstance(value, float) and not (value == value and abs(value) != float("inf")):
                    failures.append(f"{section}[{index}].{key} is non-finite")
    if len(manifest["fixtures"]["co2_n2_density"]) == 0:
        failures.append("co2_n2_density has no committed traceable reference points")
    return failures


def build_report(manifest: dict[str, Any]) -> dict[str, Any]:
    density = manifest["fixtures"]["pure_co2_density"]
    viscosity = manifest["fixtures"]["pure_co2_viscosity"]
    critical = manifest["fixtures"]["critical_points"]
    co2_n2_density = manifest["fixtures"]["co2_n2_density"]
    manifest_failures = validate_manifest(manifest)
    pure_density_tolerances = [relative_tolerance_density(point) for point in density]
    pure_viscosity_tolerances = [relative_tolerance_viscosity(point) for point in viscosity]
    gates = {
        "pure_co2_density": {
            "status": "reference_protocol_frozen",
            "reference_points": len(density),
            "regions": count_by_region(density),
            "maximum_allowed_relative_deviation": max(pure_density_tolerances),
            "runtime_observation_required": True
        },
        "pure_co2_viscosity": {
            "status": "reference_protocol_frozen",
            "reference_points": len(viscosity),
            "regions": count_by_region(viscosity),
            "maximum_allowed_relative_deviation": max(pure_viscosity_tolerances),
            "runtime_observation_required": True
        },
        "pure_co2_critical_point": {
            "status": "reference_protocol_frozen",
            "reference_points": len(critical),
            "maximum_temperature_deviation_k": 0.01,
            "maximum_relative_pressure_deviation": 0.0002,
            "runtime_observation_required": True
        },
        "pure_co2_saturation_pressure": {
            "status": "blocked",
            "reference_points": 0,
            "reason": "No committed independent saturation-pressure fixture with redistribution review."
        },
        "co2_n2_density": {
            "status": "blocked",
            "reference_points": len(co2_n2_density),
            "reason": "Exact tabulated experimental values, composition basis, units, uncertainty and redistribution terms are not committed."
        },
        "derived_properties": {
            "status": "validated_by_formula_tests",
            "reference_points": 0,
            "basis": "Transparent equations M=sum(x_i M_i), v=1/rho, Z=pM/(rhoRT) with NIST molar masses and CODATA R."
        },
        "unit_conversions": {
            "status": "validated_by_unit_tests",
            "reference_points": 0,
            "basis": "Deterministic exact conversions in EngineeringUnits tests."
        }
    }
    return {
        "schema_version": "phasexpert-calculation-validation-results.v1",
        "manifest_checksum_sha256": checksum(manifest),
        "overall_scientific_gate": "not_passed",
        "reason": "Pure-CO2 density and viscosity reference protocols are frozen, but runtime observations are iOS-native tests; CO2-N2 density and pure-CO2 saturation-pressure reference fixtures remain uncommitted.",
        "manifest_failures": manifest_failures,
        "validated_range_matrix": {
            "pure_co2_density": "supported; preliminary until native runtime deviations are recorded in this report",
            "pure_co2_viscosity": "supported; preliminary until native runtime deviations are recorded in this report",
            "pure_co2_phase_identification": "supported; preliminary; no independent phase-boundary classification fixture committed",
            "pure_co2_saturation_boundary": "supported; preliminary; critical point fixture recorded but saturation-pressure fixture blocked",
            "co2_n2_density": "supported; preliminary; independent density fixture blocked",
            "co2_n2_viscosity": "unavailable",
            "multicomponent_phase_diagrams": "unavailable"
        },
        "gates": gates,
        "acceptance_protocol_frozen": True,
        "ordinary_build_requires_network": False
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--output", type=Path, default=DEFAULT_RESULTS)
    parser.add_argument("--allow-incomplete", action="store_true")
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    report = build_report(manifest)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True, allow_nan=False) + "\n", encoding="utf-8")
    if report["manifest_failures"] and not args.allow_incomplete:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
