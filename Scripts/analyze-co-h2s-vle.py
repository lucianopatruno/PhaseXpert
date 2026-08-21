#!/usr/bin/env python3
"""Reproduce the CO2+CO and CO2+H2S ThermoML VLE validation artifacts."""

import argparse
import json
import math
import statistics
import subprocess
from collections import defaultdict
from pathlib import Path


SOURCES = {
    "westman2018": {
        "doi": "10.1016/j.fluid.2018.05.006", "component": "CO",
        "component_id": 7, "pressure_dataset": 0, "opposite_dataset": 1,
        "temperature_variable": 2, "composition_variable": 1,
        "composition_component": "CO2",
    },
    "chapoy2020": {
        "doi": "10.1016/j.jct.2020.106180", "component": "CO",
        "component_id": 7, "pressure_dataset": 1, "opposite_dataset": 2,
        "temperature_variable": 2, "composition_variable": 1,
        "composition_component": "component2",
    },
    "souza2018": {
        "doi": "10.1016/j.jct.2018.06.022", "component": "CO",
        "component_id": 7, "pressure_dataset": 1, "opposite_dataset": 2,
        "temperature_variable": 2, "composition_variable": 1,
        "composition_component": "component2",
    },
    "chapoy2013": {
        "doi": "10.1016/j.fluid.2013.07.050", "component": "H2S",
        "component_id": 8, "pressure_dataset": 0, "opposite_dataset": 1,
        "temperature_variable": 1, "composition_variable": 2,
        "composition_component": "CO2",
    },
}


def numbered(values, number):
    return next(value for value in values if value["nVarNumber"] == number)["nVarValue"]


def measured_rows(source_id, path):
    definition = SOURCES[source_id]
    document = json.loads(path.read_text())
    pressure_rows = document["PureOrMixtureData"][definition["pressure_dataset"]]["NumValues"]
    opposite_rows = document["PureOrMixtureData"][definition["opposite_dataset"]]["NumValues"]
    rows = []
    for index, pressure_row in enumerate(pressure_rows):
        variables = pressure_row["VariableValue"]
        temperature = numbered(variables, definition["temperature_variable"])
        specified_value = numbered(variables, definition["composition_variable"])
        component2_liquid = specified_value if definition["composition_component"] == "component2" else 1.0 - specified_value
        pressure_value = pressure_row["PropertyValue"][0]
        opposite = opposite_rows[index]["PropertyValue"][0]["nPropValue"] if index < len(opposite_rows) else None
        component2_vapor = opposite if definition["composition_component"] == "component2" else (None if opposite is None else 1.0 - opposite)
        rows.append({
            "rowID": f"{source_id}-{index + 1:02d}",
            "temperatureK": temperature,
            "liquidComponent2MoleFraction": component2_liquid,
            "vaporComponent2MoleFraction": component2_vapor,
            "experimentalPressurePa": pressure_value["nPropValue"] * 1000.0,
            "expandedPressureUncertaintyPa": pressure_value.get("CombinedUncertainty", {}).get("nCombExpandUncertValue", 0.0) * 1000.0,
        })
    return document, rows


def probe(executable, component_id, observable, temperature, component2):
    process = subprocess.run(
        [str(executable), str(component_id), observable, str(temperature), str(component2)],
        check=True, capture_output=True, text=True,
    )
    fields = process.stdout.strip().split(",", 9)
    return {
        "nativeCode": int(fields[0]), "converged": fields[1] == "1", "status": int(fields[2]),
        "predictedPressurePa": float(fields[3]), "predictedLiquidComponent2MoleFraction": float(fields[4]),
        "predictedVaporComponent2MoleFraction": float(fields[5]), "liquidStabilityEigenvalue": float(fields[6]),
        "vaporStabilityEigenvalue": float(fields[7]), "iterations": int(fields[8]), "message": fields[9],
    }


def metrics(rows, observable):
    usable = [row for row in rows if row[observable]["converged"]]
    pressure_errors = [100.0 * (row[observable]["predictedPressurePa"] - row["experimentalPressurePa"]) / row["experimentalPressurePa"] for row in usable]
    if observable == "bubble":
        composition_errors = [row[observable]["predictedVaporComponent2MoleFraction"] - row["vaporComponent2MoleFraction"] for row in usable]
    else:
        composition_errors = [row[observable]["predictedLiquidComponent2MoleFraction"] - row["liquidComponent2MoleFraction"] for row in usable]
    if not usable:
        return {"rows": len(rows), "converged": 0, "convergencePercent": 0.0}
    worst_index = max(range(len(pressure_errors)), key=lambda index: abs(pressure_errors[index]))
    return {
        "rows": len(rows), "converged": len(usable), "convergencePercent": 100.0 * len(usable) / len(rows),
        "pressureAARDPercent": statistics.fmean(map(abs, pressure_errors)),
        "pressureBiasPercent": statistics.fmean(pressure_errors),
        "pressureRMSPercent": math.sqrt(statistics.fmean(value * value for value in pressure_errors)),
        "pressureWorstPercent": pressure_errors[worst_index], "pressureWorstRowID": usable[worst_index]["rowID"],
        "oppositeCompositionMAE": statistics.fmean(map(abs, composition_errors)),
        "oppositeCompositionBias": statistics.fmean(composition_errors),
        "oppositeCompositionRMS": math.sqrt(statistics.fmean(value * value for value in composition_errors)),
        "oppositeCompositionWorstAbsolute": max(map(abs, composition_errors)),
        "stabilityRejections": sum(1 for row in rows if row[observable]["status"] == 6),
        "otherFailures": sum(1 for row in rows if not row[observable]["converged"] and row[observable]["status"] != 6),
    }


def isotherm_metrics(rows):
    groups = defaultdict(list)
    for row in rows:
        groups[round(row["temperatureK"], 1)].append(row)
    return [
        {
            "nominalTemperatureK": temperature,
            "bubbleMetrics": metrics(group, "bubble"),
            "dewMetrics": metrics(group, "dew"),
            "includedRows": [row["rowID"] for row in group],
        }
        for temperature, group in sorted(groups.items())
    ]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--probe", type=Path, required=True)
    parser.add_argument("--source", action="append", nargs=2, metavar=("SOURCE_ID", "THERMOML_JSON"), required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    result = {"schemaVersion": 1, "teqp": {"version": "0.23.1", "commit": "a68eb9cabf47af2c4aba0d272ac10fbca4c10eca"}, "sources": []}
    for source_id, source_path in arguments.source:
        definition = SOURCES[source_id]
        document, rows = measured_rows(source_id, Path(source_path))
        scored = []
        for row in rows:
            if row["vaporComponent2MoleFraction"] is None or min(row["liquidComponent2MoleFraction"], row["vaporComponent2MoleFraction"]) <= 0.0 or max(row["liquidComponent2MoleFraction"], row["vaporComponent2MoleFraction"]) >= 1.0:
                continue
            row["bubble"] = probe(arguments.probe, definition["component_id"], "bubble", row["temperatureK"], row["liquidComponent2MoleFraction"])
            row["dew"] = probe(arguments.probe, definition["component_id"], "dew", row["temperatureK"], row["vaporComponent2MoleFraction"])
            scored.append(row)
        result["sources"].append({
            "sourceID": source_id, "doi": definition["doi"], "title": document["Citation"]["sTitle"],
            "authors": document["Citation"]["sAuthor"], "year": int(document["Citation"]["yrPubYr"]),
            "component": definition["component"], "thermoMLMD5": document.get("THERMOML_MD5_CHECKSUM"),
            "encodedEquilibriumRows": len(scored), "bubbleMetrics": metrics(scored, "bubble"),
            "dewMetrics": metrics(scored, "dew"), "isotherms": isotherm_metrics(scored),
            "decision": "rejected",
            "decisionRationale": (
                "CO VLE remains research-only: the strongest 298.1 K bubble block is accurate, but the independent Westman block has stability rejections and the full predictive bubble/dew evidence is not robust."
                if definition["component"] == "CO" else
                "H2S VLE remains research-only because convergence is 36.84% and opposite-phase composition errors greatly exceed the source uncertainty."
            ),
            "rows": scored,
        })
    arguments.output.write_text(json.dumps(result, indent=2, allow_nan=False) + "\n")


if __name__ == "__main__":
    main()
