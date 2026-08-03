import os

import pytest
from fastapi.testclient import TestClient

from neqsim_provider.main import app, jneqsim


pytestmark = pytest.mark.skipif(
    os.environ.get("PHASEXPERT_RUN_NEQSIM_ENGINE_TESTS") != "1" or jneqsim is None,
    reason="Set PHASEXPERT_RUN_NEQSIM_ENGINE_TESTS=1 with Java 21+ to run NeqSim engine integration tests.",
)


def test_pure_co2_and_co2_n2_state_and_envelope_paths_return_finite_provider_values():
    client = TestClient(app)
    for label, composition in {
        "pure-co2": [{"component": "co2", "mole_fraction": 1.0}],
        "co2-n2-97-3": [
            {"component": "co2", "mole_fraction": 0.97},
            {"component": "n2", "mole_fraction": 0.03},
        ],
        "co2-n2-90-10": [
            {"component": "co2", "mole_fraction": 0.90},
            {"component": "n2", "mole_fraction": 0.10},
        ],
    }.items():
        for pressure in (1_000_000.0, 15_000_000.0):
            response = client.post(
                "/v1/state",
                json={
                    "schema_version": "neqsim-provider.v1",
                    "request_id": f"{label}-{int(pressure)}",
                    "pressure_pa": pressure,
                    "temperature_k": 293.15,
                    "composition": composition,
                    "requested_properties": [
                        "density",
                        "dynamicViscosity",
                        "molarMass",
                        "compressibilityFactor",
                        "specificVolume",
                    ],
                    "normalize_composition": False,
                    "client_version": "pytest",
                },
            )
            assert response.status_code == 200
            body = response.json()
            assert body["provenance"]["provider_id"] == "neqsim-remote-srk-classic"
            assert body["convergence"]["converged"] is True
            calculated = [item for item in body["properties"] if item["status"] == "calculated"]
            assert len(calculated) == 5
            assert all(item["value"] > 0 for item in calculated)

        envelope_response = client.post(
            "/v1/phase-envelope",
            json={
                "schema_version": "neqsim-provider.v1",
                "request_id": f"{label}-envelope",
                "composition": composition,
                "maximum_points": 240,
                "timeout_seconds": 20,
                "normalize_composition": False,
            },
        )
        assert envelope_response.status_code == 200
        envelope = envelope_response.json()
        assert envelope["is_available"] is True
        assert envelope["is_complete"] is True
        assert sum(1 for point in envelope["points"] if point["branch"] == "bubble") >= 2
        assert sum(1 for point in envelope["points"] if point["branch"] == "dew") >= 2
        assert all(point["pressure_pa"] > 0 and point["temperature_k"] > 0 for point in envelope["points"])

