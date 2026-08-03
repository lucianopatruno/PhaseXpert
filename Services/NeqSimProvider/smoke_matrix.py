from __future__ import annotations

import json
import time

from neqsim_provider.contracts import Component, CompositionEntry, EnvelopeRequest, PropertyID, StateRequest
from neqsim_provider.main import calculate_state, phase_envelope


CASES = [
    ("pure-co2", [(Component.co2, 1.0)]),
    ("co2-n2-97-3", [(Component.co2, 0.97), (Component.n2, 0.03)]),
    ("co2-n2-90-10", [(Component.co2, 0.90), (Component.n2, 0.10)]),
]
STATES = [
    ("10bara-20c", 1_000_000.0, 293.15),
    ("150bara-20c", 15_000_000.0, 293.15),
]


def entries(composition):
    return [CompositionEntry(component=component, mole_fraction=fraction) for component, fraction in composition]


def main() -> None:
    output = {"states": [], "envelopes": []}
    for case_name, composition in CASES:
        for state_name, pressure_pa, temperature_k in STATES:
            started = time.monotonic()
            response = calculate_state(
                StateRequest(
                    schema_version="neqsim-provider.v1",
                    request_id=f"{case_name}-{state_name}",
                    pressure_pa=pressure_pa,
                    temperature_k=temperature_k,
                    composition=entries(composition),
                    requested_properties=[
                        PropertyID.density,
                        PropertyID.dynamicViscosity,
                        PropertyID.molarMass,
                        PropertyID.compressibilityFactor,
                        PropertyID.specificVolume,
                    ],
                    client_version="smoke-matrix",
                )
            )
            output["states"].append(
                {
                    "case": case_name,
                    "state": state_name,
                    "duration_ms": (time.monotonic() - started) * 1000.0,
                    "phase": response.phase,
                    "properties": [item.model_dump(mode="json") for item in response.properties],
                    "converged": response.convergence.converged,
                }
            )
        started = time.monotonic()
        envelope = phase_envelope(
            EnvelopeRequest(
                schema_version="neqsim-provider.v1",
                request_id=f"{case_name}-envelope",
                composition=entries(composition),
                maximum_points=240,
                timeout_seconds=20.0,
            )
        )
        output["envelopes"].append(
            {
                "case": case_name,
                "duration_ms": (time.monotonic() - started) * 1000.0,
                "point_count": len(envelope.points),
                "bubble_count": sum(1 for point in envelope.points if point.branch == "bubble"),
                "dew_count": sum(1 for point in envelope.points if point.branch == "dew"),
                "complete": envelope.is_complete,
                "converged": envelope.convergence.converged,
            }
        )
    print(json.dumps(output, indent=2))


if __name__ == "__main__":
    main()
