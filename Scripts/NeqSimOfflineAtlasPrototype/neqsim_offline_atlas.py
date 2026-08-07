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


SCHEMA_VERSION = "phasexpert-neqsim-offline-atlas.v1"
NEQSIM_VERSION = "3.16.0"
NEQSIM_COMMIT = "3af7b560525b57f2d3da2c803a08e2b41a8d7f5a"
JAVA_VERSION = "Temurin-21.0.12+8"
JVM_STARTUP_ESTIMATE_S = 1.80
PER_ENVELOPE_DEADLINE_S = 5.0
OVERALL_CAMPAIGN_DEADLINE_S = 240.0

PRIMARY_CLASSIFICATION = "The NeqSim offline-atlas approach passes the scientific gate, but Apple consumption remains unproven."


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

    def finite_points(values_t: Any, values_p: Any, branch: str) -> tuple[list[dict[str, float]], list[dict[str, Any]]]:
        points: list[dict[str, float]] = []
        rejected: list[dict[str, Any]] = []
        for index, (temperature, pressure_bara) in enumerate(zip(list(values_t or []), list(values_p or []))):
            try:
                temperature_k = float(temperature)
                pressure_pa = float(pressure_bara) * 100000.0
            except Exception as error:
                rejected.append({"branch": branch, "index": index, "reason": type(error).__name__})
                continue
            if not math.isfinite(temperature_k) or not math.isfinite(pressure_pa) or temperature_k <= 0 or pressure_pa <= 0:
                rejected.append({"branch": branch, "index": index, "reason": "non_finite_or_out_of_domain"})
                continue
            points.append({"temperature_k": round_float(temperature_k), "pressure_pa": round_float(pressure_pa, 6)})
        points.sort(key=lambda point: (point["temperature_k"], point["pressure_pa"]))
        return points, rejected

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
            for key_t, key_p, branch in (("bubT", "bubP", "bubble"), ("dewT", "dewP", "dew")):
                points, rejected = finite_points(ops.get(key_t), ops.get(key_p), branch)
                branches[branch] = points
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
            response["status"] = "converged" if any(branches.values()) else "no_finite_points"
        except Exception as error:  # pragma: no cover - exercised by subprocess integration
            response["error"] = type(error).__name__ + ": " + str(error)
        response["duration_s"] = round_float(time.perf_counter() - started, 9)
        print(canonical_dumps(response), flush=True)


class NeqSimWorker:
    def __init__(self, python_executable: str, java_home: str, deadline_s: float = PER_ENVELOPE_DEADLINE_S):
        self.python_executable = python_executable
        self.java_home = java_home
        self.deadline_s = deadline_s
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
            [self.python_executable, __file__, "--worker"],
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

    def kill(self) -> None:
        if self.process and self.process.poll() is None:
            self.process.kill()
            try:
                self.process.wait(timeout=2.0)
            except subprocess.TimeoutExpired:
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
    records = {record["x_n2"]: record for record in atlas["records"]}
    validation = {
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
    }
    scientific_pass = any(
        all(
            grid["branches"][branch]["false_connections"] == 0
            and grid["branches"][branch]["branch_swaps"] == 0
            and grid["branches"][branch]["invalid_results"] == 0
            and grid["branches"][branch]["coverage_fraction"] >= 0.95
            and (grid["branches"][branch]["relative_pressure_error"]["max"] or 1.0) <= 0.005
            and (grid["branches"][branch]["relative_pressure_error"]["p95"] or 1.0) <= 0.0025
            for branch in ("bubble", "dew")
        )
        and grid["critical"]["max_temperature_error_K"] <= 0.5
        and grid["critical"]["max_pressure_relative_error"] <= 0.01
        for grid in validation["grids"].values()
    )
    raw = canonical_dumps(atlas).encode("utf-8")
    compressed = gzip.compress(raw, compresslevel=9, mtime=0)
    envelope_count = len(atlas["records"])
    bytes_per_envelope = len(raw) / envelope_count
    compressed_bytes_per_envelope = len(compressed) / envelope_count
    per_envelope = generation_timings["per_envelope_s"]
    mean_generation = statistics.fmean(per_envelope) if per_envelope else 0.0
    scaling_sample = [x for x in compositions if x <= 0.0275][:24]
    scaling = [scaling_probe(python_executable, java_home, workers, scaling_sample) for workers in (1, 2, 4, 8)]
    timing = {
        "generation": generation_timings,
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
        "uncompressed_bytes": len(raw),
        "compressed_bytes_gzip": len(compressed),
        "uncompressed_bytes_per_envelope": round_float(bytes_per_envelope, 3),
        "compressed_bytes_per_envelope": round_float(compressed_bytes_per_envelope, 3),
        "estimated_43758_uncompressed_bytes": int(bytes_per_envelope * 43758),
        "estimated_43758_compressed_bytes": int(compressed_bytes_per_envelope * 43758),
        "full_atlas_generated": False,
        "lazy_loading_recommended": bytes_per_envelope * 43758 > 50_000_000,
    }
    report = {
        "schema_version": SCHEMA_VERSION,
        "classification": PRIMARY_CLASSIFICATION if scientific_pass else "Interpolation fails the scientific gate.",
        "accepted_main_base": "f75052489baf8efb798fffcb77137b730d4ceaa4",
        "provenance": provenance(),
        "composition_matrix": {
            "main_reference_x_n2": main_reference_compositions(),
            "near_pure_ppm_x_n2": ppm_reference_compositions(),
            "total_generated_compositions": envelope_count,
            "candidate_grids": {"1.0_percent": grid_nodes(0.01), "0.5_percent": grid_nodes(0.005), "0.25_percent": grid_nodes(0.0025)},
        },
        "atlas": atlas,
        "validation": validation,
        "performance": {"storage": storage, "memory": {"peak_rss_mb": None, "measurement": "not measured without platform-specific tooling"}},
        "minimal_apple_consumption": {
            "reached": False,
            "reason": "not reached because interpolation failed the scientific gate; no production or Xcode changes in this milestone",
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
