import importlib.util
import json
import math
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "Scripts" / "NeqSimOfflineAtlasPrototype" / "neqsim_offline_atlas.py"
RESULTS = REPO_ROOT / "Documentation" / "Feasibility" / "NeqSimOfflineAtlasResults.json"


def load_module():
    spec = importlib.util.spec_from_file_location("neqsim_offline_atlas", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class NeqSimOfflineAtlasTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.module = load_module()
        cls.report = json.loads(RESULTS.read_text(encoding="utf-8"))

    def test_reference_matrix_is_bounded_and_predetermined(self):
        refs = self.module.main_reference_compositions()
        self.assertEqual(len(refs), 81)
        self.assertEqual(refs[0], 0.0)
        self.assertEqual(refs[-1], 0.1)
        self.assertEqual(self.module.grid_nodes(0.01), [round(i * 0.01, 8) for i in range(11)])
        self.assertEqual(self.report["composition_matrix"]["total_generated_compositions"], 86)

    def test_invalid_compositions_are_rejected(self):
        for value in [math.nan, math.inf, -0.001, 0.100001]:
            with self.assertRaises(ValueError):
                self.module.validate_x_n2(value)

    def test_provenance_pins_neqsim_and_interaction_row(self):
        provenance = self.report["provenance"]
        self.assertEqual(provenance["neqsim_release"], "3.16.0")
        self.assertEqual(provenance["neqsim_source_commit"], "3af7b560525b57f2d3da2c803a08e2b41a8d7f5a")
        parameter = provenance["model"]["co2_n2_binary_interaction_parameter"]
        self.assertEqual(parameter["KIJSRK"], -0.0171)
        self.assertEqual(parameter["KIJTSRK"], 0.0)

    def test_generated_envelopes_are_finite_and_branch_preserving(self):
        for record in self.report["atlas"]["records"]:
            self.assertEqual(record["status"], "converged")
            self.assertGreater(
                len(record["branches"]["bubble"]) + len(record["branches"]["dew"]),
                0,
            )
            for branch in ("bubble", "dew"):
                for point in record["branches"][branch]:
                    self.assertGreater(point["temperature_k"], 0)
                    self.assertGreater(point["pressure_pa"], 0)

    def test_direct_interpolation_failure_is_explicit(self):
        self.assertEqual(self.report["classification"], "Interpolation fails the scientific gate.")
        for grid in self.report["validation"]["grids"].values():
            for branch in ("bubble", "dew"):
                branch_report = grid["branches"][branch]
                self.assertEqual(branch_report["false_connections"], 0)
                self.assertEqual(branch_report["branch_swaps"], 0)
                self.assertEqual(branch_report["invalid_results"], 0)
                self.assertEqual(branch_report["coverage_fraction"], 1.0)
            self.assertGreater(grid["branches"]["bubble"]["relative_pressure_error"]["max"], 0.005)

    def test_branch_aligned_alternative_is_rejected(self):
        for grid in self.report["validation"]["branch_aligned_alternative"].values():
            self.assertEqual(grid["result"], "rejected: pressure errors exceed the scientific gate")
            self.assertGreater(grid["branches"]["bubble"]["relative_pressure_error"]["max"], 0.005)

    def test_scientific_json_is_canonical(self):
        canonical = self.module.canonical_dumps(self.report)
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "report.json"
            path.write_text(json.dumps(self.report, indent=2, sort_keys=True, allow_nan=False) + "\n", encoding="utf-8")
            reread = json.loads(path.read_text(encoding="utf-8"))
        self.assertEqual(canonical, self.module.canonical_dumps(reread))


if __name__ == "__main__":
    unittest.main()
