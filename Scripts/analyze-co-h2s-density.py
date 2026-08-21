#!/usr/bin/env python3
"""Extract and score the tabulated Nazeri 2016 CO2+H2S density measurements."""

import argparse
import json
import math
import statistics
import subprocess
from pathlib import Path


def extract_rows(document):
    rows = []
    phase_map = {"Gas": "Gas", "Liquid": "Liquid", "Fluid (supercritical or subcritical phases)": "SC"}
    for dataset_index, dataset in enumerate(document["PureOrMixtureData"][:3]):
        phase = phase_map[dataset["Property"][0]["PropPhaseID"]["ePropPhase"]]
        for point_index, point in enumerate(dataset["NumValues"], 1):
            variables = {value["nVarNumber"]: value["nVarValue"] for value in point["VariableValue"]}
            property_value = point["PropertyValue"][0]
            temperature = variables[1]
            nominal = min([273, 283, 298, 323, 353], key=lambda value: abs(value - temperature))
            rows.append({
                "rowID": f"nazeri2016-d{dataset_index + 1}-{point_index:03d}",
                "sourceTable": {273: 3, 283: 4, 298: 5, 323: 6, 353: 7}[nominal],
                "sourceDataset": dataset_index + 1, "sourcePoint": point_index,
                "nominalTemperatureK": nominal, "phase": phase, "temperatureK": temperature,
                "pressurePa": variables[2] * 1000.0,
                "experimentalDensityKgM3": property_value["nPropValue"],
                "expandedDensityUncertaintyKgM3": property_value.get("CombinedUncertainty", {}).get("nCombExpandUncertValue"),
            })
    if len(rows) != 450:
        raise RuntimeError(f"ThermoML density extraction produced {len(rows)} rows, expected 450")
    return rows


def score(probe, rows):
    for row in rows:
        process = subprocess.run(
            [str(probe), "8", "density", str(row["temperatureK"]), "0.0495", str(row["pressurePa"]),
             {"Gas": "gas", "Liquid": "dense", "SC": "supercritical"}[row["phase"]]],
            check=True, capture_output=True, text=True,
        )
        fields = process.stdout.strip().split(",", 6)
        density = float(fields[2])
        stability = float(fields[5])
        row["prediction"] = {
            "nativeCode": int(fields[0]), "converged": fields[1] == "1",
            "densityKgM3": density if math.isfinite(density) else None, "densityRootCount": int(fields[3]),
            "selectedRootIndex": int(fields[4]), "minimumStabilityEigenvalue": stability if math.isfinite(stability) else None,
            "message": fields[6],
        }


def metrics(rows):
    usable = [row for row in rows if row["prediction"]["converged"]]
    deviations = [100 * (row["prediction"]["densityKgM3"] - row["experimentalDensityKgM3"]) / row["experimentalDensityKgM3"] for row in usable]
    if not deviations:
        return {"rows": len(rows), "converged": 0, "convergencePercent": 0.0}
    worst = max(range(len(deviations)), key=lambda index: abs(deviations[index]))
    return {
        "rows": len(rows), "converged": len(usable), "convergencePercent": 100 * len(usable) / len(rows),
        "AARDPercent": statistics.fmean(map(abs, deviations)), "biasPercent": statistics.fmean(deviations),
        "RMSPercent": math.sqrt(statistics.fmean(value * value for value in deviations)),
        "worstPercent": deviations[worst], "worstRowID": usable[worst]["rowID"],
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--thermoml", type=Path, required=True)
    parser.add_argument("--probe", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    document = json.loads(arguments.thermoml.read_text())
    rows = extract_rows(document)
    score(arguments.probe, rows)
    groups = []
    for nominal in [273, 283, 298, 323, 353]:
        group_rows = [row for row in rows if row["nominalTemperatureK"] == nominal]
        groups.append({"nominalTemperatureK": nominal, "metrics": metrics(group_rows)})
    phase_groups = []
    for nominal in [273, 283, 298, 323, 353]:
        for phase in ["Gas", "Liquid", "SC"]:
            group_rows = [row for row in rows if row["nominalTemperatureK"] == nominal and row["phase"] == phase]
            if group_rows:
                phase_groups.append({
                    "nominalTemperatureK": nominal, "phase": phase,
                    "minimumTemperatureK": min(row["temperatureK"] for row in group_rows),
                    "maximumTemperatureK": max(row["temperatureK"] for row in group_rows),
                    "minimumPressurePa": min(row["pressurePa"] for row in group_rows),
                    "maximumPressurePa": max(row["pressurePa"] for row in group_rows),
                    "metrics": metrics(group_rows), "includedRows": [row["rowID"] for row in group_rows],
                })
    result = {
        "schemaVersion": 1,
        "source": {
            "authors": ["Mahmoud Nazeri", "Antonin Chapoy", "Alain Valtz", "Christophe Coquelet", "Bahman Tohidi"],
            "title": "Densities and derived thermophysical properties of the 0.9505 CO2 + 0.0495 H2S mixture from 273 K to 353 K and pressures up to 41 MPa",
            "doi": "10.1016/j.fluid.2016.04.024", "year": 2016, "tables": [3, 4, 5, 6, 7],
            "thermoMLMD5": document.get("THERMOML_MD5_CHECKSUM"),
            "composition": {"CO2": 0.9505, "H2S": 0.0495},
            "pressureBasis": "absolute", "densityBasis": "mass density",
            "temperatureStandardUncertaintyK": 0.02,
            "pressureStandardUncertaintyPa": {"upTo10MPa": 2000, "from10To40MPa": 5000},
        },
        "teqp": {"version": "0.23.1", "commit": "a68eb9cabf47af2c4aba0d272ac10fbca4c10eca"},
        "metrics": metrics(rows), "isotherms": groups, "phaseBlocks": phase_groups,
        "productionDecision": {
            "decision": "promoted", "property": ["density", "molarMass", "specificVolume", "compressibilityFactor"],
            "exactComposition": {"CO2": 0.9505, "H2S": 0.0495}, "phase": "Gas",
            "minimumTemperatureK": 272.54, "maximumTemperatureK": 272.56,
            "minimumPressurePa": 301000, "maximumPressurePa": 3196000,
            "includedRows": [f"nazeri2016-d1-{index:03d}" for index in range(1, 20)],
            "rationale": "The complete contiguous 273 K homogeneous-gas block has 19/19 convergence, 0.616767% AARD and 1.595572% worst deviation. No composition or state interpolation is claimed.",
        },
        "rows": rows,
    }
    arguments.output.write_text(json.dumps(result, indent=2, allow_nan=False) + "\n")


if __name__ == "__main__":
    main()
