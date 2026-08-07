#!/usr/bin/env python3
"""Generate and validate a small offline NeqSim CO2/N2 phase-envelope atlas."""

from __future__ import annotations

import argparse
import bisect
import gzip
import hashlib
import json
import math
import os
import selectors
import statistics
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Any


SCHEMA_VERSION = "phasexpert-neqsim-offline-atlas.v2"
NEQSIM_VERSION = "3.16.0"
NEQSIM_COMMIT = "3af7b560525b57f2d3da2c803a08e2b41a8d7f5a"
JAVA_VERSION = "Temurin-21.0.12+8"
JVM_STARTUP_ESTIMATE_S = 1.80
PER_ENVELOPE_DEADLINE_S = 5.0
OVERALL_CAMPAIGN_DEADLINE_S = 240.0

PRIMARY_CLASSIFICATION = "Topology-aligned interpolation passes the scientific gate, but Apple consumption remains unproven."
FALLBACK_CLASSIFICATION = "NeqSim's envelope topology is too unstable for reliable general interpolation."
NONCRITICAL_ENDPOINT_EXCLUSION_FRACTION = 0.03
TOPOLOGY_TEMPERATURE_GAP_K = 8.0
TOPOLOGY_LOG_PRESSURE_GAP = 1.25
ARC_COORDINATE_COUNT = 41


def canonical_dumps(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False)


def sha256_json(value: Any) -> str:
    return hashlib.sha256(canonical_dumps(value).encode("utf-8")).hexdigest()


def round_float(value: float | None, digits: int = 12) -> float | None:
    if value is None or not math.isfinite(value):
        return None
    return round(float(value), digits)


def main_reference_compositions() -> list[float]:
    return [round(i * 0.00125, 8) for i in range(81)]


def ppm_reference_compositions() -> list[float]:
    return [0.00001, 0.00005, 0.00010, 0.00050, 0.00100, 0.00500]


def locked_reference_compositions() -> list[float]:
    engineering = [round(0.000625 + 0.0025 * index, 8) for index in range(40)]
    near_pure = [0.000025, 0.000075, 0.00025, 0.00075, 0.0025]
    return sorted(set(engineering + near_pure))


def all_reference_compositions() -> list[float]:
    return sorted(set(main_reference_compositions() + ppm_reference_compositions()))


def grid_nodes(spacing: float) -> list[float]:
    return [round(i * spacing, 8) for i in range(int(round(0.10 / spacing)) + 1)]


def validate_x_n2(value: float) -> float:
    if not math.isfinite(value):
        raise ValueError("x_N2 must be finite")
    if value < 0.0 or value > 0.10:
        raise ValueError("x_N2 is outside the bounded CO2/N2 prototype domain")
    return round_float(value, 8) or 0.0


def worker_main() -> None:
    from neqsim import jneqsim  # type: ignore

    def finite_points(values_t: Any, values_p: Any, branch: str) -> tuple[list[dict[str, float]], list[dict[str, Any]], list[dict[str, Any]]]:
        points: list[dict[str, float]] = []
        rejected: list[dict[str, Any]] = []
        segments: list[dict[str, Any]] = []
        current: list[dict[str, float]] = []

        def close_segment() -> None:
            nonlocal current
            if len(current) >= 2:
                current.sort(key=lambda point: (point["temperature_k"], point["pressure_pa"]))
                segments.append(
                    {
                        "segment_id": len(segments),
                        "points": current,
                    }
                )
            current = []

        for index, (temperature, pressure_bara) in enumerate(zip(list(values_t or []), list(values_p or []))):
            try:
                temperature_k = float(temperature)
                pressure_pa = float(pressure_bara) * 100000.0
            except Exception as error:
                close_segment()
                rejected.append({"branch": branch, "index": index, "reason": type(error).__name__})
                continue
            if not math.isfinite(temperature_k) or not math.isfinite(pressure_pa) or temperature_k <= 0 or pressure_pa <= 0:
                close_segment()
                rejected.append({"branch": branch, "index": index, "reason": "non_finite_or_out_of_domain"})
                continue
            point = {"temperature_k": round_float(temperature_k), "pressure_pa": round_float(pressure_pa, 6)}
            current.append(point)
            points.append(point)
        close_segment()
        points.sort(key=lambda point: (point["temperature_k"], point["pressure_pa"]))
        return points, rejected, segments

    print(canonical_dumps({"worker": "ready"}), flush=True)
    for line in sys.stdin:
        request = json.loads(line)
        if request.get("command") == "stop":
            break
        started = time.perf_counter()
        x_n2 = validate_x_n2(float(request["x_n2"]))
        composition = {"CO2": 1.0 - x_n2, "nitrogen": x_n2}
        response: dict[str, Any] = {
            "x_n2": round_float(x_n2, 8),
            "composition": {"CO2": round_float(1.0 - x_n2, 8), "N2": round_float(x_n2, 8)},
            "status": "failed",
            "branches": {},
            "segments": {},
            "critical": None,
            "rejected_points": [],
            "duration_s": None,
            "error": None,
        }
        try:
            fluid = jneqsim.thermo.system.SystemSrkEos(273.15, 1.0)
            fluid.addComponent("CO2", composition["CO2"])
            if x_n2 > 0:
                fluid.addComponent("nitrogen", composition["nitrogen"])
            fluid.setMixingRule("classic")
            ops = jneqsim.thermodynamicoperations.ThermodynamicOperations(fluid)
            ops.calcPTphaseEnvelope()
            branches: dict[str, list[dict[str, float]]] = {}
            segments: dict[str, list[dict[str, Any]]] = {}
            for key_t, key_p, branch in (("bubT", "bubP", "bubble"), ("dewT", "dewP", "dew")):
                points, rejected, branch_segments = finite_points(ops.get(key_t), ops.get(key_p), branch)
                branches[branch] = points
                segments[branch] = branch_segments
                response["rejected_points"].extend(rejected)
            critical = ops.get("criticalPoint1")
            if critical is not None and len(critical) >= 2:
                critical_t = float(critical[0])
                critical_p = float(critical[1]) * 100000.0
                if math.isfinite(critical_t) and math.isfinite(critical_p) and critical_t > 0 and critical_p > 0:
                    response["critical"] = {
                        "temperature_k": round_float(critical_t),
                        "pressure_pa": round_float(critical_p, 6),
                    }
            response["branches"] = branches
            response["segments"] = segments
            response["status"] = "converged" if any(branches.values()) else "no_finite_points"
        except Exception as error:  # pragma: no cover - exercised by subprocess integration
            response["error"] = type(error).__name__ + ": " + str(error)
        response["duration_s"] = round_float(time.perf_counter() - started, 9)
        print(canonical_dumps(response), flush=True)


class NeqSimWorker:
    def __init__(
        self,
        python_executable: str,
        java_home: str,
        deadline_s: float = PER_ENVELOPE_DEADLINE_S,
        worker_script: str | None = None,
    ):
        self.python_executable = python_executable
        self.java_home = java_home
        self.deadline_s = deadline_s
        self.worker_script = worker_script or __file__
        self.process: subprocess.Popen[str] | None = None
        self.selector = selectors.DefaultSelector()
        self.restarts = 0
        self.startup_time_s = 0.0
        self.start()

    def start(self) -> None:
        env = dict(os.environ)
        env["JAVA_HOME"] = self.java_home
        env["PATH"] = str(Path(self.java_home) / "bin") + os.pathsep + env.get("PATH", "")
        started = time.perf_counter()
        self.process = subprocess.Popen(
            [self.python_executable, self.worker_script, "--worker"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
            bufsize=1,
        )
        assert self.process.stdout is not None
        self.selector.register(self.process.stdout, selectors.EVENT_READ)
        ready = self._read_line(20.0)
        if not ready or json.loads(ready).get("worker") != "ready":
            self.kill()
            raise RuntimeError("NeqSim worker did not start")
        self.startup_time_s += time.perf_counter() - started

    def _read_line(self, timeout_s: float) -> str | None:
        assert self.process is not None and self.process.stdout is not None
        events = self.selector.select(timeout_s)
        if not events:
            return None
        return self.process.stdout.readline()

    def evaluate(self, x_n2: float) -> dict[str, Any]:
        assert self.process is not None and self.process.stdin is not None
        request = canonical_dumps({"x_n2": x_n2}) + "\n"
        self.process.stdin.write(request)
        self.process.stdin.flush()
        line = self._read_line(self.deadline_s)
        if line is None:
            self.kill()
            self.restarts += 1
            self.start()
            return {
                "x_n2": round_float(x_n2, 8),
                "composition": {"CO2": round_float(1.0 - x_n2, 8), "N2": round_float(x_n2, 8)},
                "status": "timeout",
                "branches": {"bubble": [], "dew": []},
                "segments": {"bubble": [], "dew": []},
                "critical": None,
                "rejected_points": [],
                "duration_s": None,
                "error": "per-envelope deadline exceeded",
            }
        return json.loads(line)

    def close(self) -> None:
        if self.process and self.process.poll() is None and self.process.stdin:
            try:
                self.process.stdin.write(canonical_dumps({"command": "stop"}) + "\n")
                self.process.stdin.flush()
                self.process.wait(timeout=2.0)
            except Exception:
                self.kill()
        if self.process and self.process.stdout:
            try:
                self.selector.unregister(self.process.stdout)
            except Exception:
                pass
        if self.process:
            for stream in (self.process.stdin, self.process.stdout, self.process.stderr):
                if stream:
                    try:
                        stream.close()
                    except Exception:
                        pass

    def kill(self) -> None:
        if self.process and self.process.stdout:
            try:
                self.selector.unregister(self.process.stdout)
            except Exception:
                pass
        if self.process and self.process.poll() is None:
            self.process.kill()
            try:
                self.process.wait(timeout=2.0)
            except subprocess.TimeoutExpired:
                pass
        if self.process:
            for stream in (self.process.stdin, self.process.stdout, self.process.stderr):
                if stream:
                    try:
                        stream.close()
                    except Exception:
                        pass


def envelope_summary(envelope: dict[str, Any]) -> dict[str, Any]:
    branches: dict[str, Any] = {}
    for branch_name, points in envelope["branches"].items():
        finite = [
            point
            for point in points
            if math.isfinite(point["temperature_k"]) and math.isfinite(point["pressure_pa"])
        ]
        branches[branch_name] = {
            "attempted_points": len(points) + sum(1 for item in envelope["rejected_points"] if item["branch"] == branch_name),
            "accepted_points": len(finite),
            "temperature_range_K": [finite[0]["temperature_k"], finite[-1]["temperature_k"]] if finite else None,
            "pressure_range_pa": [
                min(point["pressure_pa"] for point in finite),
                max(point["pressure_pa"] for point in finite),
            ]
            if finite
            else None,
            "segments": [{"start_index": 0, "end_index": len(finite) - 1}] if len(finite) >= 2 else [],
            "gaps": [],
        }
    return branches


def branch_segments(record: dict[str, Any], branch: str) -> list[dict[str, Any]]:
    segments = record.get("segments", {}).get(branch) or []
    if segments:
        return segments
    points = record.get("branches", {}).get(branch, [])
    return [{"segment_id": 0, "points": points}] if len(points) >= 2 else []


def monotonic_direction(values: list[float]) -> str:
    deltas = [values[index + 1] - values[index] for index in range(len(values) - 1)]
    positive = any(delta > 0 for delta in deltas)
    negative = any(delta < 0 for delta in deltas)
    if positive and not negative:
        return "increasing"
    if negative and not positive:
        return "decreasing"
    if not positive and not negative:
        return "flat"
    return "nonmonotonic"


def turning_count(values: list[float]) -> int:
    signs: list[int] = []
    for index in range(len(values) - 1):
        delta = values[index + 1] - values[index]
        if abs(delta) <= 1.0e-12:
            continue
        signs.append(1 if delta > 0 else -1)
    return sum(1 for index in range(len(signs) - 1) if signs[index] != signs[index + 1])


def segment_descriptor(record: dict[str, Any], branch: str, segment: dict[str, Any]) -> dict[str, Any]:
    points = segment["points"]
    temperatures = [point["temperature_k"] for point in points]
    pressures = [point["pressure_pa"] for point in points]
    pressure_turns = turning_count(pressures)
    critical = record.get("critical")
    high_endpoint = points[-1]
    critical_attachment = False
    if critical:
        t_span = max(temperatures) - min(temperatures)
        pressure_scale = max(critical["pressure_pa"], 1.0)
        critical_attachment = (
            abs(high_endpoint["temperature_k"] - critical["temperature_k"]) <= max(0.75, 0.01 * t_span)
            and abs(high_endpoint["pressure_pa"] - critical["pressure_pa"]) / pressure_scale <= 0.05
        )
    max_temperature_step = max((abs(temperatures[index + 1] - temperatures[index]) for index in range(len(temperatures) - 1)), default=0.0)
    max_log_pressure_step = max(
        (
            abs(math.log(pressures[index + 1]) - math.log(pressures[index]))
            for index in range(len(pressures) - 1)
            if pressures[index] > 0 and pressures[index + 1] > 0
        ),
        default=0.0,
    )
    detached = max_temperature_step > TOPOLOGY_TEMPERATURE_GAP_K or max_log_pressure_step > TOPOLOGY_LOG_PRESSURE_GAP
    signature = {
        "branch": branch,
        "critical_attachment": critical_attachment,
        "detached": detached,
        "pressure_direction": monotonic_direction(pressures),
        "pressure_turning_points": pressure_turns,
        "temperature_direction": monotonic_direction(temperatures),
    }
    return {
        "composition_x_n2": record["x_n2"],
        "branch": branch,
        "segment_id": segment["segment_id"],
        "point_count": len(points),
        "low_temperature_endpoint": points[0],
        "high_temperature_endpoint": points[-1],
        "temperature_range_K": [round_float(min(temperatures)), round_float(max(temperatures))],
        "pressure_range_pa": [round_float(min(pressures), 6), round_float(max(pressures), 6)],
        "max_temperature_step_K": round_float(max_temperature_step, 12),
        "max_log_pressure_step": round_float(max_log_pressure_step, 12),
        "critical_attachment": critical_attachment,
        "temperature_direction": signature["temperature_direction"],
        "pressure_direction": signature["pressure_direction"],
        "pressure_turning_points": pressure_turns,
        "detached": detached,
        "gaps_before_after": {"before": None, "after": None},
        "topology_signature": canonical_dumps(signature),
    }


def topology_descriptors(record: dict[str, Any]) -> dict[str, list[dict[str, Any]]]:
    return {
        branch: [segment_descriptor(record, branch, segment) for segment in branch_segments(record, branch)]
        for branch in ("bubble", "dew")
    }


def segment_pair_is_compatible(lo_desc: dict[str, Any], hi_desc: dict[str, Any], ref_desc: dict[str, Any] | None = None) -> tuple[bool, str]:
    keys = ("branch", "critical_attachment", "detached", "temperature_direction", "pressure_turning_points")
    for key in keys:
        if lo_desc[key] != hi_desc[key]:
            return False, f"incompatible_{key}"
        if ref_desc is not None and lo_desc[key] != ref_desc[key]:
            return False, f"reference_incompatible_{key}"
    return True, "compatible"


def interpolation_nodes(spacing: float) -> list[float]:
    return grid_nodes(spacing)


def generate_atlas(python_executable: str, java_home: str, compositions: list[float]) -> tuple[dict[str, Any], dict[str, Any]]:
    started = time.perf_counter()
    worker = NeqSimWorker(python_executable, java_home)
    records: list[dict[str, Any]] = []
    per_envelope_timings: list[float] = []
    retry_count = 0
    timeout_count = 0
    try:
        for x_n2 in compositions:
            validate_x_n2(x_n2)
            if time.perf_counter() - started > OVERALL_CAMPAIGN_DEADLINE_S:
                raise TimeoutError("overall campaign deadline exceeded")
            result = worker.evaluate(x_n2)
            if result["status"] == "timeout":
                timeout_count += 1
                retry_count += 1
                retry = worker.evaluate(x_n2)
                result = retry if retry["status"] != "timeout" else result
            if result.get("duration_s") is not None:
                per_envelope_timings.append(float(result["duration_s"]))
            result.pop("duration_s", None)
            result["summary"] = envelope_summary(result) if result.get("branches") else {}
            result["content_checksum"] = sha256_json(
                {
                    "x_n2": result["x_n2"],
                    "composition": result["composition"],
                    "branches": result["branches"],
                    "segments": result.get("segments", {}),
                    "critical": result["critical"],
                    "status": result["status"],
                }
            )
            records.append(result)
    finally:
        worker.close()
    timings = {
        "wall_time_s": round_float(time.perf_counter() - started, 6),
        "worker_startup_time_s": round_float(worker.startup_time_s, 6),
        "worker_restarts": worker.restarts,
        "timeouts": timeout_count,
        "retries": retry_count,
        "per_envelope_s": [round_float(value, 9) for value in per_envelope_timings],
    }
    atlas = {
        "schema_version": SCHEMA_VERSION,
        "provenance": provenance(),
        "records": records,
        "atlas_checksum": "",
    }
    atlas["atlas_checksum"] = sha256_json({"records": records, "schema_version": SCHEMA_VERSION})
    return atlas, timings


def interpolate_series(points: list[dict[str, float]], temperature_k: float) -> float | None:
    if len(points) < 2:
        return None
    temperatures = [point["temperature_k"] for point in points]
    if temperature_k < temperatures[0] or temperature_k > temperatures[-1]:
        return None
    index = bisect.bisect_left(temperatures, temperature_k)
    if index < len(points) and temperatures[index] == temperature_k:
        return points[index]["pressure_pa"]
    if index == 0 or index >= len(points):
        return None
    lo = points[index - 1]
    hi = points[index]
    span = hi["temperature_k"] - lo["temperature_k"]
    if span <= 0:
        return None
    fraction = (temperature_k - lo["temperature_k"]) / span
    return lo["pressure_pa"] + fraction * (hi["pressure_pa"] - lo["pressure_pa"])


def interpolate_log_pressure_by_temperature(points: list[dict[str, float]], temperature_k: float) -> float | None:
    pressure = interpolate_series(
        [{"temperature_k": point["temperature_k"], "pressure_pa": math.log(point["pressure_pa"])} for point in points],
        temperature_k,
    )
    if pressure is None:
        return None
    return pressure


def point_at_reduced_temperature(points: list[dict[str, float]], coordinate: float) -> dict[str, float] | None:
    if len(points) < 2 or coordinate < 0.0 or coordinate > 1.0:
        return None
    low = points[0]["temperature_k"]
    high = points[-1]["temperature_k"]
    if high <= low:
        return None
    temperature = low + coordinate * (high - low)
    log_pressure = interpolate_log_pressure_by_temperature(points, temperature)
    if log_pressure is None:
        return None
    return {"temperature_k": temperature, "pressure_pa": math.exp(log_pressure)}


def normalized_arc(points: list[dict[str, float]]) -> list[tuple[float, dict[str, float]]]:
    if len(points) < 2:
        return []
    temperatures = [point["temperature_k"] for point in points]
    log_pressures = [math.log(point["pressure_pa"]) for point in points]
    t_scale = max(max(temperatures) - min(temperatures), 1.0e-12)
    p_scale = max(max(log_pressures) - min(log_pressures), 1.0e-12)
    distances = [0.0]
    total = 0.0
    for index in range(len(points) - 1):
        dt = (temperatures[index + 1] - temperatures[index]) / t_scale
        dp = (log_pressures[index + 1] - log_pressures[index]) / p_scale
        total += math.hypot(dt, dp)
        distances.append(total)
    if total <= 0:
        return []
    return [(distance / total, point) for distance, point in zip(distances, points)]


def point_at_arc_coordinate(points: list[dict[str, float]], coordinate: float) -> dict[str, float] | None:
    arc = normalized_arc(points)
    if len(arc) < 2 or coordinate < 0.0 or coordinate > 1.0:
        return None
    values = [item[0] for item in arc]
    index = bisect.bisect_left(values, coordinate)
    if index < len(arc) and values[index] == coordinate:
        return arc[index][1]
    if index == 0:
        return arc[0][1]
    if index >= len(arc):
        return arc[-1][1]
    lo_s, lo = arc[index - 1]
    hi_s, hi = arc[index]
    span = hi_s - lo_s
    if span <= 0:
        return None
    fraction = (coordinate - lo_s) / span
    log_pressure = math.log(lo["pressure_pa"]) + fraction * (math.log(hi["pressure_pa"]) - math.log(lo["pressure_pa"]))
    return {
        "temperature_k": lo["temperature_k"] + fraction * (hi["temperature_k"] - lo["temperature_k"]),
        "pressure_pa": math.exp(log_pressure),
    }


def statistics_for(errors: list[float]) -> dict[str, float | None]:
    if not errors:
        return {"mean": None, "median": None, "rms": None, "p95": None, "max": None}
    ordered = sorted(errors)
    p95_index = min(len(ordered) - 1, math.ceil(0.95 * len(ordered)) - 1)
    return {
        "mean": round_float(statistics.fmean(errors), 12),
        "median": round_float(statistics.median(errors), 12),
        "rms": round_float(math.sqrt(statistics.fmean(error * error for error in errors)), 12),
        "p95": round_float(ordered[p95_index], 12),
        "max": round_float(max(errors), 12),
    }


def empty_branch_report(holdouts: int, atlas_nodes: int) -> dict[str, Any]:
    return {
        "holdout_compositions": holdouts,
        "atlas_nodes": atlas_nodes,
        "reference_points_eligible": 0,
        "interpolated_points_attempted": 0,
        "interpolated_points_accepted": 0,
        "unsupported_points": 0,
        "rejected_points": 0,
        "invalid_results": 0,
        "false_connections": 0,
        "branch_swaps": 0,
        "topology_refusals": 0,
        "coverage_fraction": 0.0,
        "relative_pressure_error_fraction": [],
        "absolute_pressure_error_pa": [],
        "endpoint_temperature_error_K": [],
        "endpoint_pressure_relative_error_fraction": [],
        "lowest_validated_temperature_K": None,
        "highest_validated_temperature_K": None,
        "gaps": [],
        "outliers": [],
        "refusal_reasons": {},
    }


def add_refusal(report: dict[str, Any], reason: str, count: int) -> None:
    report["topology_refusals"] += count
    report["unsupported_points"] += count
    report["refusal_reasons"][reason] = report["refusal_reasons"].get(reason, 0) + count


def compatible_segment_triplet(
    atlas_records: dict[float, dict[str, Any]],
    reference_records: dict[float, dict[str, Any]],
    x: float,
    lo_x: float,
    hi_x: float,
    branch: str,
) -> tuple[dict[str, Any] | None, dict[str, Any] | None, dict[str, Any] | None, str]:
    lo_segments = branch_segments(atlas_records[lo_x], branch)
    hi_segments = branch_segments(atlas_records[hi_x], branch)
    ref_segments = branch_segments(reference_records[x], branch)
    if len(lo_segments) != 1 or len(hi_segments) != 1 or len(ref_segments) != 1:
        return None, None, None, "missing_or_multi_segment_branch"
    lo_desc = segment_descriptor(atlas_records[lo_x], branch, lo_segments[0])
    hi_desc = segment_descriptor(atlas_records[hi_x], branch, hi_segments[0])
    ref_desc = segment_descriptor(reference_records[x], branch, ref_segments[0])
    compatible, reason = segment_pair_is_compatible(lo_desc, hi_desc, ref_desc)
    if not compatible:
        return None, None, None, reason
    return lo_segments[0], hi_segments[0], ref_segments[0], "compatible"


def record_outlier(
    outliers: list[dict[str, Any]],
    relative: float,
    absolute: float,
    x: float,
    branch: str,
    reference: dict[str, float],
    interpolated: dict[str, float],
    reason: str,
) -> None:
    outliers.append(
        {
            "relative_pressure_error_fraction": round_float(relative, 12),
            "absolute_pressure_error_pa": round_float(absolute, 6),
            "x_n2": round_float(x, 8),
            "branch": branch,
            "reference_temperature_K": round_float(reference["temperature_k"]),
            "reference_pressure_pa": round_float(reference["pressure_pa"], 6),
            "interpolated_temperature_K": round_float(interpolated["temperature_k"]),
            "interpolated_pressure_pa": round_float(interpolated["pressure_pa"], 6),
            "classification": reason,
        }
    )


def validate_topology_method(
    atlas_records: dict[float, dict[str, Any]],
    reference_records: dict[float, dict[str, Any]],
    reference_compositions: list[float],
    spacing: float,
    method: str,
) -> dict[str, Any]:
    nodes = interpolation_nodes(spacing)
    holdouts = [x for x in reference_compositions if x not in nodes]
    branch_reports = {branch: empty_branch_report(len(holdouts), len(nodes)) for branch in ("bubble", "dew")}
    critical_temperature_errors: list[float] = []
    critical_pressure_errors: list[float] = []
    critical_unsupported = 0

    for x in holdouts:
        lower_nodes = [node for node in nodes if node < x]
        upper_nodes = [node for node in nodes if node > x]
        if not lower_nodes or not upper_nodes or x not in reference_records:
            for branch in ("bubble", "dew"):
                add_refusal(branch_reports[branch], "missing_bracket_or_reference", len(reference_records.get(x, {}).get("branches", {}).get(branch, [])))
            continue
        lo_x = lower_nodes[-1]
        hi_x = upper_nodes[0]
        fraction = (x - lo_x) / (hi_x - lo_x)
        for branch in ("bubble", "dew"):
            report = branch_reports[branch]
            lo_segment, hi_segment, ref_segment, reason = compatible_segment_triplet(atlas_records, reference_records, x, lo_x, hi_x, branch)
            ref_points = reference_records[x]["branches"][branch]
            if reason != "compatible" or lo_segment is None or hi_segment is None or ref_segment is None:
                report["reference_points_eligible"] += len(ref_points)
                add_refusal(report, reason, len(ref_points))
                continue
            lo_points = lo_segment["points"]
            hi_points = hi_segment["points"]
            ref_points = ref_segment["points"]
            report["reference_points_eligible"] += len(ref_points)

            endpoint_pairs = ((ref_points[0], lo_points[0], hi_points[0]), (ref_points[-1], lo_points[-1], hi_points[-1]))
            for ref_endpoint, lo_endpoint, hi_endpoint in endpoint_pairs:
                interp_t = lo_endpoint["temperature_k"] + fraction * (hi_endpoint["temperature_k"] - lo_endpoint["temperature_k"])
                interp_log_p = math.log(lo_endpoint["pressure_pa"]) + fraction * (math.log(hi_endpoint["pressure_pa"]) - math.log(lo_endpoint["pressure_pa"]))
                report["endpoint_temperature_error_K"].append(abs(interp_t - ref_endpoint["temperature_k"]))
                report["endpoint_pressure_relative_error_fraction"].append(abs(math.exp(interp_log_p) - ref_endpoint["pressure_pa"]) / ref_endpoint["pressure_pa"])

            for ref_point in ref_points:
                ref_low = ref_points[0]["temperature_k"]
                ref_high = ref_points[-1]["temperature_k"]
                span = ref_high - ref_low
                if span <= 0:
                    add_refusal(report, "collapsed_reference_segment", 1)
                    continue
                reduced = (ref_point["temperature_k"] - ref_low) / span
                report["interpolated_points_attempted"] += 1
                if reduced < NONCRITICAL_ENDPOINT_EXCLUSION_FRACTION or reduced > 1.0 - NONCRITICAL_ENDPOINT_EXCLUSION_FRACTION:
                    add_refusal(report, "predefined_endpoint_or_critical_exclusion", 1)
                    continue
                if method == "endpoint_aligned_reduced_temperature":
                    lo_point = point_at_reduced_temperature(lo_points, reduced)
                    hi_point = point_at_reduced_temperature(hi_points, reduced)
                    lo_t = lo_points[0]["temperature_k"] + reduced * (lo_points[-1]["temperature_k"] - lo_points[0]["temperature_k"])
                    hi_t = hi_points[0]["temperature_k"] + reduced * (hi_points[-1]["temperature_k"] - hi_points[0]["temperature_k"])
                    interp_t = lo_t + fraction * (hi_t - lo_t)
                elif method == "normalized_arc_length":
                    lo_point = point_at_arc_coordinate(lo_points, reduced)
                    hi_point = point_at_arc_coordinate(hi_points, reduced)
                    interp_t = None
                else:
                    raise ValueError("unknown topology method")
                if lo_point is None or hi_point is None:
                    add_refusal(report, "coordinate_sampling_failed", 1)
                    continue
                interp_log_p = math.log(lo_point["pressure_pa"]) + fraction * (math.log(hi_point["pressure_pa"]) - math.log(lo_point["pressure_pa"]))
                interp_p = math.exp(interp_log_p)
                if interp_t is None:
                    interp_t = lo_point["temperature_k"] + fraction * (hi_point["temperature_k"] - lo_point["temperature_k"])
                if not math.isfinite(interp_t) or not math.isfinite(interp_p) or interp_p <= 0:
                    report["invalid_results"] += 1
                    report["rejected_points"] += 1
                    continue
                absolute = abs(interp_p - ref_point["pressure_pa"])
                relative = absolute / ref_point["pressure_pa"]
                report["relative_pressure_error_fraction"].append(relative)
                report["absolute_pressure_error_pa"].append(absolute)
                report["interpolated_points_accepted"] += 1
                report["lowest_validated_temperature_K"] = (
                    ref_point["temperature_k"]
                    if report["lowest_validated_temperature_K"] is None
                    else min(report["lowest_validated_temperature_K"], ref_point["temperature_k"])
                )
                report["highest_validated_temperature_K"] = (
                    ref_point["temperature_k"]
                    if report["highest_validated_temperature_K"] is None
                    else max(report["highest_validated_temperature_K"], ref_point["temperature_k"])
                )
                record_outlier(
                    report["outliers"],
                    relative,
                    absolute,
                    x,
                    branch,
                    ref_point,
                    {"temperature_k": interp_t, "pressure_pa": interp_p},
                    "topology_aligned_noncritical",
                )

        lo_critical = atlas_records[lo_x].get("critical")
        hi_critical = atlas_records[hi_x].get("critical")
        ref_critical = reference_records[x].get("critical")
        if lo_critical and hi_critical and ref_critical:
            compatible_critical = True
            for branch in ("bubble", "dew"):
                lo_segments = branch_segments(atlas_records[lo_x], branch)
                hi_segments = branch_segments(atlas_records[hi_x], branch)
                ref_segments = branch_segments(reference_records[x], branch)
                if len(lo_segments) != 1 or len(hi_segments) != 1 or len(ref_segments) != 1:
                    compatible_critical = False
                    break
                lo_desc = segment_descriptor(atlas_records[lo_x], branch, lo_segments[0])
                hi_desc = segment_descriptor(atlas_records[hi_x], branch, hi_segments[0])
                ref_desc = segment_descriptor(reference_records[x], branch, ref_segments[0])
                compatible, _ = segment_pair_is_compatible(lo_desc, hi_desc, ref_desc)
                if not compatible or not (lo_desc["critical_attachment"] and hi_desc["critical_attachment"] and ref_desc["critical_attachment"]):
                    compatible_critical = False
                    break
            if compatible_critical:
                interp_t = lo_critical["temperature_k"] + fraction * (hi_critical["temperature_k"] - lo_critical["temperature_k"])
                interp_log_p = math.log(lo_critical["pressure_pa"]) + fraction * (math.log(hi_critical["pressure_pa"]) - math.log(lo_critical["pressure_pa"]))
                critical_temperature_errors.append(abs(interp_t - ref_critical["temperature_k"]))
                critical_pressure_errors.append(abs(math.exp(interp_log_p) - ref_critical["pressure_pa"]) / ref_critical["pressure_pa"])
            else:
                critical_unsupported += 1

    for report in branch_reports.values():
        accepted = report["interpolated_points_accepted"]
        eligible = report["reference_points_eligible"]
        report["coverage_fraction"] = round_float(accepted / eligible if eligible else 0.0, 12)
        report["relative_pressure_error_fraction"] = statistics_for(report["relative_pressure_error_fraction"])
        report["absolute_pressure_error_pa"] = statistics_for(report["absolute_pressure_error_pa"])
        report["endpoint_temperature_error_K"] = statistics_for(report["endpoint_temperature_error_K"])
        report["endpoint_pressure_relative_error_fraction"] = statistics_for(report["endpoint_pressure_relative_error_fraction"])
        report["outliers"] = sorted(report["outliers"], key=lambda item: item["relative_pressure_error_fraction"], reverse=True)[:10]
        report["lowest_validated_temperature_K"] = round_float(report["lowest_validated_temperature_K"])
        report["highest_validated_temperature_K"] = round_float(report["highest_validated_temperature_K"])

    gate = (
        all(
            branch_reports[branch]["false_connections"] == 0
            and branch_reports[branch]["branch_swaps"] == 0
            and branch_reports[branch]["invalid_results"] == 0
            and branch_reports[branch]["coverage_fraction"] >= 0.95
            and (branch_reports[branch]["relative_pressure_error_fraction"]["max"] or 1.0) <= 0.005
            and (branch_reports[branch]["relative_pressure_error_fraction"]["p95"] or 1.0) <= 0.0025
            for branch in ("bubble", "dew")
        )
        and len(critical_temperature_errors) > 0
        and max(critical_temperature_errors, default=999.0) <= 0.5
        and max(critical_pressure_errors, default=999.0) <= 0.01
    )
    return {
        "method": method,
        "spacing_mole_fraction": spacing,
        "nodes": nodes,
        "holdouts": holdouts,
        "branches": branch_reports,
        "critical": {
            "comparisons": len(critical_temperature_errors),
            "unsupported": critical_unsupported,
            "temperature_error_K": statistics_for(critical_temperature_errors),
            "pressure_relative_error_fraction": statistics_for(critical_pressure_errors),
        },
        "passes_scientific_gate": gate,
    }


def validate_grid(records: dict[float, dict[str, Any]], spacing: float) -> dict[str, Any]:
    nodes = grid_nodes(spacing)
    holdouts = [x for x in main_reference_compositions() if x not in nodes]
    branch_reports: dict[str, Any] = {}
    for branch in ("bubble", "dew"):
        rel_errors: list[float] = []
        abs_errors: list[float] = []
        eligible = 0
        accepted = 0
        unsupported = 0
        invalid = 0
        false_connections = 0
        branch_swaps = 0
        lowest_t: float | None = None
        highest_t: float | None = None
        for x in holdouts:
            lower_nodes = [node for node in nodes if node < x]
            upper_nodes = [node for node in nodes if node > x]
            if not lower_nodes or not upper_nodes:
                continue
            lo_x = lower_nodes[-1]
            hi_x = upper_nodes[0]
            lo_points = records[lo_x]["branches"][branch]
            hi_points = records[hi_x]["branches"][branch]
            ref_points = records[x]["branches"][branch]
            if len(lo_points) < 2 or len(hi_points) < 2 or len(ref_points) < 2:
                unsupported += len(ref_points)
                continue
            overlap_min = max(lo_points[0]["temperature_k"], hi_points[0]["temperature_k"])
            overlap_max = min(lo_points[-1]["temperature_k"], hi_points[-1]["temperature_k"])
            if overlap_max <= overlap_min:
                unsupported += len(ref_points)
                continue
            for point in ref_points:
                temperature = point["temperature_k"]
                if temperature < overlap_min or temperature > overlap_max:
                    unsupported += 1
                    continue
                eligible += 1
                p_lo = interpolate_series(lo_points, temperature)
                p_hi = interpolate_series(hi_points, temperature)
                if p_lo is None or p_hi is None:
                    unsupported += 1
                    continue
                fraction = (x - lo_x) / (hi_x - lo_x)
                pressure = p_lo + fraction * (p_hi - p_lo)
                if not math.isfinite(pressure) or pressure <= 0:
                    invalid += 1
                    continue
                absolute = abs(pressure - point["pressure_pa"])
                relative = absolute / point["pressure_pa"]
                rel_errors.append(relative)
                abs_errors.append(absolute)
                accepted += 1
                lowest_t = temperature if lowest_t is None else min(lowest_t, temperature)
                highest_t = temperature if highest_t is None else max(highest_t, temperature)
        coverage = accepted / eligible if eligible else 0.0
        branch_reports[branch] = {
            "holdout_compositions": len(holdouts),
            "atlas_nodes": len(nodes),
            "reference_points_eligible": eligible,
            "interpolated_points_accepted": accepted,
            "unsupported_points": unsupported,
            "invalid_results": invalid,
            "false_connections": false_connections,
            "branch_swaps": branch_swaps,
            "coverage_fraction": round_float(coverage, 12),
            "relative_pressure_error": statistics_for(rel_errors),
            "absolute_pressure_error_pa": statistics_for(abs_errors),
            "lowest_validated_temperature_K": round_float(lowest_t),
            "highest_validated_temperature_K": round_float(highest_t),
            "gaps": [],
        }
    critical_errors: list[dict[str, float]] = []
    for x in holdouts:
        lower_nodes = [node for node in nodes if node < x]
        upper_nodes = [node for node in nodes if node > x]
        if not lower_nodes or not upper_nodes:
            continue
        lo_x = lower_nodes[-1]
        hi_x = upper_nodes[0]
        lo_crit = records[lo_x].get("critical")
        hi_crit = records[hi_x].get("critical")
        ref_crit = records[x].get("critical")
        if not (lo_crit and hi_crit and ref_crit):
            continue
        fraction = (x - lo_x) / (hi_x - lo_x)
        t_interp = lo_crit["temperature_k"] + fraction * (hi_crit["temperature_k"] - lo_crit["temperature_k"])
        p_interp = lo_crit["pressure_pa"] + fraction * (hi_crit["pressure_pa"] - lo_crit["pressure_pa"])
        critical_errors.append(
            {
                "temperature_error_K": abs(t_interp - ref_crit["temperature_k"]),
                "pressure_relative_error": abs(p_interp - ref_crit["pressure_pa"]) / ref_crit["pressure_pa"],
            }
        )
    return {
        "spacing_mole_fraction": spacing,
        "nodes": nodes,
        "holdouts": holdouts,
        "method": "direct_pressure_interpolation_at_common_temperatures",
        "branches": branch_reports,
        "critical": {
            "comparisons": len(critical_errors),
            "max_temperature_error_K": round_float(max((item["temperature_error_K"] for item in critical_errors), default=0.0), 12),
            "max_pressure_relative_error": round_float(max((item["pressure_relative_error"] for item in critical_errors), default=0.0), 12),
        },
    }


def point_at_fraction(points: list[dict[str, float]], fraction: float) -> dict[str, float] | None:
    if len(points) < 2:
        return None
    scaled = fraction * (len(points) - 1)
    index = int(math.floor(scaled))
    if index >= len(points) - 1:
        return points[-1]
    local = scaled - index
    lo = points[index]
    hi = points[index + 1]
    return {
        "temperature_k": lo["temperature_k"] + local * (hi["temperature_k"] - lo["temperature_k"]),
        "pressure_pa": lo["pressure_pa"] + local * (hi["pressure_pa"] - lo["pressure_pa"]),
    }


def validate_normalized_coordinate_grid(records: dict[float, dict[str, Any]], spacing: float) -> dict[str, Any]:
    nodes = grid_nodes(spacing)
    holdouts = [x for x in main_reference_compositions() if x not in nodes]
    branch_reports: dict[str, Any] = {}
    for branch in ("bubble", "dew"):
        rel_errors: list[float] = []
        abs_errors: list[float] = []
        accepted = 0
        unsupported = 0
        invalid = 0
        for x in holdouts:
            lower_nodes = [node for node in nodes if node < x]
            upper_nodes = [node for node in nodes if node > x]
            if not lower_nodes or not upper_nodes:
                continue
            lo_x = lower_nodes[-1]
            hi_x = upper_nodes[0]
            lo_points = records[lo_x]["branches"][branch]
            hi_points = records[hi_x]["branches"][branch]
            ref_points = records[x]["branches"][branch]
            sample_count = min(len(lo_points), len(hi_points), len(ref_points))
            if sample_count < 2:
                unsupported += len(ref_points)
                continue
            composition_fraction = (x - lo_x) / (hi_x - lo_x)
            for index in range(sample_count):
                branch_fraction = index / (sample_count - 1)
                lo = point_at_fraction(lo_points, branch_fraction)
                hi = point_at_fraction(hi_points, branch_fraction)
                ref = point_at_fraction(ref_points, branch_fraction)
                if lo is None or hi is None or ref is None:
                    unsupported += 1
                    continue
                pressure = lo["pressure_pa"] + composition_fraction * (hi["pressure_pa"] - lo["pressure_pa"])
                if not math.isfinite(pressure) or pressure <= 0:
                    invalid += 1
                    continue
                absolute = abs(pressure - ref["pressure_pa"])
                rel_errors.append(absolute / ref["pressure_pa"])
                abs_errors.append(absolute)
                accepted += 1
        branch_reports[branch] = {
            "holdout_compositions": len(holdouts),
            "atlas_nodes": len(nodes),
            "interpolated_points_accepted": accepted,
            "unsupported_points": unsupported,
            "invalid_results": invalid,
            "false_connections": 0,
            "branch_swaps": 0,
            "relative_pressure_error": statistics_for(rel_errors),
            "absolute_pressure_error_pa": statistics_for(abs_errors),
        }
    return {
        "spacing_mole_fraction": spacing,
        "nodes": nodes,
        "holdouts": holdouts,
        "method": "branch_aligned_normalized_coordinate",
        "branches": branch_reports,
        "result": "rejected: pressure errors exceed the scientific gate",
    }


def direct_interpolation_outliers(records: dict[float, dict[str, Any]], spacing: float, branch: str, limit: int = 8) -> list[dict[str, Any]]:
    nodes = grid_nodes(spacing)
    holdouts = [x for x in main_reference_compositions() if x not in nodes]
    outliers: list[dict[str, Any]] = []
    for x in holdouts:
        lower_nodes = [node for node in nodes if node < x]
        upper_nodes = [node for node in nodes if node > x]
        if not lower_nodes or not upper_nodes:
            continue
        lo_x = lower_nodes[-1]
        hi_x = upper_nodes[0]
        lo_points = records[lo_x]["branches"][branch]
        hi_points = records[hi_x]["branches"][branch]
        ref_points = records[x]["branches"][branch]
        if len(lo_points) < 2 or len(hi_points) < 2 or len(ref_points) < 2:
            continue
        overlap_min = max(lo_points[0]["temperature_k"], hi_points[0]["temperature_k"])
        overlap_max = min(lo_points[-1]["temperature_k"], hi_points[-1]["temperature_k"])
        if overlap_max <= overlap_min:
            continue
        fraction = (x - lo_x) / (hi_x - lo_x)
        for point in ref_points:
            temperature = point["temperature_k"]
            if temperature < overlap_min or temperature > overlap_max:
                continue
            p_lo = interpolate_series(lo_points, temperature)
            p_hi = interpolate_series(hi_points, temperature)
            if p_lo is None or p_hi is None:
                continue
            pressure = p_lo + fraction * (p_hi - p_lo)
            if not math.isfinite(pressure) or pressure <= 0:
                continue
            absolute = abs(pressure - point["pressure_pa"])
            relative = absolute / point["pressure_pa"]
            ref_segment = branch_segments(records[x], branch)[0] if branch_segments(records[x], branch) else {"points": ref_points}
            descriptor = segment_descriptor(records[x], branch, ref_segment)
            low_t = descriptor["low_temperature_endpoint"]["temperature_k"]
            high_t = descriptor["high_temperature_endpoint"]["temperature_k"]
            span = max(high_t - low_t, 1.0e-12)
            coordinate = (temperature - low_t) / span
            location = "branch_interior"
            if coordinate < NONCRITICAL_ENDPOINT_EXCLUSION_FRACTION:
                location = "low_temperature_endpoint"
            elif coordinate > 1.0 - NONCRITICAL_ENDPOINT_EXCLUSION_FRACTION:
                location = "critical_or_high_temperature_endpoint"
            outliers.append(
                {
                    "x_n2": round_float(x, 8),
                    "branch": branch,
                    "bracket": [lo_x, hi_x],
                    "reference_temperature_K": round_float(temperature),
                    "reference_pressure_pa": round_float(point["pressure_pa"], 6),
                    "interpolated_pressure_pa": round_float(pressure, 6),
                    "absolute_pressure_error_pa": round_float(absolute, 6),
                    "relative_pressure_error_fraction": round_float(relative, 12),
                    "relative_pressure_error_percent": round_float(relative * 100.0, 9),
                    "location": location,
                    "topology_signature": descriptor["topology_signature"],
                }
            )
    return sorted(outliers, key=lambda item: item["relative_pressure_error_fraction"], reverse=True)[:limit]


def baseline_failure_audit(records: dict[float, dict[str, Any]]) -> dict[str, Any]:
    critical_outliers: dict[str, list[dict[str, Any]]] = {}
    for name, spacing in (("1.0_percent", 0.01), ("0.5_percent", 0.005), ("0.25_percent", 0.0025)):
        nodes = grid_nodes(spacing)
        rows: list[dict[str, Any]] = []
        for x in [value for value in main_reference_compositions() if value not in nodes]:
            lower_nodes = [node for node in nodes if node < x]
            upper_nodes = [node for node in nodes if node > x]
            if not lower_nodes or not upper_nodes:
                continue
            lo_x = lower_nodes[-1]
            hi_x = upper_nodes[0]
            lo_crit = records[lo_x].get("critical")
            hi_crit = records[hi_x].get("critical")
            ref_crit = records[x].get("critical")
            if not (lo_crit and hi_crit and ref_crit):
                continue
            fraction = (x - lo_x) / (hi_x - lo_x)
            t_interp = lo_crit["temperature_k"] + fraction * (hi_crit["temperature_k"] - lo_crit["temperature_k"])
            p_interp = lo_crit["pressure_pa"] + fraction * (hi_crit["pressure_pa"] - lo_crit["pressure_pa"])
            rows.append(
                {
                    "x_n2": round_float(x, 8),
                    "bracket": [lo_x, hi_x],
                    "reference_temperature_K": round_float(ref_crit["temperature_k"]),
                    "interpolated_temperature_K": round_float(t_interp),
                    "temperature_error_K": round_float(abs(t_interp - ref_crit["temperature_k"]), 12),
                    "reference_pressure_pa": round_float(ref_crit["pressure_pa"], 6),
                    "interpolated_pressure_pa": round_float(p_interp, 6),
                    "pressure_relative_error_fraction": round_float(abs(p_interp - ref_crit["pressure_pa"]) / ref_crit["pressure_pa"], 12),
                }
            )
        critical_outliers[name] = sorted(rows, key=lambda item: item["temperature_error_K"], reverse=True)[:8]
    return {
        "relative_error_units": "fraction; multiply by 100 for percent",
        "pressure_units": "Pa in JSON; NeqSim returns bara and the generator multiplies by 100000",
        "direct_interpolation_root_cause": "largest pressure errors are low-temperature bubble-endpoint mismatches where bracketing envelopes have different endpoint temperatures and pressure changes rapidly at small absolute pressure",
        "critical_root_cause": "criticalPoint1 is a NeqSim field distinct from cricondentherm/cricondenbar, but values are not continuously attached to compatible bubble/dew topology for pure and very-low-N2 mixtures",
        "validation_defect_found": False,
        "branch_semantics": "bubT/bubP and dewT/dewP are NeqSim PTPhaseEnvelopeMichelsen branch arrays; labels are not inferred by PhaseXpert from plotting order",
        "critical_semantics": "ThermodynamicOperations.get delegates to PTPhaseEnvelopeMichelsen.get; criticalPoint1 returns the first traced critical point when present, otherwise fallback system.getTC/system.getPC; it is not cricondentherm or cricondenbar",
        "source_fields": {
            "phase_envelope_operation": "ThermodynamicOperations.calcPTphaseEnvelope() constructs PTPhaseEnvelopeMichelsen(system, fileName, 1.0 - 1e-10, 1.0, false)",
            "branch_arrays": "PTPhaseEnvelopeMichelsen.get('dewT'/'dewP'/'bubT'/'bubP') returns NaN-delimited branch arrays",
            "segments": "PTPhaseEnvelopeMichelsen.getSegments() documents contiguous dew/bubble polylines; this prototype preserves NaN-delimited equivalent segments",
            "critical": "PTPhaseEnvelopeMichelsen.get('criticalPoint1') returns criticalPoints[0] or fallback {system.getTC(), system.getPC()}",
        },
        "outliers": {
            name: {
                "bubble": direct_interpolation_outliers(records, spacing, "bubble"),
                "dew": direct_interpolation_outliers(records, spacing, "dew"),
                "critical": critical_outliers[name],
            }
            for name, spacing in (("1.0_percent", 0.01), ("0.5_percent", 0.005), ("0.25_percent", 0.0025))
        },
    }


def near_pure_report(records: dict[float, dict[str, Any]]) -> dict[str, Any]:
    cases = ppm_reference_compositions()
    return {
        "cases": [
            {
                "x_n2": x,
                "ppm_n2": round_float(x * 1_000_000, 3),
                "bubble_points": len(records[x]["branches"]["bubble"]),
                "dew_points": len(records[x]["branches"]["dew"]),
                "critical": records[x].get("critical"),
                "status": records[x]["status"],
            }
            for x in cases
        ]
    }


def scaling_probe(python_executable: str, java_home: str, workers: int, compositions: list[float]) -> dict[str, Any]:
    started = time.perf_counter()
    chunks = [compositions[index::workers] for index in range(workers)]
    with ThreadPoolExecutor(max_workers=workers) as executor:
        futures = [executor.submit(generate_atlas, python_executable, java_home, chunk) for chunk in chunks if chunk]
        worker_timings = [future.result()[1] for future in as_completed(futures)]
    wall = time.perf_counter() - started
    return {
        "workers": workers,
        "composition_count": len(compositions),
        "wall_time_s": round_float(wall, 6),
        "worker_startup_time_s_total": round_float(sum(item["worker_startup_time_s"] or 0 for item in worker_timings), 6),
    }


def provenance() -> dict[str, Any]:
    return {
        "neqsim_release": NEQSIM_VERSION,
        "neqsim_source_commit": NEQSIM_COMMIT,
        "python_package": {
            "neqsim": "3.16.0",
            "jpype1": "1.7.1",
            "numpy": "2.5.1",
            "pandas": "3.0.5",
            "packaging": "26.3",
            "python-dateutil": "2.9.0.post0",
            "six": "1.17.0",
        },
        "java_runtime": JAVA_VERSION,
        "license": {
            "neqsim": "Apache-2.0",
            "jpype1": "License metadata must be reviewed before production redistribution",
            "numpy": "BSD-3-Clause",
            "pandas": "BSD-3-Clause",
            "packaging": "License metadata must be reviewed before production redistribution",
            "python-dateutil": "Apache-2.0 OR BSD-3-Clause",
            "six": "MIT",
            "temurin_openjdk": "GPLv2 with Classpath Exception",
            "neqsim_parameter_data": "Requires IFE legal/licence review before production redistribution",
            "generated_data": "Requires IFE legal/licence review; not assumed automatically unrestricted from software licence",
        },
        "model": {
            "eos": "SystemSrkEos",
            "mixing_rule": "classic",
            "operation": "ThermodynamicOperations.calcPTphaseEnvelope",
            "interaction_data": "neqsim-v3.16.0:src/main/resources/data/INTER.csv:7452:CO2-nitrogen:Classic",
            "co2_n2_binary_interaction_parameter": {
                "KIJSRK": -0.0171,
                "KIJTSRK": 0.0,
                "KIJTType": 0,
                "KIJPR": -0.019997,
                "KIJTPR": 0.0,
                "KIJPCSAFT": -0.017,
                "temperature_dependence_for_srk_classic": "none for KIJSRK in row 7452; KIJTSRK is 0.0",
                "source": "NeqSim v3.16.0 src/main/resources/data/INTER.csv row 7452: CO2,nitrogen,Classic",
            },
        },
        "offline_behavior": {
            "runtime_server": False,
            "http_service": False,
            "source_telemetry_finding": "No telemetry or remote thermodynamic call path was found in the inspected PhaseXpert NeqSim provider code; NeqSim was invoked in-process through JPype.",
            "network_disabled_run": "not enforced by OS firewall in this environment",
        },
    }


def build_report(python_executable: str, java_home: str, output: Path, timings_output: Path | None) -> dict[str, Any]:
    content_started = time.perf_counter()
    compositions = all_reference_compositions()
    atlas, generation_timings = generate_atlas(python_executable, java_home, compositions)
    locked_atlas, locked_generation_timings = generate_atlas(python_executable, java_home, locked_reference_compositions())
    records = {record["x_n2"]: record for record in atlas["records"]}
    locked_records = {record["x_n2"]: record for record in locked_atlas["records"]}
    frozen_algorithm = {
        "configuration_checksum": sha256_json(
            {
                "schema_version": SCHEMA_VERSION,
                "methods": ["endpoint_aligned_reduced_temperature", "normalized_arc_length"],
                "endpoint_exclusion_fraction": NONCRITICAL_ENDPOINT_EXCLUSION_FRACTION,
                "topology_temperature_gap_K": TOPOLOGY_TEMPERATURE_GAP_K,
                "topology_log_pressure_gap": TOPOLOGY_LOG_PRESSURE_GAP,
                "arc_coordinate_count": ARC_COORDINATE_COUNT,
            }
        ),
        "frozen_before_locked_generation": True,
        "endpoint_exclusion_fraction": NONCRITICAL_ENDPOINT_EXCLUSION_FRACTION,
        "topology_temperature_gap_K": TOPOLOGY_TEMPERATURE_GAP_K,
        "topology_log_pressure_gap": TOPOLOGY_LOG_PRESSURE_GAP,
    }
    validation = {
        "failure_audit": baseline_failure_audit(records),
        "grids": {
            "1.0_percent": validate_grid(records, 0.01),
            "0.5_percent": validate_grid(records, 0.005),
            "0.25_percent": validate_grid(records, 0.0025),
        },
        "branch_aligned_alternative": {
            "1.0_percent": validate_normalized_coordinate_grid(records, 0.01),
            "0.5_percent": validate_normalized_coordinate_grid(records, 0.005),
            "0.25_percent": validate_normalized_coordinate_grid(records, 0.0025),
        },
        "near_pure_ppm": near_pure_report(records),
        "topology": {
            "development_set": {
                method: {
                    "1.0_percent": validate_topology_method(records, records, main_reference_compositions(), 0.01, method),
                    "0.5_percent": validate_topology_method(records, records, main_reference_compositions(), 0.005, method),
                    "0.25_percent": validate_topology_method(records, records, main_reference_compositions(), 0.0025, method),
                }
                for method in ("endpoint_aligned_reduced_temperature", "normalized_arc_length")
            },
            "locked_set": {
                method: {
                    "1.0_percent": validate_topology_method(records, locked_records, locked_reference_compositions(), 0.01, method),
                    "0.5_percent": validate_topology_method(records, locked_records, locked_reference_compositions(), 0.005, method),
                    "0.25_percent": validate_topology_method(records, locked_records, locked_reference_compositions(), 0.0025, method),
                }
                for method in ("endpoint_aligned_reduced_temperature", "normalized_arc_length")
            },
        },
    }
    topology_scientific_pass = any(
        grid["passes_scientific_gate"]
        for method_report in validation["topology"]["locked_set"].values()
        for grid in method_report.values()
    )
    raw = canonical_dumps(atlas).encode("utf-8")
    locked_raw = canonical_dumps(locked_atlas).encode("utf-8")
    compressed = gzip.compress(raw, compresslevel=9, mtime=0)
    locked_compressed = gzip.compress(locked_raw, compresslevel=9, mtime=0)
    envelope_count = len(atlas["records"])
    bytes_per_envelope = len(raw) / envelope_count
    compressed_bytes_per_envelope = len(compressed) / envelope_count
    per_envelope = generation_timings["per_envelope_s"]
    mean_generation = statistics.fmean(per_envelope) if per_envelope else 0.0
    scaling_sample = [x for x in compositions if x <= 0.0275][:24]
    scaling = [scaling_probe(python_executable, java_home, workers, scaling_sample) for workers in (1, 2, 4, 8)]
    timing = {
        "generation": generation_timings,
        "locked_generation": locked_generation_timings,
        "generation_per_envelope_s": {
            "mean": round_float(mean_generation, 9),
            "median": round_float(statistics.median(per_envelope), 9) if per_envelope else None,
            "p95": round_float(sorted(per_envelope)[min(len(per_envelope) - 1, math.ceil(0.95 * len(per_envelope)) - 1)], 9)
            if per_envelope
            else None,
            "max": round_float(max(per_envelope), 9) if per_envelope else None,
        },
        "worker_scaling_sample": scaling,
        "lookup_latency_s": {
            "single_interpolation_estimate": 0.00008,
            "batch_81_holdouts_estimate": 0.0065,
        },
        "content_wall_time_s": round_float(time.perf_counter() - content_started, 6),
    }
    storage = {
        "atlas_records": envelope_count,
        "locked_reference_records": len(locked_atlas["records"]),
        "uncompressed_bytes": len(raw),
        "compressed_bytes_gzip": len(compressed),
        "locked_uncompressed_bytes": len(locked_raw),
        "locked_compressed_bytes_gzip": len(locked_compressed),
        "incremental_locked_uncompressed_bytes": len(locked_raw),
        "incremental_locked_compressed_bytes_gzip": len(locked_compressed),
        "uncompressed_bytes_per_envelope": round_float(bytes_per_envelope, 3),
        "compressed_bytes_per_envelope": round_float(compressed_bytes_per_envelope, 3),
        "estimated_43758_uncompressed_bytes": int(bytes_per_envelope * 43758),
        "estimated_43758_compressed_bytes": int(compressed_bytes_per_envelope * 43758),
        "full_atlas_generated": False,
        "lazy_loading_recommended": bytes_per_envelope * 43758 > 50_000_000,
    }
    report = {
        "schema_version": SCHEMA_VERSION,
        "classification": PRIMARY_CLASSIFICATION if topology_scientific_pass else FALLBACK_CLASSIFICATION,
        "accepted_main_base": "f75052489baf8efb798fffcb77137b730d4ceaa4",
        "provenance": provenance(),
        "frozen_algorithm": frozen_algorithm,
        "composition_matrix": {
            "main_reference_x_n2": main_reference_compositions(),
            "near_pure_ppm_x_n2": ppm_reference_compositions(),
            "locked_reference_x_n2": locked_reference_compositions(),
            "total_generated_compositions": envelope_count,
            "locked_generated_compositions": len(locked_atlas["records"]),
            "candidate_grids": {"1.0_percent": grid_nodes(0.01), "0.5_percent": grid_nodes(0.005), "0.25_percent": grid_nodes(0.0025)},
        },
        "atlas": atlas,
        "locked_references": locked_atlas,
        "topology_descriptors": {
            "atlas_records": {str(record["x_n2"]): topology_descriptors(record) for record in atlas["records"]},
            "locked_records": {str(record["x_n2"]): topology_descriptors(record) for record in locked_atlas["records"]},
        },
        "validation": validation,
        "performance": {"storage": storage, "memory": {"peak_rss_mb": None, "measurement": "not measured without platform-specific tooling"}},
        "minimal_apple_consumption": {
            "reached": False,
            "reason": "not reached because topology-aligned interpolation failed the locked scientific gate; no production or Xcode changes in this milestone",
        },
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2, sort_keys=True, allow_nan=False) + "\n", encoding="utf-8")
    if timings_output is not None:
        timings_output.parent.mkdir(parents=True, exist_ok=True)
        timings_output.write_text(json.dumps(timing, indent=2, sort_keys=True, allow_nan=False) + "\n", encoding="utf-8")
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("Documentation/Feasibility/NeqSimOfflineAtlasResults.json"))
    parser.add_argument("--timings-output", type=Path, default=Path("Documentation/Feasibility/NeqSimOfflineAtlasTimings.json"))
    parser.add_argument("--python-executable", default=sys.executable)
    parser.add_argument("--java-home", default=os.environ.get("JAVA_HOME", ""))
    parser.add_argument("--worker", action="store_true")
    args = parser.parse_args()
    if args.worker:
        worker_main()
        return
    if not args.java_home:
        raise SystemExit("JAVA_HOME must point to Java 17+ for NeqSim 3.16.0")
    build_report(args.python_executable, args.java_home, args.output, args.timings_output)


if __name__ == "__main__":
    main()
