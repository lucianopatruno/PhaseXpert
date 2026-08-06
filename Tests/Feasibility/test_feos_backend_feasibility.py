import json
import math
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "Scripts"))

import feos_backend_feasibility as feasibility


class FeOsBackendFeasibilityTests(unittest.TestCase):
    def test_core_co2_n2_cases_are_blocked_by_missing_bip(self):
        report = feasibility.generate_report()
        core = [
            result for result in report["case_results"]
            if result["case"] in {"co2-97-n2-3", "co2-90-n2-10"}
        ]
        self.assertEqual(len(core), 4)
        for result in core:
            self.assertEqual(result["status"], "blocked_missing_binary_interaction_parameters")
            self.assertEqual(result["attempted_points"], 0)
            self.assertIn("CO2/N2", result["termination_reason"])

    def test_pure_co2_parameter_is_recorded_but_not_benchmarked_without_cargo(self):
        report = feasibility.generate_report()
        pure = [result for result in report["case_results"] if result["case"] == "pure-co2"]
        self.assertEqual(len(pure), 2)
        for result in pure:
            self.assertTrue(result["parameter_status"]["pure_parameters_available"])
            self.assertEqual(result["status"], "not_run")
            self.assertIn("cargo/rustc are unavailable", result["termination_reason"])

    def test_no_fabricated_boundary_points_or_error_statistics(self):
        report = feasibility.generate_report()
        for result in report["case_results"]:
            self.assertEqual(result["attempted_points"], 0)
            self.assertEqual(result["converged_points"], 0)
            self.assertEqual(result["accepted_points"], 0)
            self.assertEqual(result["continuous_intervals"], [])
            self.assertEqual(result["gaps"], [])
            self.assertEqual(result["detached_segments"], [])
            self.assertEqual(result["pressure_error_relative"]["sample_count"], 0)

    def test_phase_xpert_component_pure_parameters_are_explicit(self):
        parameters = feasibility.ESPER2023_PURE_PARAMETERS
        for component in feasibility.PHASEXPERT_COMPONENTS:
            self.assertIn(component, parameters)
            self.assertIn("source", parameters[component])
        self.assertEqual(parameters["CO2"]["source"], "parameters/pcsaft/esper2023.json")
        self.assertEqual(parameters["H2"]["source"], "parameters/pcsaft/eller2022.json")

    def test_missing_binary_pairs_are_not_silently_zeroed(self):
        self.assertEqual(feasibility.missing_binary_pairs(("CO2", "N2")), ["CO2/N2"])
        self.assertEqual(feasibility.missing_binary_pairs(("CO2", "CH4")), [])
        self.assertIn(
            "CO2/N2",
            feasibility.generate_report()["model_selection"]["required_missing_binary_parameters"],
        )

    def test_invalid_inputs_are_rejected_before_feos(self):
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

    def test_native_api_findings_include_required_high_level_calls(self):
        api = feasibility.generate_report()["native_rust_api_findings"]
        self.assertIn("bubble_point", api["bubble_point_state"])
        self.assertIn("dew_point", api["dew_point_state"])
        self.assertIn("tp_flash", api["tp_flash"])
        self.assertIn("stability_analysis", api["stability"])
        self.assertIn("max_iter", api["solver_limits"])

    def test_deterministic_normalized_json(self):
        first = feasibility.normalized_json(feasibility.generate_report())
        second = feasibility.normalized_json(feasibility.generate_report())
        self.assertEqual(first, second)
        parsed = json.loads(first)
        self.assertEqual(parsed["feos_source"]["release"], feasibility.FEOS_TAG)
        self.assertEqual(parsed["feos_source"]["commit"], feasibility.FEOS_COMMIT)

    def test_json_contains_no_numeric_nonfinite_values(self):
        text = feasibility.normalized_json(feasibility.generate_report())
        self.assertNotIn("NaN", text)
        self.assertNotIn("Infinity", text)
        self.assertTrue(math.isfinite(len(text)))

    def test_classification_and_phase_four_stop(self):
        gates = feasibility.generate_report()["gates"]
        self.assertEqual(gates["classification"], "FeOs lacks the required parameters or component coverage")
        self.assertFalse(gates["phase_4_reached"])
        self.assertFalse(gates["ios_packaging_justified"])


if __name__ == "__main__":
    unittest.main()
