#!/usr/bin/env python3
"""Offline validation-report generator for PhaseXpert calculation claims.

The runner intentionally does not call CoolProp or any network service. It
freezes reference provenance and acceptance criteria, verifies fixture
completeness, consumes native production-path observations when supplied, and
records which scientific gates can and cannot yet be claimed from committed
evidence.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = ROOT / "Documentation" / "Validation" / "CalculationReferenceManifest.json"
DEFAULT_RESULTS = ROOT / "Documentation" / "Validation" / "CalculationValidationResults.json"
REQUIRED_GATE_STATUSES = {"blocked", "failed", "runtime_observation_missing"}


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


def absolute_tolerance(gate: str, point: dict[str, Any]) -> float:
    if gate == "pure_co2_density":
        return (
            point["expanded_uncertainty_kg_m3"]
            + 0.001 * point["density_kg_m3"]
        )
    if gate == "pure_co2_viscosity":
        return relative_tolerance_viscosity(point) * point["viscosity_pa_s"]
    raise KeyError(f"No absolute tolerance rule for {gate}")


def reference_value(gate: str, point: dict[str, Any]) -> float:
    if gate == "pure_co2_density":
        return point["density_kg_m3"]
    if gate == "pure_co2_viscosity":
        return point["viscosity_pa_s"]
    raise KeyError(f"No reference value rule for {gate}")


def empty_metrics(expected_points: int) -> dict[str, Any]:
    return {
        "attempted": expected_points,
        "observed": 0,
        "passed": 0,
        "failed": expected_points,
        "failure_rate": 1.0 if expected_points else 0.0,
        "mean_absolute_relative_deviation": None,
        "bias_relative_deviation": None,
        "maximum_absolute_relative_deviation": None
    }


def summarize_observations(
    gate: str,
    fixtures: list[dict[str, Any]],
    observations: dict[str, Any] | None
) -> dict[str, Any]:
    if not observations:
        return {
            "status": "runtime_observation_missing",
            "reason": "No native production-path observation file was supplied.",
            "metrics": empty_metrics(len(fixtures))
        }

    by_key = {
        (point.get("fixture_section"), point.get("fixture_index")): point
        for point in observations.get("points", [])
        if point.get("gate") == gate
    }
    deviations: list[float] = []
    absolute_deviations: list[float] = []
    failures: list[str] = []
    passed = 0

    for index, fixture in enumerate(fixtures):
        observed = by_key.get((gate, index))
        if not observed:
            failures.append(f"{gate}[{index}] has no native production observation")
            continue
        if observed.get("status") != "calculated":
            failures.append(f"{gate}[{index}] status is {observed.get('status')!r}")
            continue
        value = observed.get("value")
        if not isinstance(value, (int, float)) or not math.isfinite(value):
            failures.append(f"{gate}[{index}] value is not finite")
            continue

        reference = reference_value(gate, fixture)
        absolute_deviation = float(value) - reference
        relative_deviation = absolute_deviation / reference
        deviations.append(relative_deviation)
        absolute_deviations.append(abs(absolute_deviation))
        if abs(absolute_deviation) <= absolute_tolerance(gate, fixture):
            passed += 1
        else:
            failures.append(
                f"{gate}[{index}] deviation exceeds frozen tolerance"
            )

    observed_count = len(deviations)
    failed = len(fixtures) - passed
    metrics = {
        "attempted": len(fixtures),
        "observed": observed_count,
        "passed": passed,
        "failed": failed,
        "failure_rate": failed / len(fixtures) if fixtures else 0.0,
        "mean_absolute_relative_deviation": (
            sum(abs(item) for item in deviations) / observed_count
            if observed_count else None
        ),
        "bias_relative_deviation": (
            sum(deviations) / observed_count if observed_count else None
        ),
        "maximum_absolute_relative_deviation": (
            max(abs(item) for item in deviations) if observed_count else None
        ),
        "maximum_absolute_deviation_si": (
            max(absolute_deviations) if absolute_deviations else None
        )
    }
    status = "passed" if not failures else "failed"
    return {
        "status": status,
        "failures": failures,
        "metrics": metrics
    }


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
    if len(manifest["fixtures"].get("pure_co2_saturation_pressure", [])) == 0:
        failures.append("pure_co2_saturation_pressure has no committed traceable reference points")
    return failures


def strict_blockers(report: dict[str, Any]) -> list[str]:
    blockers = list(report["manifest_failures"])
    for name, gate in report["gates"].items():
        if gate["status"] in REQUIRED_GATE_STATUSES:
            blockers.append(f"{name} gate is {gate['status']}")
    return sorted(set(blockers))


def build_report(
    manifest: dict[str, Any],
    observations: dict[str, Any] | None = None
) -> dict[str, Any]:
    density = manifest["fixtures"]["pure_co2_density"]
    viscosity = manifest["fixtures"]["pure_co2_viscosity"]
    critical = manifest["fixtures"]["critical_points"]
    saturation = manifest["fixtures"].get("pure_co2_saturation_pressure", [])
    co2_n2_density = manifest["fixtures"]["co2_n2_density"]
    manifest_failures = validate_manifest(manifest)
    pure_density_tolerances = [relative_tolerance_density(point) for point in density]
    pure_viscosity_tolerances = [relative_tolerance_viscosity(point) for point in viscosity]
    density_observations = summarize_observations("pure_co2_density", density, observations)
    viscosity_observations = summarize_observations("pure_co2_viscosity", viscosity, observations)
    observation_metadata = observations.get("metadata", {}) if observations else None
    gates = {
        "pure_co2_density": {
            "status": density_observations["status"],
            "reference_points": len(density),
            "regions": count_by_region(density),
            "maximum_allowed_relative_deviation": max(pure_density_tolerances),
            "runtime_observation_required": True,
            "runtime_observation_source": observation_metadata,
            "metrics": density_observations["metrics"],
            "failures": density_observations.get("failures", [])
        },
        "pure_co2_viscosity": {
            "status": viscosity_observations["status"],
            "reference_points": len(viscosity),
            "regions": count_by_region(viscosity),
            "maximum_allowed_relative_deviation": max(pure_viscosity_tolerances),
            "runtime_observation_required": True,
            "runtime_observation_source": observation_metadata,
            "metrics": viscosity_observations["metrics"],
            "failures": viscosity_observations.get("failures", [])
        },
        "pure_co2_critical_point": {
            "status": "runtime_observation_missing",
            "reference_points": len(critical),
            "maximum_temperature_deviation_k": 0.01,
            "maximum_relative_pressure_deviation": 0.0002,
            "runtime_observation_required": True,
            "reason": "The current native production observation file does not record critical-point values."
        },
        "pure_co2_saturation_pressure": {
            "status": "blocked",
            "reference_points": len(saturation),
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
    report = {
        "schema_version": "phasexpert-calculation-validation-results.v1",
        "manifest_checksum_sha256": checksum(manifest),
        "observation_checksum_sha256": checksum(observations) if observations else None,
        "overall_scientific_gate": "not_passed",
        "reason": "Selected pure-CO2 runtime deviations can be recorded when native observations are supplied, but the complete scientific gate remains blocked by missing critical-point observations plus CO2-N2 density and pure-CO2 saturation-pressure fixtures.",
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
    report["strict_blockers"] = strict_blockers(report)
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--output", type=Path, default=DEFAULT_RESULTS)
    parser.add_argument("--observations", type=Path)
    parser.add_argument("--allow-incomplete", action="store_true")
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    observations = None
    if args.observations:
        observations = json.loads(args.observations.read_text(encoding="utf-8"))
    report = build_report(manifest, observations=observations)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True, allow_nan=False) + "\n", encoding="utf-8")
    if report["strict_blockers"] and not args.allow_incomplete:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
