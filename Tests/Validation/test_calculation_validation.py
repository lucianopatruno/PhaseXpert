import json
import base64
import subprocess
import sys
import tempfile
import unittest
from copy import deepcopy
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "Scripts" / "validate_calculations.py"
EXTRACT_SCRIPT = ROOT / "Scripts" / "extract_validation_observations.py"
MANIFEST = ROOT / "Documentation" / "Validation" / "CalculationReferenceManifest.json"


class CalculationValidationRunnerTests(unittest.TestCase):
    provider_fields = {
        "provider_id": "coolprop-heos",
        "provider_name": "CoolProp HEOS",
        "provider_version": "synthetic-provider-version",
        "model_version": "synthetic-model-version",
        "normalized_composition": [
            {
                "component": "co2",
                "mole_fraction": 1.0
            }
        ],
        "composition_basis": "mole_fraction"
    }

    def run_report(
        self,
        allow_incomplete: bool = True,
        observations: dict | None = None,
        manifest: dict | None = None
    ):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "results.json"
            manifest_path = MANIFEST
            if manifest is not None:
                manifest_path = Path(tmp) / "manifest.json"
                manifest_path.write_text(
                    json.dumps(manifest, sort_keys=True),
                    encoding="utf-8"
                )
            command = [sys.executable, str(SCRIPT), "--manifest", str(manifest_path), "--output", str(output)]
            if observations is not None:
                observations_path = Path(tmp) / "observations.json"
                observations_path.write_text(
                    json.dumps(observations, sort_keys=True),
                    encoding="utf-8"
                )
                command.extend(["--observations", str(observations_path)])
            if allow_incomplete:
                command.append("--allow-incomplete")
            result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
            return result, output.read_bytes() if output.exists() else b""

    def exact_observations(self, manifest: dict | None = None) -> dict:
        if manifest is None:
            manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
        points = []
        for index, point in enumerate(manifest["fixtures"]["pure_co2_density"]):
            points.append(
                {
                    "gate": "pure_co2_density",
                    "fixture_section": "pure_co2_density",
                    "fixture_index": index,
                    "reference_id": point["reference_id"],
                    "property": "density",
                    "input_temperature_k": point["temperature_k"],
                    "input_pressure_pa": point["pressure_pa"],
                    "status": "calculated",
                    "value": point["density_kg_m3"],
                    "unit": "kg/m³",
                    "phase": "synthetic",
                    **self.provider_fields
                }
            )
        for index, point in enumerate(manifest["fixtures"]["pure_co2_viscosity"]):
            points.append(
                {
                    "gate": "pure_co2_viscosity",
                    "fixture_section": "pure_co2_viscosity",
                    "fixture_index": index,
                    "reference_id": point["reference_id"],
                    "property": "dynamicViscosity",
                    "input_temperature_k": point["temperature_k"],
                    "input_pressure_pa": point["pressure_pa"],
                    "status": "calculated",
                    "value": point["viscosity_pa_s"],
                    "unit": "Pa·s",
                    "phase": "synthetic",
                    **self.provider_fields
                }
            )
        for index, point in enumerate(manifest["fixtures"]["critical_points"]):
            points.append(
                {
                    "gate": "pure_co2_critical_point",
                    "fixture_section": "critical_points",
                    "fixture_index": index,
                    "reference_id": point["reference_id"],
                    "property": "criticalPoint",
                    "input_temperature_k": None,
                    "input_pressure_pa": None,
                    "status": "calculated",
                    "value": None,
                    "unit": "K,Pa",
                    "phase": "critical",
                    "critical_temperature_k": point["temperature_k"],
                    "critical_pressure_pa": point["pressure_pa"],
                    **self.provider_fields
                }
            )
        for index, point in enumerate(manifest["fixtures"].get("pure_co2_saturation_pressure", [])):
            points.append(
                {
                    "gate": "pure_co2_saturation_pressure",
                    "fixture_section": "pure_co2_saturation_pressure",
                    "fixture_index": index,
                    "reference_id": point["reference_id"],
                    "property": "saturationPressure",
                    "input_temperature_k": point["temperature_k"],
                    "input_pressure_pa": point["pressure_pa"],
                    "status": "calculated",
                    "value": point["pressure_pa"],
                    "unit": "Pa",
                    "phase": "synthetic",
                    **self.provider_fields
                }
            )
        for index, point in enumerate(manifest["fixtures"]["co2_n2_density"]):
            points.append(
                {
                    "gate": "co2_n2_density",
                    "fixture_section": "co2_n2_density",
                    "fixture_index": index,
                    "reference_id": point["reference_id"],
                    "property": "density",
                    "input_temperature_k": point["temperature_k"],
                    "input_pressure_pa": point["pressure_pa"],
                    "status": "calculated",
                    "value": point["density_kg_m3"],
                    "unit": "kg/m³",
                    "phase": "synthetic",
                    **self.provider_fields
                }
            )
        return {
            "schema_version": "phasexpert-production-observations.v2",
            "metadata": {
                "source": "synthetic test observation fixture",
                "note": "Exercises runner accounting; not scientific evidence."
            },
            "points": points
        }

    def assert_gate_failed_after_observation_mutation(
        self,
        mutate,
        gate: str = "pure_co2_density"
    ):
        observations = self.exact_observations()
        mutate(observations)
        _, output = self.run_report(observations=observations)
        report = json.loads(output)
        self.assertEqual(report["gates"][gate]["status"], "failed")
        self.assertIn(
            f"{gate} gate is failed",
            report["strict_blockers"],
        )

    def all_passing_manifest(self) -> dict:
        manifest = deepcopy(json.loads(MANIFEST.read_text(encoding="utf-8")))
        manifest["fixtures"]["pure_co2_saturation_pressure"] = [
            {
                "reference_id": "pure-co2-saturation-pressure-needed",
                "region": "synthetic_runner_logic_only",
                "temperature_k": 280.0,
                "pressure_pa": 4_160_000.0,
                "absolute_tolerance_pa": 1_000.0
            }
        ]
        manifest["fixtures"]["co2_n2_density"] = [
            {
                "reference_id": "co2-n2-density-needed",
                "region": "synthetic_runner_logic_only",
                "temperature_k": 300.0,
                "pressure_pa": 10_000_000.0,
                "density_kg_m3": 500.0,
                "expanded_uncertainty_kg_m3": 0.5
            }
        ]
        return manifest

    def test_manifest_has_traceable_references_for_committed_pure_co2_points(self):
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
        references = {item["id"] for item in manifest["references"]}
        self.assertEqual(len(manifest["fixtures"]["pure_co2_density"]), 5)
        self.assertEqual(len(manifest["fixtures"]["pure_co2_viscosity"]), 9)
        self.assertEqual(len(manifest["fixtures"]["critical_points"]), 1)
        for section, points in manifest["fixtures"].items():
            for point in points:
                self.assertIn(point["reference_id"], references, section)

    def test_missing_required_evidence_fails_strict_gate(self):
        result, output = self.run_report(allow_incomplete=False)
        self.assertNotEqual(result.returncode, 0)
        report = json.loads(output)
        self.assertEqual(report["overall_scientific_gate"], "not_passed")
        self.assertIn(
            "co2_n2_density has no committed traceable reference points",
            report["manifest_failures"],
        )
        self.assertIn(
            "pure_co2_saturation_pressure gate is blocked",
            report["strict_blockers"],
        )
        self.assertIn(
            "pure_co2_density gate is runtime_observation_missing",
            report["strict_blockers"],
        )
        self.assertTrue(report["reason"].startswith("Required scientific gates are incomplete:"))

    def test_observations_record_aad_bias_maximum_deviation_and_failure_rate(self):
        _, output = self.run_report(observations=self.exact_observations())
        report = json.loads(output)
        density = report["gates"]["pure_co2_density"]
        viscosity = report["gates"]["pure_co2_viscosity"]

        self.assertEqual(density["status"], "passed")
        self.assertEqual(viscosity["status"], "passed")
        self.assertEqual(density["metrics"]["observed"], 5)
        self.assertEqual(viscosity["metrics"]["observed"], 9)
        self.assertEqual(density["metrics"]["mean_absolute_relative_deviation"], 0)
        self.assertEqual(density["metrics"]["bias_relative_deviation"], 0)
        self.assertEqual(density["metrics"]["maximum_absolute_relative_deviation"], 0)
        self.assertEqual(density["metrics"]["failure_rate"], 0)
        self.assertEqual(viscosity["metrics"]["failure_rate"], 0)
        self.assertEqual(report["gates"]["pure_co2_critical_point"]["status"], "passed")
        self.assertEqual(
            report["gates"]["pure_co2_critical_point"]["metrics"]["maximum_temperature_deviation_k"],
            0
        )
        self.assertEqual(
            report["gates"]["pure_co2_critical_point"]["metrics"]["maximum_relative_pressure_deviation"],
            0
        )

    def test_out_of_tolerance_observation_fails_its_gate(self):
        observations = self.exact_observations()
        observations["points"][0]["value"] = 1.0
        _, output = self.run_report(observations=observations)
        report = json.loads(output)

        self.assertEqual(report["gates"]["pure_co2_density"]["status"], "failed")
        self.assertGreater(report["gates"]["pure_co2_density"]["metrics"]["failure_rate"], 0)
        self.assertIn(
            "pure_co2_density gate is failed",
            report["strict_blockers"],
        )

    def test_missing_critical_observation_fails_critical_gate(self):
        observations = self.exact_observations()
        observations["points"] = [
            point for point in observations["points"]
            if point["gate"] != "pure_co2_critical_point"
        ]
        _, output = self.run_report(observations=observations)
        report = json.loads(output)

        self.assertEqual(report["gates"]["pure_co2_critical_point"]["status"], "failed")
        self.assertIn(
            "pure_co2_critical_point gate is failed",
            report["strict_blockers"],
        )

    def test_critical_temperature_outside_tolerance_fails_gate(self):
        observations = self.exact_observations()
        for point in observations["points"]:
            if point["gate"] == "pure_co2_critical_point":
                point["critical_temperature_k"] += 0.02
        _, output = self.run_report(observations=observations)
        report = json.loads(output)

        self.assertEqual(report["gates"]["pure_co2_critical_point"]["status"], "failed")

    def test_critical_pressure_outside_tolerance_fails_gate(self):
        observations = self.exact_observations()
        for point in observations["points"]:
            if point["gate"] == "pure_co2_critical_point":
                point["critical_pressure_pa"] *= 1.001
        _, output = self.run_report(observations=observations)
        report = json.loads(output)

        self.assertEqual(report["gates"]["pure_co2_critical_point"]["status"], "failed")

    def test_non_finite_critical_observation_fails_gate(self):
        observations = self.exact_observations()
        for point in observations["points"]:
            if point["gate"] == "pure_co2_critical_point":
                point["critical_temperature_k"] = "nan"
        _, output = self.run_report(observations=observations)
        report = json.loads(output)

        self.assertEqual(report["gates"]["pure_co2_critical_point"]["status"], "failed")

    def test_wrong_observation_schema_prevents_gate_pass(self):
        self.assert_gate_failed_after_observation_mutation(
            lambda observations: observations.update(
                {"schema_version": "phasexpert-production-observations.v1"}
            )
        )

    def test_wrong_provider_prevents_gate_pass(self):
        self.assert_gate_failed_after_observation_mutation(
            lambda observations: observations["points"][0].update(
                {"provider_id": "architecture-demo"}
            )
        )

    def test_wrong_property_prevents_gate_pass(self):
        self.assert_gate_failed_after_observation_mutation(
            lambda observations: observations["points"][0].update(
                {"property": "dynamicViscosity"}
            )
        )

    def test_wrong_unit_prevents_gate_pass(self):
        self.assert_gate_failed_after_observation_mutation(
            lambda observations: observations["points"][0].update(
                {"unit": "kg/m3"}
            )
        )

    def test_wrong_temperature_prevents_gate_pass(self):
        self.assert_gate_failed_after_observation_mutation(
            lambda observations: observations["points"][0].update(
                {"input_temperature_k": 999.0}
            )
        )

    def test_wrong_pressure_prevents_gate_pass(self):
        self.assert_gate_failed_after_observation_mutation(
            lambda observations: observations["points"][0].update(
                {"input_pressure_pa": 999.0}
            )
        )

    def test_wrong_composition_prevents_gate_pass(self):
        self.assert_gate_failed_after_observation_mutation(
            lambda observations: observations["points"][0].update(
                {
                    "normalized_composition": [
                        {"component": "co2", "mole_fraction": 0.999},
                        {"component": "n2", "mole_fraction": 0.001}
                    ]
                }
            )
        )

    def test_wrong_reference_id_prevents_gate_pass(self):
        self.assert_gate_failed_after_observation_mutation(
            lambda observations: observations["points"][0].update(
                {"reference_id": "wrong-reference"}
            )
        )

    def test_duplicate_observation_prevents_gate_pass(self):
        self.assert_gate_failed_after_observation_mutation(
            lambda observations: observations["points"].append(
                dict(observations["points"][0])
            )
        )

    def test_missing_observation_prevents_gate_pass(self):
        self.assert_gate_failed_after_observation_mutation(
            lambda observations: observations["points"].pop(0)
        )

    def test_non_finite_value_prevents_gate_pass(self):
        self.assert_gate_failed_after_observation_mutation(
            lambda observations: observations["points"][0].update(
                {"value": "NaN"}
            )
        )

    def test_extract_observation_payload_writes_canonical_json(self):
        observations = self.exact_observations()
        payload = base64.b64encode(
            json.dumps(observations, sort_keys=True).encode("utf-8")
        ).decode("ascii")
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "xcode.log"
            output = Path(tmp) / "observations.json"
            log.write_text(
                "before\nPHASEXPERT_VALIDATION_OBSERVATIONS_BASE64="
                + payload
                + "\nafter\n",
                encoding="utf-8"
            )
            result = subprocess.run(
                [sys.executable, str(EXTRACT_SCRIPT), str(log), str(output)],
                cwd=ROOT,
                text=True,
                capture_output=True
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(output.read_text(encoding="utf-8")), observations)

    def test_extract_observation_payload_rejects_missing_duplicate_and_invalid_payloads(self):
        observations = self.exact_observations()
        payload = base64.b64encode(
            json.dumps(observations, sort_keys=True).encode("utf-8")
        ).decode("ascii")
        cases = [
            "no payload here",
            (
                "PHASEXPERT_VALIDATION_OBSERVATIONS_BASE64="
                + payload
                + "\nPHASEXPERT_VALIDATION_OBSERVATIONS_BASE64="
                + payload
            ),
            "PHASEXPERT_VALIDATION_OBSERVATIONS_BASE64=not-base64"
        ]
        with tempfile.TemporaryDirectory() as tmp:
            for index, content in enumerate(cases):
                log = Path(tmp) / f"xcode-{index}.log"
                output = Path(tmp) / f"observations-{index}.json"
                log.write_text(content, encoding="utf-8")
                result = subprocess.run(
                    [sys.executable, str(EXTRACT_SCRIPT), str(log), str(output)],
                    cwd=ROOT,
                    text=True,
                    capture_output=True
                )
                self.assertNotEqual(result.returncode, 0, content)
                self.assertFalse(output.exists())

    def test_synthetic_all_passing_configuration_returns_zero_strict_exit(self):
        manifest = self.all_passing_manifest()
        observations = self.exact_observations(manifest=manifest)
        result, output = self.run_report(
            allow_incomplete=False,
            observations=observations,
            manifest=manifest
        )
        report = json.loads(output)

        self.assertEqual(result.returncode, 0)
        self.assertEqual(report["overall_scientific_gate"], "passed")
        self.assertEqual(report["strict_blockers"], [])

    def test_allow_incomplete_never_changes_scientific_gate_result(self):
        strict_result, strict_output = self.run_report(allow_incomplete=False)
        incomplete_result, incomplete_output = self.run_report(allow_incomplete=True)
        strict_report = json.loads(strict_output)
        incomplete_report = json.loads(incomplete_output)

        self.assertNotEqual(strict_result.returncode, 0)
        self.assertEqual(incomplete_result.returncode, 0)
        self.assertEqual(
            strict_report["overall_scientific_gate"],
            incomplete_report["overall_scientific_gate"]
        )
        self.assertEqual(
            strict_report["strict_blockers"],
            incomplete_report["strict_blockers"]
        )

    def test_report_is_deterministic(self):
        first_result, first = self.run_report()
        second_result, second = self.run_report()
        self.assertEqual(first_result.returncode, 0)
        self.assertEqual(second_result.returncode, 0)
        self.assertEqual(first, second)

    def test_unavailable_capabilities_are_explicit(self):
        _, output = self.run_report()
        report = json.loads(output)
        matrix = report["validated_range_matrix"]
        self.assertEqual(matrix["co2_n2_viscosity"], "unavailable")
        self.assertEqual(matrix["multicomponent_phase_diagrams"], "unavailable")
        self.assertEqual(report["gates"]["pure_co2_saturation_pressure"]["status"], "blocked")


if __name__ == "__main__":
    unittest.main()
