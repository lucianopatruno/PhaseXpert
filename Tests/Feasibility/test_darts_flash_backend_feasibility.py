import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "Scripts" / "darts_flash_backend_feasibility.py"


class DartsFlashBackendFeasibilityTests(unittest.TestCase):
    def generate(self, path: Path) -> dict:
        subprocess.run([sys.executable, str(SCRIPT), "--output", str(path)], check=True, cwd=REPO_ROOT)
        return json.loads(path.read_text(encoding="utf-8"))

    def test_report_is_deterministic(self):
        with tempfile.TemporaryDirectory() as tmp:
            first = Path(tmp) / "first.json"
            second = Path(tmp) / "second.json"
            self.generate(first)
            self.generate(second)
            self.assertEqual(first.read_bytes(), second.read_bytes())

    def test_pinned_dependency_is_immutable(self):
        with tempfile.TemporaryDirectory() as tmp:
            report = self.generate(Path(tmp) / "report.json")
        dependency = report["pinned_dependency"]
        self.assertEqual(dependency["release"], "v0.13.0")
        self.assertEqual(dependency["commit"], "acf1e12db4b82c779462a81d911ead0e254b963b")
        self.assertEqual(dependency["license"], "Apache-2.0")
        self.assertEqual(len(dependency["submodules"]), 2)

    def test_api_blocks_turnkey_boundary_claim(self):
        with tempfile.TemporaryDirectory() as tmp:
            report = self.generate(Path(tmp) / "report.json")
        api = report["api_findings"]
        self.assertTrue(api["pt_flash"])
        self.assertTrue(api["stability_analysis"])
        self.assertFalse(api["fixed_composition_pt_bubble_dew_envelope"])
        self.assertIn("bracketing", api["phase_boundary"])

    def test_core_results_do_not_fabricate_points(self):
        with tempfile.TemporaryDirectory() as tmp:
            report = self.generate(Path(tmp) / "report.json")
        for case in report["benchmark"]["core_results"]:
            for branch in case["branches"]:
                self.assertEqual(branch["attempted_points"], 0)
                self.assertEqual(branch["converged_points"], 0)
                self.assertEqual(branch["accepted_points"], 0)
                self.assertEqual(branch["continuous_intervals"], [])
                self.assertIsNone(branch["temperature_range_K"])
                self.assertIsNone(branch["relative_pressure_error"]["max"])
                self.assertIn("not_run", branch["termination_reason"])

    def test_component_coverage_records_phasexpert_gaps(self):
        with tempfile.TemporaryDirectory() as tmp:
            report = self.generate(Path(tmp) / "report.json")
        components = report["model_and_parameter_findings"]["component_support"]
        self.assertTrue(components["CO2"]["supported"])
        self.assertTrue(components["N2"]["supported"])
        self.assertFalse(components["O2"]["supported"])
        self.assertFalse(components["Ar"]["supported"])
        self.assertFalse(components["CO"]["supported"])

    def test_parameter_provenance_rejects_unverified_co2_n2_kij(self):
        with tempfile.TemporaryDirectory() as tmp:
            report = self.generate(Path(tmp) / "report.json")
        kij = report["model_and_parameter_findings"]["co2_n2_kij"]
        self.assertEqual(kij["value"], -0.0462)
        self.assertIsNone(kij["primary_source"])
        self.assertFalse(kij["usable_for_phasexpert_acceptance"])

    def test_scientific_and_apple_gates_are_not_claimed(self):
        with tempfile.TemporaryDirectory() as tmp:
            report = self.generate(Path(tmp) / "report.json")
        self.assertFalse(report["benchmark"]["actual_native_benchmark_ran"])
        self.assertFalse(report["apple_gate"]["reached"])
        self.assertEqual(
            report["primary_classification"],
            "DARTS-flash requires excessive PhaseXpert-owned solver development",
        )


if __name__ == "__main__":
    unittest.main()
