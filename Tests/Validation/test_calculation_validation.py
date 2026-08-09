import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "Scripts" / "validate_calculations.py"
MANIFEST = ROOT / "Documentation" / "Validation" / "CalculationReferenceManifest.json"


class CalculationValidationRunnerTests(unittest.TestCase):
    def run_report(self, allow_incomplete: bool = True, observations: dict | None = None):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "results.json"
            command = [sys.executable, str(SCRIPT), "--manifest", str(MANIFEST), "--output", str(output)]
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

    def exact_observations(self) -> dict:
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
        points = []
        for index, point in enumerate(manifest["fixtures"]["pure_co2_density"]):
            points.append(
                {
                    "gate": "pure_co2_density",
                    "fixture_section": "pure_co2_density",
                    "fixture_index": index,
                    "property": "density",
                    "status": "calculated",
                    "value": point["density_kg_m3"],
                    "unit": "kg/m3"
                }
            )
        for index, point in enumerate(manifest["fixtures"]["pure_co2_viscosity"]):
            points.append(
                {
                    "gate": "pure_co2_viscosity",
                    "fixture_section": "pure_co2_viscosity",
                    "fixture_index": index,
                    "property": "dynamicViscosity",
                    "status": "calculated",
                    "value": point["viscosity_pa_s"],
                    "unit": "Pa*s"
                }
            )
        return {
            "schema_version": "phasexpert-production-observations.v1",
            "metadata": {
                "source": "synthetic test observation fixture",
                "note": "Exercises runner accounting; not scientific evidence."
            },
            "points": points
        }

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
        self.assertIn(
            "pure_co2_critical_point gate is runtime_observation_missing",
            report["strict_blockers"],
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
