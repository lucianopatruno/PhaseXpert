#!/usr/bin/env python3
"""Deterministic CoolProp 8 backend feasibility runner and result normalizer."""

from __future__ import annotations

import argparse
import json
import math
import os
import shutil
import statistics
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

COOLPROP_TAG = "v8.0.0"
COOLPROP_COMMIT = "ae81610e7d23efc57f9d051c8e70a4d66e87537f"
COOLPROP_TAG_OBJECT = "f39e663f5573f6a142c50d425f2a46b4c9dc5dcd"
BACKENDS = ["HEOS", "SRK", "PR"]
OPERATIONS = ["build_phase_envelope", "pt_flash", "critical_points"]
REFERENCE_CASES = {
    "pure-co2",
    "co2-97-n2-3",
    "co2-90-n2-10",
}
APPROPRIATE_TIMEOUT_SECONDS = 12.0
TEMPERATURE_MATCH_WINDOW_K = 1.0
GAP_THRESHOLD_K = 5.0
PRESSURE_GATES = {
    ("pure-co2", "bubble"): 0.010,
    ("pure-co2", "dew"): 0.010,
    ("co2-97-n2-3", "bubble"): 0.003,
    ("co2-97-n2-3", "dew"): 0.007,
    ("co2-90-n2-10", "bubble"): 0.022,
    ("co2-90-n2-10", "dew"): 0.015,
}
MAIN_GATE_CASES = ["pure-co2", "co2-97-n2-3", "co2-90-n2-10"]


def valid_case_ids() -> list[str]:
    return [
        "pure-co2",
        "co2-97-n2-3",
        "co2-90-n2-10",
        "co2-99999ppm-n2-1ppm",
        "co2-999-n2-001",
        "co2-96-n2-2-o2-1-ar-05-ch4-05",
        "co2-95-n2-3-ar-1-ch4-05-h2-05",
        "co2-90-n2-4-o2-2-ar-2-ch4-1-h2-1",
    ]


def invalid_case_ids() -> list[str]:
    return [
        "invalid-nonnormalized",
        "invalid-negative",
        "invalid-nonfinite",
        "invalid-unsupported-component",
        "invalid-out-of-domain-impurity",
    ]


@dataclass(frozen=True)
class CommandResult:
    status: str
    stdout: str
    stderr: str
    elapsed_seconds: float
    returncode: int | None


def run_command(
    command: list[str],
    timeout_seconds: float | None = None,
    cwd: Path | None = None,
) -> CommandResult:
    start = time.monotonic()
    try:
        completed = subprocess.run(
            command,
            cwd=cwd,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout_seconds,
            check=False,
        )
        return CommandResult(
            status="returned",
            stdout=completed.stdout,
            stderr=completed.stderr,
            elapsed_seconds=time.monotonic() - start,
            returncode=completed.returncode,
        )
    except subprocess.TimeoutExpired as error:
        return CommandResult(
            status="timeout",
            stdout=error.stdout or "",
            stderr=error.stderr or "",
            elapsed_seconds=time.monotonic() - start,
            returncode=None,
        )


def build_executable(repo_root: Path, work_root: Path) -> Path:
    source_root = work_root / "CoolProp"
    build_root = work_root / "build"
    executable = build_root / "coolprop8_backend_benchmark"
    harness_source = repo_root / "Scripts" / "CoolProp8BackendBenchmark.cpp"
    if executable.exists() and executable.stat().st_mtime >= harness_source.stat().st_mtime:
        return executable
    work_root.mkdir(parents=True, exist_ok=True)
    if not (source_root / ".git").exists():
        subprocess.run(
            [
                "git",
                "clone",
                "--branch",
                COOLPROP_TAG,
                "--depth",
                "1",
                "--recurse-submodules",
                "--shallow-submodules",
                "https://github.com/CoolProp/CoolProp.git",
                str(source_root),
            ],
            check=True,
        )
    actual_commit = subprocess.check_output(
        ["git", "-C", str(source_root), "rev-parse", "HEAD"],
        text=True,
    ).strip()
    if actual_commit != COOLPROP_COMMIT:
        raise RuntimeError(
            f"CoolProp source mismatch: expected {COOLPROP_COMMIT}, got {actual_commit}"
        )
    cmake_args = [
        "cmake",
        "-S",
        str(source_root),
        "-B",
        str(build_root),
        "-G",
        "Unix Makefiles",
        "-DCOOLPROP_STATIC_LIBRARY=ON",
        "-DCOOLPROP_SHARED_LIBRARY=OFF",
        "-DCOOLPROP_EXTERNC_LIBRARY=OFF",
        "-DCOOLPROP_LIBRARY_NAME=CoolProp",
        "-DBUILD_TESTING=OFF",
        "-DCMAKE_BUILD_TYPE=Release",
    ]
    subprocess.run(cmake_args, check=True)
    subprocess.run(
        ["cmake", "--build", str(build_root), "--config", "Release", "--target", "CoolProp"],
        check=True,
    )
    library = next(build_root.rglob("libCoolProp.a"), None)
    if library is None:
        raise RuntimeError("CoolProp static library was not produced.")
    dependency_includes = [
        build_root / "_deps" / "fmt-src" / "include",
        build_root / "_deps" / "eigen-src",
        build_root / "_deps" / "msgpack-c-src" / "include",
        build_root / "_deps" / "nlohmann_json-src" / "include",
        build_root / "_deps" / "valijson-src" / "include",
        build_root / "_deps" / "boost_headers-src",
        build_root / "_deps" / "multicomplex-src" / "multicomplex" / "include",
    ]
    compile_command = [
        "clang++",
        "-std=c++17",
        "-O2",
        "-I",
        str(source_root / "include"),
    ]
    for include_path in dependency_includes:
        compile_command.extend(["-I", str(include_path)])
    compile_command.extend(
        [
            str(harness_source),
            str(library),
            "-lc++",
            "-o",
            str(executable),
        ]
    )
    subprocess.run(compile_command, check=True)
    return executable


def load_reference(repo_root: Path) -> dict[str, Any]:
    path = repo_root / "Documentation" / "Feasibility" / "LocalPhaseDiagramNeqSimReferenceDataset.json"
    with path.open() as handle:
        data = json.load(handle)
    return {
        case["id"]: case
        for case in data["phase_envelope_cases"]
    }


def finite_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and math.isfinite(value)


def branch_points(points: list[dict[str, Any]], branch: str) -> list[dict[str, Any]]:
    accepted = [
        point
        for point in points
        if point.get("branch") == branch
        and finite_number(point.get("temperature_k"))
        and finite_number(point.get("pressure_pa"))
        and point["temperature_k"] > 0
        and point["pressure_pa"] > 0
    ]
    return sorted(accepted, key=lambda point: (point["temperature_k"], point["pressure_pa"]))


def gaps_for(points: list[dict[str, Any]]) -> list[dict[str, float]]:
    gaps: list[dict[str, float]] = []
    ordered = sorted(points, key=lambda point: point["temperature_k"])
    for previous, current in zip(ordered, ordered[1:]):
        delta = current["temperature_k"] - previous["temperature_k"]
        if delta > GAP_THRESHOLD_K:
            gaps.append(
                {
                    "from_temperature_k": round(previous["temperature_k"], 9),
                    "to_temperature_k": round(current["temperature_k"], 9),
                    "delta_k": round(delta, 9),
                }
            )
    return gaps


def percentile(values: list[float], fraction: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    index = max(0, min(len(ordered) - 1, math.ceil(fraction * len(ordered)) - 1))
    return ordered[index]


def statistics_for(errors: list[float]) -> dict[str, Any]:
    if not errors:
        return {
            "matched_count": 0,
            "mean_relative_pressure_error": None,
            "median_relative_pressure_error": None,
            "rms_relative_pressure_error": None,
            "p95_relative_pressure_error": None,
            "max_relative_pressure_error": None,
        }
    return {
        "matched_count": len(errors),
        "mean_relative_pressure_error": round(statistics.fmean(errors), 12),
        "median_relative_pressure_error": round(statistics.median(errors), 12),
        "rms_relative_pressure_error": round(math.sqrt(statistics.fmean([e * e for e in errors])), 12),
        "p95_relative_pressure_error": round(percentile(errors, 0.95), 12),
        "max_relative_pressure_error": round(max(errors), 12),
    }


def compare_branch(candidate: list[dict[str, Any]], reference: list[dict[str, Any]]) -> dict[str, Any]:
    errors: list[float] = []
    matches: list[dict[str, float]] = []
    for reference_point in reference:
        nearest = min(
            candidate,
            key=lambda point: abs(point["temperature_k"] - reference_point["temperature_k"]),
            default=None,
        )
        if nearest is None:
            continue
        delta_t = abs(nearest["temperature_k"] - reference_point["temperature_k"])
        if delta_t <= TEMPERATURE_MATCH_WINDOW_K:
            error = abs(nearest["pressure_pa"] - reference_point["pressure_pa"]) / reference_point["pressure_pa"]
            errors.append(error)
            matches.append(
                {
                    "reference_temperature_k": round(reference_point["temperature_k"], 9),
                    "candidate_temperature_k": round(nearest["temperature_k"], 9),
                    "relative_pressure_error": round(error, 12),
                }
            )
    result = statistics_for(errors)
    result["temperature_match_window_k"] = TEMPERATURE_MATCH_WINDOW_K
    result["matches"] = matches
    return result


def summarize_envelope(raw: dict[str, Any], reference_case: dict[str, Any] | None) -> dict[str, Any]:
    points = raw.get("points", []) if isinstance(raw.get("points"), list) else []
    summary: dict[str, Any] = {
        "status": raw.get("status"),
        "is_complete": raw.get("is_complete"),
        "is_closed": raw.get("is_closed"),
        "attempted_points": len(points),
        "accepted_points": 0,
        "branches": {},
        "termination_reason": raw.get("termination_reason"),
    }
    for branch in ["bubble", "dew", "critical"]:
        accepted = branch_points(points, branch)
        summary["accepted_points"] += len(accepted)
        branch_summary: dict[str, Any] = {
            "accepted_points": len(accepted),
            "temperature_range_k": [
                round(accepted[0]["temperature_k"], 9),
                round(accepted[-1]["temperature_k"], 9),
            ] if accepted else None,
            "pressure_range_pa": [
                round(min(point["pressure_pa"] for point in accepted), 9),
                round(max(point["pressure_pa"] for point in accepted), 9),
            ] if accepted else None,
            "gaps": gaps_for(accepted),
            "duplicates": duplicate_points(accepted),
            "last_accepted_point": accepted[-1] if accepted else None,
        }
        if reference_case and branch in {"bubble", "dew"}:
            reference_points = branch_points(reference_case["points"], branch)
            branch_summary["reference_points"] = len(reference_points)
            branch_summary["comparison"] = compare_branch(accepted, reference_points)
        summary["branches"][branch] = branch_summary
    return summary


def duplicate_points(points: list[dict[str, Any]]) -> list[dict[str, float]]:
    seen: set[tuple[float, float, str]] = set()
    duplicates: list[dict[str, float]] = []
    for point in points:
        key = (
            round(point["temperature_k"], 9),
            round(point["pressure_pa"], 6),
            str(point["branch"]),
        )
        if key in seen:
            duplicates.append(
                {
                    "temperature_k": key[0],
                    "pressure_pa": key[1],
                }
            )
        seen.add(key)
    return duplicates


def summarize_pt_flash(raw: dict[str, Any]) -> dict[str, Any]:
    samples = raw.get("samples", []) if isinstance(raw.get("samples"), list) else []
    converged = [sample for sample in samples if sample.get("status") == "converged"]
    failed = [sample for sample in samples if sample.get("status") == "failed"]
    phases = sorted({sample.get("phase") for sample in converged if sample.get("phase")})
    return {
        "status": raw.get("status"),
        "attempted_samples": len(samples),
        "converged_samples": len(converged),
        "failed_samples": len(failed),
        "phases": phases,
        "termination_reason": raw.get("termination_reason"),
        "stability_algorithm": raw.get("stability_algorithm"),
    }


def summarize_critical(raw: dict[str, Any]) -> dict[str, Any]:
    points = raw.get("critical_points", []) if isinstance(raw.get("critical_points"), list) else []
    finite = [
        point
        for point in points
        if finite_number(point.get("temperature_k"))
        and finite_number(point.get("pressure_pa"))
        and finite_number(point.get("density_molar"))
    ]
    return {
        "status": raw.get("status"),
        "critical_point_count": len(points),
        "finite_critical_point_count": len(finite),
        "stable_critical_point_count": len([point for point in finite if point.get("stable") is True]),
        "points": finite,
        "termination_reason": raw.get("termination_reason"),
    }


def normalized_timeout(operation: str, backend: str, case_id: str, elapsed_seconds: float) -> dict[str, Any]:
    return {
        "schema_version": "phasexpert-coolprop8-raw.v1",
        "coolprop_version": "8.0.0",
        "coolprop_gitrevision": COOLPROP_COMMIT,
        "backend": backend,
        "operation": operation,
        "case_id": case_id,
        "status": "timeout",
        "termination_reason": f"Process exceeded {APPROPRIATE_TIMEOUT_SECONDS:.1f} second deadline.",
        "elapsed_seconds": round(elapsed_seconds, 6),
    }


def run_operation(executable: Path, operation: str, backend: str, case_id: str) -> tuple[dict[str, Any], dict[str, Any]]:
    result = run_command(
        [str(executable), operation, backend, case_id],
        timeout_seconds=APPROPRIATE_TIMEOUT_SECONDS,
    )
    timing = {
        "operation": operation,
        "backend": backend,
        "case_id": case_id,
        "status": result.status,
        "elapsed_seconds": round(result.elapsed_seconds, 6),
        "returncode": result.returncode,
    }
    if result.status == "timeout":
        return normalized_timeout(operation, backend, case_id, result.elapsed_seconds), timing
    if result.returncode != 0:
        return {
            "schema_version": "phasexpert-coolprop8-raw.v1",
            "coolprop_version": "8.0.0",
            "coolprop_gitrevision": COOLPROP_COMMIT,
            "backend": backend,
            "operation": operation,
            "case_id": case_id,
            "status": "process_failed",
            "termination_reason": result.stderr.strip(),
        }, timing
    try:
        return json.loads(result.stdout), timing
    except json.JSONDecodeError as error:
        return {
            "schema_version": "phasexpert-coolprop8-raw.v1",
            "coolprop_version": "8.0.0",
            "coolprop_gitrevision": COOLPROP_COMMIT,
            "backend": backend,
            "operation": operation,
            "case_id": case_id,
            "status": "malformed_json",
            "termination_reason": str(error),
        }, timing


def gate_decision(
    envelopes: dict[str, dict[str, Any]],
    critical_points: dict[str, dict[str, Any]],
) -> dict[str, Any]:
    backend_results: dict[str, Any] = {}
    for backend in BACKENDS:
        failures: list[str] = []
        for case_id in MAIN_GATE_CASES:
            summary = envelopes[f"{backend}:{case_id}"]
            if summary["status"] != "returned":
                failures.append(f"{case_id}: envelope did not return ({summary['status']})")
                continue
            for branch in ["bubble", "dew"]:
                branch_summary = summary["branches"][branch]
                if branch_summary["accepted_points"] < 2:
                    failures.append(f"{case_id} {branch}: fewer than two accepted points")
                if branch_summary["gaps"]:
                    failures.append(f"{case_id} {branch}: discontinuous accepted branch")
                comparison = branch_summary.get("comparison", {})
                max_error = comparison.get("max_relative_pressure_error")
                threshold = PRESSURE_GATES[(case_id, branch)]
                if max_error is None or max_error > threshold:
                    failures.append(
                        f"{case_id} {branch}: max pressure error {max_error} exceeds {threshold}"
                    )
        pure_endpoint = endpoint_gap_k(
            envelopes[f"{backend}:pure-co2"],
            critical_points.get(f"{backend}:pure-co2"),
        )
        low_9010_bubble = lowest_branch_temperature_k(
            envelopes[f"{backend}:co2-90-n2-10"],
            "bubble",
        )
        if pure_endpoint is None or pure_endpoint >= 14.096:
            failures.append(f"pure-co2 endpoint gap {pure_endpoint} K does not improve 14.096 K")
        if low_9010_bubble is None or low_9010_bubble >= 139.987:
            failures.append(
                f"90/10 lowest continuous bubble temperature {low_9010_bubble} K does not improve 139.987 K"
            )
        backend_results[backend] = {
            "passed": not failures,
            "failures": failures,
            "pure_co2_endpoint_gap_k": pure_endpoint,
            "lowest_continuous_9010_bubble_temperature_k": low_9010_bubble,
        }
    return {
        "passed": any(result["passed"] for result in backend_results.values()),
        "backend_results": backend_results,
        "ios_packaging_justified": any(result["passed"] for result in backend_results.values()),
    }


def endpoint_gap_k(
    summary: dict[str, Any],
    critical_summary: dict[str, Any] | None = None,
) -> float | None:
    bubble = summary["branches"]["bubble"]
    dew = summary["branches"]["dew"]
    ranges = [
        value
        for value in [bubble.get("temperature_range_k"), dew.get("temperature_range_k")]
        if value
    ]
    if not ranges:
        return None
    high = max(value[1] for value in ranges)
    critical_temperatures: list[float] = []
    if critical_summary:
        critical_temperatures = [
            point["temperature_k"]
            for point in critical_summary.get("points", [])
            if point.get("stable") is True and finite_number(point.get("temperature_k"))
        ]
    if not critical_temperatures:
        critical_range = summary["branches"]["critical"].get("temperature_range_k")
        if critical_range:
            critical_temperatures = [critical_range[-1]]
    if not critical_temperatures:
        return None
    return round(abs(max(critical_temperatures) - high), 9)


def lowest_branch_temperature_k(summary: dict[str, Any], branch: str) -> float | None:
    temperature_range = summary["branches"][branch].get("temperature_range_k")
    if not temperature_range:
        return None
    return temperature_range[0]


def run_benchmark(repo_root: Path, output: Path, timing_output: Path, work_root: Path) -> dict[str, Any]:
    executable = build_executable(repo_root, work_root)
    references = load_reference(repo_root)
    raw_results: list[dict[str, Any]] = []
    timings: list[dict[str, Any]] = []
    case_ids = valid_case_ids() + invalid_case_ids()
    for backend in BACKENDS:
        for case_id in case_ids:
            for operation in OPERATIONS:
                raw, timing = run_operation(executable, operation, backend, case_id)
                raw_results.append(raw)
                timings.append(timing)
    envelopes: dict[str, dict[str, Any]] = {}
    critical_points: dict[str, dict[str, Any]] = {}
    operation_summaries: list[dict[str, Any]] = []
    for raw in raw_results:
        reference = references.get(raw["case_id"])
        if raw["operation"] == "build_phase_envelope":
            summary = summarize_envelope(raw, reference)
            envelopes[f"{raw['backend']}:{raw['case_id']}"] = summary
        elif raw["operation"] == "pt_flash":
            summary = summarize_pt_flash(raw)
        else:
            summary = summarize_critical(raw)
            critical_points[f"{raw['backend']}:{raw['case_id']}"] = summary
        operation_summaries.append(
            {
                "backend": raw["backend"],
                "case_id": raw["case_id"],
                "operation": raw["operation"],
                "summary": summary,
            }
        )
    report = {
        "schema_version": "phasexpert-coolprop8-comparison.v1",
        "coolprop": {
            "tag": COOLPROP_TAG,
            "tag_object": COOLPROP_TAG_OBJECT,
            "commit": COOLPROP_COMMIT,
            "license": "MIT",
        },
        "bounded_execution": {
            "operation_process_timeout_seconds": APPROPRIATE_TIMEOUT_SECONDS,
            "noninterruptible_library_call_strategy": "Each CoolProp operation runs in a separate macOS process; timeout terminates the process rather than pretending cooperative cancellation reached inside CoolProp.",
            "cooperative_cancellation_limitation": "The C++ CoolProp API does not expose a cancellation hook inside build_phase_envelope, PT flash, or all_critical_points.",
        },
        "reference": {
            "dataset": "Documentation/Feasibility/LocalPhaseDiagramNeqSimReferenceDataset.json",
            "available_phase_envelope_cases": sorted(references.keys()),
            "parity_only_not_experimental_validation": True,
        },
        "operation_summaries": sorted(
            operation_summaries,
            key=lambda item: (item["backend"], item["case_id"], item["operation"]),
        ),
        "scientific_gate": gate_decision(envelopes, critical_points),
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    timing_output.write_text(json.dumps({"timings": timings}, indent=2, sort_keys=True) + "\n")
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("Documentation/Feasibility/CoolProp8ComparisonResults.json"),
    )
    parser.add_argument(
        "--timing-output",
        type=Path,
        default=Path("/tmp/phasexpert-coolprop8-timing-results.json"),
    )
    parser.add_argument(
        "--work-root",
        type=Path,
        default=Path(os.environ.get("PHASEXPERT_COOLPROP8_WORK_ROOT", "/tmp/phasexpert-coolprop8-benchmark")),
    )
    args = parser.parse_args()
    repo_root = args.repo_root.resolve()
    run_benchmark(repo_root, repo_root / args.output, args.timing_output, args.work_root)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
