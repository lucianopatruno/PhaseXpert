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
    def run_report(self, allow_incomplete: bool = True):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "results.json"
            command = [sys.executable, str(SCRIPT), "--manifest", str(MANIFEST), "--output", str(output)]
            if allow_incomplete:
                command.append("--allow-incomplete")
            result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
            return result, output.read_bytes() if output.exists() else b""

    def test_manifest_has_traceable_references_for_committed_pure_co2_points(self):
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
        references = {item["id"] for item in manifest["references"]}
        self.assertEqual(len(manifest["fixtures"]["pure_co2_density"]), 5)
        self.assertEqual(len(manifest["fixtures"]["pure_co2_viscosity"]), 9)
        self.assertEqual(len(manifest["fixtures"]["critical_points"]), 1)
        for section, points in manifest["fixtures"].items():
            for point in points:
                self.assertIn(point["reference_id"], references, section)

    def test_missing_co2_n2_density_fixture_fails_strict_gate(self):
        result, output = self.run_report(allow_incomplete=False)
        self.assertNotEqual(result.returncode, 0)
        report = json.loads(output)
        self.assertEqual(report["overall_scientific_gate"], "not_passed")
        self.assertIn(
            "co2_n2_density has no committed traceable reference points",
            report["manifest_failures"],
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
