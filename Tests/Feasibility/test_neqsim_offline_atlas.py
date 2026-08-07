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
        self.assertEqual(len(self.module.locked_reference_compositions()), 45)
        self.assertIn(0.000025, self.module.locked_reference_compositions())
        self.assertIn(0.0025, self.module.locked_reference_compositions())
        self.assertIn(0.098125, self.module.locked_reference_compositions())
        self.assertEqual(self.module.grid_nodes(0.01), [round(i * 0.01, 8) for i in range(11)])
        self.assertEqual(self.report["composition_matrix"]["total_generated_compositions"], 86)
        self.assertEqual(self.report["composition_matrix"]["locked_generated_compositions"], 45)

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
                self.assertIn(branch, record["segments"])

    def test_topology_descriptors_preserve_missing_bubble_branch(self):
        near_pure = next(record for record in self.report["atlas"]["records"] if record["x_n2"] == 0.00001)
        self.assertEqual(near_pure["branches"]["bubble"], [])
        self.assertEqual(near_pure["segments"]["bubble"], [])
        descriptors = self.report["topology_descriptors"]["atlas_records"][str(near_pure["x_n2"])]
        self.assertEqual(descriptors["bubble"], [])

    def test_critical_field_semantics_are_explicit(self):
        audit = self.report["validation"]["failure_audit"]
        self.assertFalse(audit["validation_defect_found"])
        self.assertIn("criticalPoint1", audit["critical_semantics"])
        self.assertIn("not cricondentherm", audit["critical_semantics"])
        self.assertEqual(audit["relative_error_units"], "fraction; multiply by 100 for percent")

    def test_direct_interpolation_failure_is_explicit(self):
        self.assertEqual(self.report["validation"]["failure_audit"]["validation_defect_found"], False)
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

    def test_topology_aligned_locked_validation_fails_explicitly(self):
        self.assertEqual(
            self.report["classification"],
            "NeqSim's envelope topology is too unstable for reliable general interpolation.",
        )
        for method in self.report["validation"]["topology"]["locked_set"].values():
            for grid in method.values():
                self.assertFalse(grid["passes_scientific_gate"])
                for branch in ("bubble", "dew"):
                    branch_report = grid["branches"][branch]
                    self.assertEqual(branch_report["false_connections"], 0)
                    self.assertEqual(branch_report["branch_swaps"], 0)
                    self.assertEqual(branch_report["invalid_results"], 0)
                    self.assertLess(branch_report["coverage_fraction"], 0.95)
                    self.assertGreater(branch_report["topology_refusals"], 0)

    def test_endpoint_and_critical_outliers_are_recorded(self):
        outliers = self.report["validation"]["failure_audit"]["outliers"]
        self.assertEqual(outliers["0.25_percent"]["bubble"][0]["location"], "low_temperature_endpoint")
        self.assertGreater(outliers["0.25_percent"]["critical"][0]["temperature_error_K"], 50.0)
        self.assertEqual(outliers["0.25_percent"]["bubble"][0]["relative_pressure_error_fraction"], 42.332306131024)

    def test_timeout_worker_is_killed_and_restarted(self):
        worker_source = (
            "import json, sys, time\n"
            "print(json.dumps({'worker':'ready'}), flush=True)\n"
            "for line in sys.stdin:\n"
            "    req=json.loads(line)\n"
            "    if req.get('command') == 'stop': break\n"
            "    time.sleep(10)\n"
        )
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "slow_worker.py"
            path.write_text(worker_source, encoding="utf-8")
            worker = self.module.NeqSimWorker("python3", "", deadline_s=0.05, worker_script=str(path))
            try:
                result = worker.evaluate(0.001)
                self.assertEqual(result["status"], "timeout")
                self.assertEqual(worker.restarts, 1)
                self.assertIsNotNone(worker.process)
                self.assertIsNone(worker.process.poll())
            finally:
                worker.close()
            self.assertIsNotNone(worker.process)
            self.assertIsNotNone(worker.process.poll())

    def test_scientific_json_is_canonical(self):
        canonical = self.module.canonical_dumps(self.report)
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "report.json"
            path.write_text(json.dumps(self.report, indent=2, sort_keys=True, allow_nan=False) + "\n", encoding="utf-8")
            reread = json.loads(path.read_text(encoding="utf-8"))
        self.assertEqual(canonical, self.module.canonical_dumps(reread))


if __name__ == "__main__":
    unittest.main()
