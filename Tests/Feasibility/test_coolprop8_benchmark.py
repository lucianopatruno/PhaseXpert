import unittest

from Scripts.coolprop8_benchmark import (
    compare_branch,
    duplicate_points,
    gaps_for,
    gate_decision,
    summarize_envelope,
    summarize_pt_flash,
)


class CoolProp8BenchmarkAnalysisTests(unittest.TestCase):
    def test_gap_detection_is_explicit(self):
        points = [
            {"temperature_k": 200.0, "pressure_pa": 1.0, "branch": "bubble"},
            {"temperature_k": 204.0, "pressure_pa": 2.0, "branch": "bubble"},
            {"temperature_k": 211.0, "pressure_pa": 3.0, "branch": "bubble"},
        ]

        self.assertEqual(
            gaps_for(points),
            [{"from_temperature_k": 204.0, "to_temperature_k": 211.0, "delta_k": 7.0}],
        )

    def test_comparison_uses_nearest_temperature_without_interpolation(self):
        candidate = [
            {"temperature_k": 100.4, "pressure_pa": 105.0, "branch": "dew"},
            {"temperature_k": 105.0, "pressure_pa": 400.0, "branch": "dew"},
        ]
        reference = [
            {"temperature_k": 100.0, "pressure_pa": 100.0, "branch": "dew"},
            {"temperature_k": 102.0, "pressure_pa": 200.0, "branch": "dew"},
        ]

        result = compare_branch(candidate, reference)

        self.assertEqual(result["matched_count"], 1)
        self.assertEqual(result["max_relative_pressure_error"], 0.05)

    def test_envelope_summary_rejects_nonfinite_and_counts_duplicates(self):
        raw = {
            "status": "returned",
            "is_complete": False,
            "is_closed": False,
            "points": [
                {"temperature_k": 200.0, "pressure_pa": 1.0, "branch": "bubble"},
                {"temperature_k": 200.0, "pressure_pa": 1.0, "branch": "bubble"},
                {"temperature_k": float("nan"), "pressure_pa": 2.0, "branch": "bubble"},
                {"temperature_k": 205.0, "pressure_pa": -1.0, "branch": "dew"},
            ],
        }

        summary = summarize_envelope(raw, None)

        self.assertEqual(summary["accepted_points"], 2)
        self.assertEqual(
            duplicate_points(summary["branches"]["bubble"]["last_accepted_point"] and [
                {"temperature_k": 200.0, "pressure_pa": 1.0, "branch": "bubble"},
                {"temperature_k": 200.0, "pressure_pa": 1.0, "branch": "bubble"},
            ]),
            [{"temperature_k": 200.0, "pressure_pa": 1.0}],
        )
        self.assertEqual(summary["branches"]["dew"]["accepted_points"], 0)

    def test_pt_flash_summary_does_not_relabel_samples_as_boundaries(self):
        raw = {
            "status": "returned",
            "samples": [
                {"status": "converged", "phase": "twophase"},
                {"status": "converged", "phase": "gas"},
                {"status": "failed"},
            ],
        }

        summary = summarize_pt_flash(raw)

        self.assertEqual(summary["attempted_samples"], 3)
        self.assertEqual(summary["converged_samples"], 2)
        self.assertEqual(summary["failed_samples"], 1)
        self.assertEqual(summary["phases"], ["gas", "twophase"])

    def test_gate_fails_when_no_backend_meets_branch_metrics(self):
        empty_branch = {
            "accepted_points": 0,
            "temperature_range_k": None,
            "pressure_range_pa": None,
            "gaps": [],
            "duplicates": [],
            "last_accepted_point": None,
            "comparison": {"max_relative_pressure_error": None},
        }
        critical_branch = dict(empty_branch)
        critical_branch["temperature_range_k"] = [300.0, 300.0]
        summaries = {}
        for backend in ["HEOS", "SRK", "PR"]:
            for case_id in ["pure-co2", "co2-97-n2-3", "co2-90-n2-10"]:
                summaries[f"{backend}:{case_id}"] = {
                    "status": "returned",
                    "branches": {
                        "bubble": dict(empty_branch),
                        "dew": dict(empty_branch),
                        "critical": dict(critical_branch),
                    },
                }

        critical_points = {
            f"{backend}:{case_id}": {
                "points": [{"temperature_k": 300.0, "stable": True}]
            }
            for backend in ["HEOS", "SRK", "PR"]
            for case_id in ["pure-co2", "co2-97-n2-3", "co2-90-n2-10"]
        }

        decision = gate_decision(summaries, critical_points)

        self.assertFalse(decision["passed"])
        self.assertFalse(decision["ios_packaging_justified"])


if __name__ == "__main__":
    unittest.main()
