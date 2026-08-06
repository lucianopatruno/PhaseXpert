import json
import math
import unittest
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "Scripts"))

import teqp_backend_feasibility as feasibility


class TeqpBackendFeasibilityTests(unittest.TestCase):
    def test_invalid_inputs_are_rejected_explicitly(self):
        reasons = {
            case.identifier: feasibility.validate_composition(case)["reason"]
            for case in feasibility.INVALID_CASES
        }
        self.assertEqual(reasons["invalid-empty"], "empty composition")
        self.assertEqual(reasons["invalid-negative"], "negative mole fraction")
        self.assertEqual(reasons["invalid-nonnormalized"], "composition is not normalized")
        self.assertEqual(reasons["invalid-duplicate"], "duplicate component")
        self.assertEqual(reasons["invalid-unsupported"], "unsupported component: Xe")
        self.assertEqual(reasons["invalid-nonfinite"], "non-finite mole fraction")
        self.assertEqual(reasons["invalid-out-of-domain"], "boundary-pinned composition")

    def test_safely_normalizable_input_is_not_silently_normalized(self):
        case = next(item for item in feasibility.ADDITIONAL_CASES if item.identifier == "safely-normalizable")
        validation = feasibility.validate_composition(case)
        self.assertTrue(validation["valid"])
        self.assertTrue(validation["requires_explicit_normalization"])
        self.assertEqual(list(case.mole_fractions), [0.9700000000000001, 0.03])

    def test_gerg2008_covers_required_named_components(self):
        models = {model["identifier"]: model for model in feasibility.model_support_matrix()}
        gerg = models["teqp-gerg2008resid"]
        self.assertEqual(gerg["supported_components"], feasibility.REQUIRED_COMPONENTS)
        for component in feasibility.REQUIRED_COMPONENTS:
            self.assertIn(component, feasibility.GERG2008_NAMES)

    def test_cubic_models_are_blocked_without_complete_bip_provenance(self):
        models = {model["identifier"]: model for model in feasibility.model_support_matrix()}
        self.assertEqual(models["teqp-canonical-srk"]["gate_status"], "required_parameters_absent")
        self.assertEqual(models["teqp-canonical-pr"]["gate_status"], "required_parameters_absent")
        self.assertIn("BIP", " ".join(models["teqp-canonical-srk"]["limitations"]))

    def test_multicomponent_cases_remain_multicomponent(self):
        report = feasibility.generate_report()
        multicomponent_cases = [
            case for case in report["cases"]
            if case["category"] == "additional" and len(case["components"]) >= 3
        ]
        self.assertGreaterEqual(len(multicomponent_cases), 3)
        self.assertTrue(all(len(case["components"]) >= 3 for case in multicomponent_cases))

    def test_no_fabricated_boundary_points_or_gap_bridging(self):
        report = feasibility.generate_report()
        for result in report["case_results"]:
            self.assertEqual(result["attempted_points"], 0)
            self.assertEqual(result["converged_points"], 0)
            self.assertEqual(result["accepted_points"], 0)
            self.assertEqual(result["continuous_coverage"], "none")
            self.assertEqual(result["gaps"], [])
            self.assertEqual(result["detached_segments"], [])
            self.assertIn("termination_reason", result)

    def test_statistics_are_restricted_to_genuine_boundary_intervals(self):
        report = feasibility.generate_report()
        for result in report["case_results"]:
            stats = result["pressure_error_relative"]
            self.assertEqual(stats["sample_count"], 0)
            self.assertIsNone(stats["mean"])
            self.assertIsNone(stats["median"])
            self.assertIsNone(stats["rms"])
            self.assertIsNone(stats["p95"])
            self.assertIsNone(stats["max"])
            self.assertEqual(stats["basis"], "no genuine continuous accepted boundary interval")

    def test_timeout_and_cancellation_limitations_are_explicit(self):
        safety = feasibility.generate_report()["runtime_and_safety"]
        self.assertIn("killable subprocess", safety["timeout_strategy"])
        self.assertIn("internal teqp call interruption was not established", safety["cancellation_strategy"])
        self.assertEqual(safety["complete_teqp_numerical_benchmark_runs"], 0)

    def test_deterministic_normalized_json(self):
        first = feasibility.normalized_json(feasibility.generate_report())
        second = feasibility.normalized_json(feasibility.generate_report())
        self.assertEqual(first, second)
        parsed = json.loads(first)
        self.assertEqual(parsed["teqp_source"]["release"], feasibility.TEQP_TAG)
        self.assertEqual(parsed["teqp_source"]["commit"], feasibility.TEQP_COMMIT)

    def test_json_rejects_nonfinite_values(self):
        report_text = feasibility.normalized_json(feasibility.generate_report())
        self.assertNotIn("NaN", report_text)
        self.assertNotIn("Infinity", report_text)
        self.assertTrue(math.isfinite(len(report_text)))

    def test_every_outcome_has_explicit_status(self):
        report = feasibility.generate_report()
        for result in report["case_results"]:
            self.assertTrue(result["status"])
            self.assertTrue(result["termination_reason"])
        self.assertEqual(
            report["gates"]["required_classification"],
            "teqp requires excessive PhaseXpert-owned solver development",
        )


if __name__ == "__main__":
    unittest.main()
