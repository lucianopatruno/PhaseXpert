#!/usr/bin/env python3
import json
import math
from pathlib import Path

root = Path(__file__).resolve().parents[1]
bakeoff = json.loads((root / "Documentation/Validation/AdvancedModelBakeoff2026-08-28.json").read_text())
density = json.loads((root / "Documentation/Validation/AdvancedDensityContinuousDomains2026-08-28.json").read_text())
phase = json.loads((root / "Documentation/Validation/AdvancedMulticomponentPhaseProduction2026-08-28.json").read_text())
coolprop = json.loads((root / "Documentation/Validation/GeneralPropertiesCoolPropDensityValidation2026-08-20.json").read_text())

assert bakeoff["baselineModel"]["engineCommit"] == "a68eb9cabf47af2c4aba0d272ac10fbca4c10eca"
assert bakeoff["productionDecision"]["status"] == "RETAIN CURRENT FORMULATION"
assert bakeoff["productionDecision"]["promotedCandidates"] == []
assert bakeoff["productionDecision"]["acceptedDomains"] == []
assert len(bakeoff["candidateModels"]) == 8
assert all(candidate["status"] in {"REJECT", "PROMISING — NEEDS MORE DATA"} for candidate in bakeoff["candidateModels"])

source_density = {entry["system"]: entry for entry in density["systems"]}
baseline_density = {entry["datasetID"]: entry for entry in bakeoff["baselineModel"]["densityEvidence"]}
assert math.isclose(baseline_density["Mazzoccoli2012-CO2-N2"]["aardPercent"], source_density["CO2+N2"]["statistics"]["aardPercent"])
assert math.isclose(baseline_density["Ghafri2016-CO2-CH4"]["aardPercent"], source_density["CO2+CH4"]["statistics"]["ghafriAardPercent"])
assert math.isclose(baseline_density["Souissi2017-CO2-H2"]["aardPercent"], source_density["CO2+H2"]["statistics"]["aardPercent"])
assert baseline_density["Razmjoo2026-dry-multicomponent"]["converged"] == source_density["dryMulticomponent"]["statistics"]["converged"]

source_phase = {entry["sourceID"]: entry for entry in phase["datasets"]}
baseline_vle = {entry["datasetID"]: entry for entry in bakeoff["baselineModel"]["vleEvidence"]}
assert baseline_vle["Theveneau2020-CO2-CH4-H2S"]["accepted"] == 0
assert source_phase["Ottoy2020"]["rows"] == 62
assert source_phase["KeGeorge2017"]["rows"] == 63

coolprop_candidate = next(candidate for candidate in bakeoff["candidateModels"] if candidate["candidateID"] == "coolprop-heos-8.0.0")
coolprop_metrics = {entry["datasetID"]: entry for entry in coolprop_candidate["densityEvidence"]}
assert math.isclose(coolprop_metrics["Mazzoccoli2012-CO2-N2"]["aardPercent"], coolprop["datasets"]["co2_n2_mazzoccoli"]["summaries"]["allRows"]["aardPercent"])
assert math.isclose(coolprop_metrics["Ghafri2016-CO2-CH4"]["aardPercent"], coolprop["datasets"]["co2_ch4_ghafri"]["summaries"]["allRows"]["aardPercent"])

integrity = bakeoff["scientificIntegrity"]
assert integrity["negativeResultsPreserved"] is True
assert all(value is False for key, value in integrity.items() if key != "negativeResultsPreserved")
print("Advanced model bake-off artifact validation passed: 8 candidates, no production promotion")
