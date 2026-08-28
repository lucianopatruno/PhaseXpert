#!/usr/bin/env python3
"""Validate the committed negative ZMS 2023 identity and evidence decision."""

import json
import math
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
IDENTITY_PATH = ROOT / "Documentation/Validation/ZMS2023ModelIdentity.json"
RESULTS_PATH = ROOT / "Documentation/Validation/ZMS2023ValidationResults.json"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


identity = json.loads(IDENTITY_PATH.read_text())
results = json.loads(RESULTS_PATH.read_text())

require(identity["publication"]["doi"] == "10.3390/app13063659", "unexpected DOI")
require(identity["publication"]["authors"] == ["Jia Zhang", "Shide Mao", "Zeming Shi"], "unexpected authors")
require(identity["publication"]["license"] == "CC BY 4.0", "unexpected article license")
require(
    identity["acquisition"]["primaryReprintPDFSHA256"]
    == "eb86bd80535a6dae5e4dbd5c4baa813a27fe3a091ca3aa7f5f1bfd3af86f2057",
    "primary-source hash changed",
)
require(identity["acquisition"]["sourcePackageFound"] is False, "source package status changed")
require(identity["acquisition"]["sourceCodeLicense"] == "unknown; the article license does not establish a license for an unavailable source package", "source license was inferred")
require(identity["publishedFormulation"]["publishedPairCoefficientCount"] == 12, "pair coefficient count changed")
require(identity["publishedFormulation"]["referencedUniversalDepartureCoefficientCount"] == 30, "departure omission count changed")
require(identity["publishedFormulation"]["ternarySpecificTerms"] == 0, "unexpected ternary term")

expected_pairs = [
    ("CH4", "CO2", 1.2844025, 0.0035751245, -43.720344, 1.0358865),
    ("CO2", "N2", 1.6671494, 0.0058411078, -22.952094, 1.6878787),
    ("CH4", "N2", 0.63739997, 0.003812517, -17.790001, 1.009001),
]
actual_pairs = [
    (row["first"], row["second"], row["F"], row["zetaDm3PerMol"], row["varsigmaK"], row["beta"])
    for row in identity["binaryParameters"]
]
require(len(actual_pairs) == len(expected_pairs), "binary pair count changed")
for actual, expected in zip(actual_pairs, expected_pairs):
    require(actual[:2] == expected[:2], "component ordering changed")
    require(all(math.isclose(a, b, rel_tol=0.0, abs_tol=1e-12) for a, b in zip(actual[2:], expected[2:])), "published binary coefficient changed")

printed_temperatures = [row["printedTciK"] for row in identity["publishedCriticalTable"]]
require(printed_temperatures == [90.6941, 216.592, 63.151], "published critical-table contradiction changed")
require(identity["identityComplete"] is False, "incomplete identity marked complete")
require(identity["implementationAllowed"] is False, "implementation enabled without identity")
require(identity["verifiedNumericalCoefficientCount"] == 12, "verified coefficient count changed")
require(identity["missingOrAmbiguousNumericalCoefficientCount"] == 30, "missing coefficient count changed")

fitting = results["fittingDataAudit"]["ch4N2"]
require(fitting["pvtxSelectedRows"] == 433, "CH4/N2 PVTx fitting total changed")
require(fitting["vleSelectedRows"] == 270, "CH4/N2 VLE fitting total changed")
require(sum(row["fittingRows"] for row in fitting["datasets"] if row["property"] == "PVTx") == 433, "PVTx fitting rows do not sum")
require(sum(row["fittingRows"] for row in fitting["datasets"] if row["property"] == "VLE") == 270, "VLE fitting rows do not sum")
require(sum(row["rows"] for row in results["authorTernaryEvaluationInventory"]) == 839, "ternary evaluation inventory changed")

require(results["implementation"]["created"] is False, "unreviewed implementation recorded")
require(results["implementation"]["iosNativeChanges"] is False, "unexpected native change")
require(results["implementation"]["xcframeworkRebuilt"] is False, "unexpected framework rebuild")
require(results["implementation"]["multiModelRoutingImplemented"] is False, "unexpected routing change")
require(all(value is None for value in results["zmsMetrics"].values()), "fabricated ZMS metric present")
require(all(value is None for value in results["eoscgSameRowMetrics"].values()), "non-comparable EOS-CG metric present")
require(results["baselineUnchanged"] is True, "baseline marked changed")
require(results["productionPromotion"] is False, "unsupported production promotion")
require(all(value is False for key, value in results["scientificIntegrity"].items() if key != "negativeResultsPreserved"), "scientific-integrity violation")
require(results["scientificIntegrity"]["negativeResultsPreserved"] is True, "negative result not preserved")

print("ZMS 2023 identity/evidence audit: PASS (12 published pair coefficients locked; 30 referenced departure values unresolved; no implementation or promotion)")
