from fastapi.testclient import TestClient

from neqsim_provider.contracts import INTERACTION_DATA_ID
from neqsim_provider.main import app


def test_health_reports_pinned_identity():
    response = TestClient(app).get("/v1/health")

    assert response.status_code == 200
    body = response.json()
    assert body["provider_id"] == "neqsim-remote-srk-classic"
    assert body["neqsim_version"] == "3.16.0"
    assert body["neqsim_source_commit"] == "3af7b560525b57f2d3da2c803a08e2b41a8d7f5a"
    assert body["eos"] == "SystemSrkEos"
    assert body["mixing_rule"] == "classic"
    assert body["interaction_data"] == INTERACTION_DATA_ID


def test_duplicate_components_are_rejected_before_neqsim_execution():
    response = TestClient(app).post(
        "/v1/state",
        json={
            "schema_version": "neqsim-provider.v1",
            "request_id": "duplicate-test",
            "pressure_pa": 1000000.0,
            "temperature_k": 293.15,
            "composition": [
                {"component": "co2", "mole_fraction": 0.5},
                {"component": "co2", "mole_fraction": 0.5},
            ],
            "requested_properties": ["density"],
            "client_version": "test",
        },
    )

    assert response.status_code == 422
