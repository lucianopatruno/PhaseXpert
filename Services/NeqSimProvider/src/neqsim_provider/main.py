from __future__ import annotations

import math
import os
import subprocess
import time
import uuid
from typing import Any

from fastapi import FastAPI, HTTPException

from . import __version__
from .contracts import (
    API_SCHEMA_VERSION,
    Branch,
    CapabilityResponse,
    Component,
    ConvergenceMetadata,
    EnvelopePoint,
    EnvelopeRequest,
    EnvelopeResponse,
    PhaseRegion,
    PropertyID,
    PropertyResult,
    PropertyStatus,
    ProviderProvenance,
    StateRequest,
    StateResponse,
)

try:
    from neqsim import jneqsim
except Exception:  # pragma: no cover - exercised in deployment diagnostics
    jneqsim = None


app = FastAPI(title="PhaseXpert NeqSim Provider", version=__version__)


def _java_version() -> str:
    configured = os.environ.get("JAVA_VERSION")
    if configured:
        return configured
    try:
        completed = subprocess.run(
            ["java", "-version"],
            capture_output=True,
            text=True,
            timeout=2.0,
            check=False,
        )
    except Exception:
        return "unreported"
    output = (completed.stderr or completed.stdout).splitlines()
    return output[0] if output else "unreported"


def _provenance() -> ProviderProvenance:
    return ProviderProvenance(service_version=__version__, java_runtime_version=_java_version())


def _component_name(component: Component) -> str:
    return "CO2" if component == Component.co2 else "nitrogen"


def _finite(value: Any) -> float | None:
    try:
        number = float(value)
    except Exception:
        return None
    return number if math.isfinite(number) else None


def _build_fluid(pressure_pa: float, temperature_k: float, composition):
    if jneqsim is None:
        raise RuntimeError("NeqSim Python bridge is not importable")
    fluid = jneqsim.thermo.system.SystemSrkEos(float(temperature_k), float(pressure_pa) / 100000.0)
    total = sum(entry.mole_fraction for entry in composition)
    for entry in composition:
        fluid.addComponent(_component_name(entry.component), float(entry.mole_fraction / total))
    fluid.setMixingRule("classic")
    return fluid


@app.get("/v1/health", response_model=CapabilityResponse)
def health() -> CapabilityResponse:
    return CapabilityResponse(service_version=__version__)


@app.post("/v1/state", response_model=StateResponse)
def calculate_state(request: StateRequest) -> StateResponse:
    started = time.monotonic()
    calculation_id = str(uuid.uuid4())
    warnings = [
        "NeqSim remote result is integration output only and has not completed PhaseXpert scientific validation."
    ]
    try:
        fluid = _build_fluid(request.pressure_pa, request.temperature_k, request.composition)
        ops = jneqsim.thermodynamicoperations.ThermodynamicOperations(fluid)
        ops.TPflash()
        fluid.initProperties()
        phase = _phase_region(fluid)
        properties = _properties(fluid, request.requested_properties)
        converged = all(item.status != PropertyStatus.failed for item in properties)
        status = "completed" if converged else "completed_with_unavailable_properties"
    except Exception as error:
        raise HTTPException(
            status_code=422,
            detail={
                "schema_version": API_SCHEMA_VERSION,
                "request_id": request.request_id,
                "calculation_id": calculation_id,
                "error": "neqsim_state_failed",
                "message": str(error),
            },
        ) from error

    return StateResponse(
        request_id=request.request_id,
        calculation_id=calculation_id,
        provenance=_provenance(),
        pressure_pa=request.pressure_pa,
        temperature_k=request.temperature_k,
        composition=request.composition,
        phase=phase,
        properties=properties,
        warnings=warnings,
        convergence=ConvergenceMetadata(
            method="NeqSim SystemSrkEos TPflash + initProperties",
            converged=converged,
            duration_ms=(time.monotonic() - started) * 1000.0,
            status=status,
        ),
    )


@app.post("/v1/phase-envelope", response_model=EnvelopeResponse)
def phase_envelope(request: EnvelopeRequest) -> EnvelopeResponse:
    started = time.monotonic()
    calculation_id = str(uuid.uuid4())
    warnings = [
        "NeqSim phase envelope is integration output only and has not completed PhaseXpert scientific validation.",
        "Straight chart segments are display-only connections between adjacent finite NeqSim points.",
    ]
    try:
        fluid = _build_fluid(100000.0, 273.15, request.composition)
        ops = jneqsim.thermodynamicoperations.ThermodynamicOperations(fluid)
        ops.calcPTphaseEnvelope()
        points = _envelope_points(ops, request.maximum_points)
    except Exception as error:
        raise HTTPException(
            status_code=422,
            detail={
                "schema_version": API_SCHEMA_VERSION,
                "request_id": request.request_id,
                "calculation_id": calculation_id,
                "error": "neqsim_phase_envelope_failed",
                "message": str(error),
            },
        ) from error

    is_complete = bool(points)
    return EnvelopeResponse(
        request_id=request.request_id,
        calculation_id=calculation_id,
        provenance=_provenance(),
        points=points,
        is_available=bool(points),
        is_complete=is_complete,
        warnings=warnings if is_complete else warnings + ["NeqSim returned no finite envelope points."],
        convergence=ConvergenceMetadata(
            method="NeqSim SystemSrkEos calcPTphaseEnvelope",
            converged=is_complete,
            duration_ms=(time.monotonic() - started) * 1000.0,
            status="completed" if is_complete else "no_finite_points",
        ),
    )


def _phase_region(fluid) -> PhaseRegion:
    phases = int(fluid.getNumberOfPhases())
    if phases > 1:
        return PhaseRegion.twoPhase
    try:
        phase_type = str(fluid.getPhase(0).getType()).lower()
    except Exception:
        return PhaseRegion.unknown
    if "gas" in phase_type:
        return PhaseRegion.gas
    if "liquid" in phase_type or "oil" in phase_type:
        return PhaseRegion.liquid
    return PhaseRegion.unknown


def _properties(fluid, requested: list[PropertyID]) -> list[PropertyResult]:
    by_id: dict[PropertyID, tuple[float | None, str]] = {
        PropertyID.density: (_finite(fluid.getDensity("kg/m3")), "kg/m³"),
        PropertyID.dynamicViscosity: (_finite(fluid.getViscosity("kg/msec")), "Pa·s"),
        PropertyID.molarMass: (_finite(fluid.getMolarMass("kg/mol")), "kg/mol"),
        PropertyID.compressibilityFactor: (_finite(fluid.getZ()), "1"),
    }
    density = by_id[PropertyID.density][0]
    if density and density > 0:
        by_id[PropertyID.specificVolume] = (1.0 / density, "m³/kg")
    results: list[PropertyResult] = []
    for property_id in requested:
        value_unit = by_id.get(property_id)
        if value_unit is None:
            results.append(
                PropertyResult(
                    property=property_id,
                    value=None,
                    unit="",
                    status=PropertyStatus.unavailable,
                    message="This property is not exposed by the initial NeqSim remote contract.",
                )
            )
            continue
        value, unit = value_unit
        if value is None or not math.isfinite(value):
            results.append(
                PropertyResult(
                    property=property_id,
                    value=None,
                    unit=unit,
                    status=PropertyStatus.failed,
                    message="NeqSim returned a non-finite value.",
                )
            )
            continue
        results.append(
            PropertyResult(property=property_id, value=value, unit=unit, status=PropertyStatus.calculated)
        )
    return results


def _envelope_points(ops, maximum_points: int) -> list[EnvelopePoint]:
    points: list[EnvelopePoint] = []
    for key_t, key_p, branch in (("bubT", "bubP", Branch.bubble), ("dewT", "dewP", Branch.dew)):
        temperatures = list(ops.get(key_t) or [])
        pressures_bara = list(ops.get(key_p) or [])
        for temperature, pressure_bara in zip(temperatures, pressures_bara):
            temperature_k = _finite(temperature)
            pressure_pa = _finite(float(pressure_bara) * 100000.0)
            if temperature_k is None or pressure_pa is None or temperature_k <= 0 or pressure_pa <= 0:
                continue
            points.append(EnvelopePoint(temperature_k=temperature_k, pressure_pa=pressure_pa, branch=branch))
            if len(points) >= maximum_points:
                return points
    critical = ops.get("criticalPoint1")
    if critical is not None and len(critical) >= 2:
        temperature_k = _finite(critical[0])
        pressure_pa = _finite(float(critical[1]) * 100000.0)
        if temperature_k is not None and pressure_pa is not None and temperature_k > 0 and pressure_pa > 0:
            points.append(EnvelopePoint(temperature_k=temperature_k, pressure_pa=pressure_pa, branch=Branch.critical))
    return points[:maximum_points]
