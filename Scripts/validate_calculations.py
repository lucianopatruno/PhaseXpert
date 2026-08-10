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
OBSERVATION_SCHEMA_VERSION = "phasexpert-production-observations.v2"
EXPECTED_PROVIDER_ID = "coolprop-heos"
REQUIRED_GATE_STATUSES = {"blocked", "failed", "runtime_observation_missing"}
REQUIRED_SCIENTIFIC_GATES = {
    "pure_co2_density",
    "pure_co2_viscosity",
    "pure_co2_critical_point",
    "pure_co2_saturation_pressure",
    "co2_n2_density"
}
GATE_CONTRACTS = {
    "pure_co2_density": {
        "fixture_section": "pure_co2_density",
        "property": "density",
        "unit": "kg/m³",
        "requires_input_state": True,
        "requires_pure_co2": True
    },
    "pure_co2_viscosity": {
        "fixture_section": "pure_co2_viscosity",
        "property": "dynamicViscosity",
        "unit": "Pa·s",
        "requires_input_state": True,
        "requires_pure_co2": True
    },
    "pure_co2_saturation_pressure": {
        "fixture_section": "pure_co2_saturation_pressure",
        "property": "saturationPressure",
        "unit": "Pa",
        "requires_input_state": True,
        "requires_pure_co2": True
    },
    "pure_co2_critical_point": {
        "fixture_section": "critical_points",
        "property": "criticalPoint",
        "unit": "K,Pa",
        "requires_input_state": False,
        "requires_pure_co2": True
    },
    "co2_n2_density": {
        "fixture_section": "co2_n2_density",
        "property": "density",
        "unit": "kg/m³",
        "requires_input_state": True,
        "requires_pure_co2": False
    }
}


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
    if gate == "co2_n2_density":
        return (
            point["expanded_uncertainty_kg_m3"]
            + 0.001 * point["density_kg_m3"]
        )
    if gate == "pure_co2_viscosity":
        return relative_tolerance_viscosity(point) * point["viscosity_pa_s"]
    if gate == "pure_co2_saturation_pressure":
        return (
            point.get("expanded_uncertainty_pa")
            or point.get("absolute_tolerance_pa")
            or 0.001 * point["pressure_pa"]
        )
    raise KeyError(f"No absolute tolerance rule for {gate}")


def reference_value(gate: str, point: dict[str, Any]) -> float:
    if gate == "pure_co2_density":
        return point["density_kg_m3"]
    if gate == "co2_n2_density":
        return point["density_kg_m3"]
    if gate == "pure_co2_viscosity":
        return point["viscosity_pa_s"]
    if gate == "pure_co2_saturation_pressure":
        return point["pressure_pa"]
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


def close_enough(left: Any, right: Any, rel_tol: float = 1e-12, abs_tol: float = 1e-9) -> bool:
    return (
        isinstance(left, (int, float))
        and isinstance(right, (int, float))
        and math.isfinite(float(left))
        and math.isfinite(float(right))
        and math.isclose(float(left), float(right), rel_tol=rel_tol, abs_tol=abs_tol)
    )


def is_pure_co2_composition(value: Any) -> bool:
    if not isinstance(value, list) or len(value) != 1:
        return False
    item = value[0]
    if not isinstance(item, dict):
        return False
    return item.get("component") == "co2" and close_enough(
        item.get("mole_fraction"),
        1.0,
        rel_tol=0,
        abs_tol=1e-12
    )


def expected_pressure(fixture: dict[str, Any]) -> float | None:
    pressure = fixture.get("pressure_pa")
    return float(pressure) if isinstance(pressure, (int, float)) else None


def observation_contract_failures(
    gate: str,
    fixtures: list[dict[str, Any]],
    observations: dict[str, Any]
) -> list[str]:
    contract = GATE_CONTRACTS[gate]
    failures: list[str] = []
    if observations.get("schema_version") != OBSERVATION_SCHEMA_VERSION:
        failures.append(
            f"observation schema_version must be {OBSERVATION_SCHEMA_VERSION!r}"
        )
    points = observations.get("points")
    if not isinstance(points, list):
        return failures + ["observations.points must be an array"]

    matching_points = [
        point for point in points
        if point.get("gate") == gate
        or point.get("fixture_section") == contract["fixture_section"]
    ]
    by_key: dict[tuple[str, int], dict[str, Any]] = {}
    duplicate_keys: set[tuple[str, int]] = set()
    for point in matching_points:
        key = (point.get("fixture_section"), point.get("fixture_index"))
        if key in by_key:
            duplicate_keys.add(key)
        elif isinstance(key[1], int):
            by_key[key] = point
    for section, index in sorted(duplicate_keys, key=lambda item: str(item)):
        failures.append(f"{section}[{index}] has duplicate observations")

    for index, fixture in enumerate(fixtures):
        key = (contract["fixture_section"], index)
        observed = by_key.get(key)
        if not observed:
            failures.append(f"{contract['fixture_section']}[{index}] has no native production observation")
            continue
        if observed.get("gate") != gate:
            failures.append(f"{contract['fixture_section']}[{index}] has gate {observed.get('gate')!r}")
        if observed.get("fixture_section") != contract["fixture_section"]:
            failures.append(f"{gate}[{index}] fixture_section is {observed.get('fixture_section')!r}")
        if observed.get("fixture_index") != index:
            failures.append(f"{gate}[{index}] fixture_index is {observed.get('fixture_index')!r}")
        if observed.get("reference_id") != fixture.get("reference_id"):
            failures.append(f"{gate}[{index}] reference_id does not match manifest")
        if observed.get("property") != contract["property"]:
            failures.append(f"{gate}[{index}] property is {observed.get('property')!r}")
        if observed.get("unit") != contract["unit"]:
            failures.append(f"{gate}[{index}] unit is {observed.get('unit')!r}")
        if observed.get("provider_id") != EXPECTED_PROVIDER_ID:
            failures.append(f"{gate}[{index}] provider_id is {observed.get('provider_id')!r}")
        for field in ("provider_name", "provider_version", "model_version"):
            if not isinstance(observed.get(field), str) or not observed[field]:
                failures.append(f"{gate}[{index}] {field} is missing")
        if observed.get("composition_basis") != "mole_fraction":
            failures.append(f"{gate}[{index}] composition_basis is {observed.get('composition_basis')!r}")
        if contract["requires_pure_co2"] and not is_pure_co2_composition(
            observed.get("normalized_composition")
        ):
            failures.append(f"{gate}[{index}] normalized_composition is not pure CO2")
        if contract["requires_input_state"]:
            if not close_enough(observed.get("input_temperature_k"), fixture.get("temperature_k")):
                failures.append(f"{gate}[{index}] input_temperature_k does not match fixture")
            pressure = expected_pressure(fixture)
            if pressure is not None and not close_enough(observed.get("input_pressure_pa"), pressure):
                failures.append(f"{gate}[{index}] input_pressure_pa does not match fixture")
        if observed.get("status") != "calculated":
            failures.append(f"{gate}[{index}] status is {observed.get('status')!r}")
        if gate == "pure_co2_critical_point":
            temperature = observed.get("critical_temperature_k")
            pressure = observed.get("critical_pressure_pa")
            if not isinstance(temperature, (int, float)) or not math.isfinite(float(temperature)):
                failures.append(f"{gate}[{index}] critical_temperature_k is not finite")
            if not isinstance(pressure, (int, float)) or not math.isfinite(float(pressure)) or float(pressure) <= 0:
                failures.append(f"{gate}[{index}] critical_pressure_pa is not finite and positive")
        else:
            value = observed.get("value")
            if not isinstance(value, (int, float)) or not math.isfinite(float(value)) or float(value) <= 0:
                failures.append(f"{gate}[{index}] value is not finite and positive")
    return failures


def summarize_observations(
    gate: str,
    fixtures: list[dict[str, Any]],
    observations: dict[str, Any] | None
) -> dict[str, Any]:
    if len(fixtures) == 0:
        return {
            "status": "blocked",
            "reason": "No committed traceable reference points.",
            "metrics": empty_metrics(0)
        }
    if not observations:
        return {
            "status": "runtime_observation_missing",
            "reason": "No native production-path observation file was supplied.",
            "metrics": empty_metrics(len(fixtures))
        }
    contract_failures = observation_contract_failures(gate, fixtures, observations)
    if contract_failures:
        return {
            "status": "failed",
            "failures": contract_failures,
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


def summarize_critical_observations(
    fixtures: list[dict[str, Any]],
    observations: dict[str, Any] | None
) -> dict[str, Any]:
    if len(fixtures) == 0:
        return {
            "status": "blocked",
            "reason": "No committed traceable critical-point reference.",
            "metrics": {
                "attempted": 0,
                "observed": 0,
                "passed": 0,
                "failed": 0,
                "failure_rate": 0.0,
                "maximum_temperature_deviation_k": None,
                "maximum_relative_pressure_deviation": None
            }
        }
    if not observations:
        return {
            "status": "runtime_observation_missing",
            "reason": "No native production-path critical-point observation file was supplied.",
            "metrics": {
                "attempted": len(fixtures),
                "observed": 0,
                "passed": 0,
                "failed": len(fixtures),
                "failure_rate": 1.0,
                "maximum_temperature_deviation_k": None,
                "maximum_relative_pressure_deviation": None
            }
        }
    contract_failures = observation_contract_failures(
        "pure_co2_critical_point",
        fixtures,
        observations
    )
    if contract_failures:
        return {
            "status": "failed",
            "failures": contract_failures,
            "metrics": {
                "attempted": len(fixtures),
                "observed": 0,
                "passed": 0,
                "failed": len(fixtures),
                "failure_rate": 1.0,
                "maximum_temperature_deviation_k": None,
                "maximum_relative_pressure_deviation": None
            }
        }

    by_key = {
        (point.get("fixture_section"), point.get("fixture_index")): point
        for point in observations.get("points", [])
        if point.get("gate") == "pure_co2_critical_point"
    }
    failures: list[str] = []
    temperature_deviations: list[float] = []
    pressure_deviations: list[float] = []
    passed = 0

    for index, fixture in enumerate(fixtures):
        observed = by_key.get(("critical_points", index))
        if not observed:
            failures.append(f"critical_points[{index}] has no native production observation")
            continue
        if observed.get("status") != "calculated":
            failures.append(f"critical_points[{index}] status is {observed.get('status')!r}")
            continue
        temperature = observed.get("critical_temperature_k")
        pressure = observed.get("critical_pressure_pa")
        if not isinstance(temperature, (int, float)) or not math.isfinite(temperature):
            failures.append(f"critical_points[{index}] critical_temperature_k is not finite")
            continue
        if not isinstance(pressure, (int, float)) or not math.isfinite(pressure) or pressure <= 0:
            failures.append(f"critical_points[{index}] critical_pressure_pa is not finite and positive")
            continue

        temperature_deviation = abs(float(temperature) - fixture["temperature_k"])
        pressure_relative_deviation = abs(float(pressure) - fixture["pressure_pa"]) / fixture["pressure_pa"]
        temperature_deviations.append(temperature_deviation)
        pressure_deviations.append(pressure_relative_deviation)
        if temperature_deviation <= 0.01 and pressure_relative_deviation <= 0.0002:
            passed += 1
        else:
            failures.append(f"critical_points[{index}] deviation exceeds frozen tolerance")

    failed = len(fixtures) - passed
    return {
        "status": "passed" if not failures else "failed",
        "failures": failures,
        "metrics": {
            "attempted": len(fixtures),
            "observed": len(temperature_deviations),
            "passed": passed,
            "failed": failed,
            "failure_rate": failed / len(fixtures),
            "maximum_temperature_deviation_k": max(temperature_deviations) if temperature_deviations else None,
            "maximum_relative_pressure_deviation": max(pressure_deviations) if pressure_deviations else None
        }
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
        if name in REQUIRED_SCIENTIFIC_GATES and gate["status"] in REQUIRED_GATE_STATUSES:
            blockers.append(f"{name} gate is {gate['status']}")
    return sorted(set(blockers))


def overall_status_and_reason(blockers: list[str]) -> tuple[str, str]:
    if not blockers:
        return (
            "passed",
            "Every required scientific gate passed with committed fixtures and supplied production observations."
        )
    return (
        "not_passed",
        "Required scientific gates are incomplete: " + "; ".join(blockers) + "."
    )


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
    critical_observations = summarize_critical_observations(critical, observations)
    saturation_observations = summarize_observations(
        "pure_co2_saturation_pressure",
        saturation,
        observations
    )
    co2_n2_density_observations = summarize_observations(
        "co2_n2_density",
        co2_n2_density,
        observations
    )
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
            "status": critical_observations["status"],
            "reference_points": len(critical),
            "maximum_temperature_deviation_k": 0.01,
            "maximum_relative_pressure_deviation": 0.0002,
            "runtime_observation_required": True,
            "runtime_observation_source": observation_metadata,
            "metrics": critical_observations["metrics"],
            "failures": critical_observations.get("failures", []),
            "reason": critical_observations.get("reason")
        },
        "pure_co2_saturation_pressure": {
            "status": saturation_observations["status"],
            "reference_points": len(saturation),
            "runtime_observation_required": True,
            "runtime_observation_source": observation_metadata,
            "metrics": saturation_observations["metrics"],
            "failures": saturation_observations.get("failures", []),
            "reason": "No committed independent saturation-pressure fixture with redistribution review."
                if len(saturation) == 0 else saturation_observations.get("reason")
        },
        "co2_n2_density": {
            "status": co2_n2_density_observations["status"],
            "reference_points": len(co2_n2_density),
            "runtime_observation_required": True,
            "runtime_observation_source": observation_metadata,
            "metrics": co2_n2_density_observations["metrics"],
            "failures": co2_n2_density_observations.get("failures", []),
            "reason": "Exact tabulated experimental values, composition basis, units, uncertainty and redistribution terms are not committed."
                if len(co2_n2_density) == 0 else co2_n2_density_observations.get("reason")
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
    blockers = sorted(set(
        list(manifest_failures)
        + [
            f"{name} gate is {gate['status']}"
            for name, gate in gates.items()
            if name in REQUIRED_SCIENTIFIC_GATES
            and gate["status"] in REQUIRED_GATE_STATUSES
        ]
    ))
    overall_gate, reason = overall_status_and_reason(blockers)
    report = {
        "schema_version": "phasexpert-calculation-validation-results.v1",
        "manifest_checksum_sha256": checksum(manifest),
        "observation_checksum_sha256": checksum(observations) if observations else None,
        "overall_scientific_gate": overall_gate,
        "reason": reason,
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
    report["strict_blockers"] = blockers
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
