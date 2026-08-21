#!/usr/bin/env python3
"""Finalize the independently extracted/scored Al-Siyabi acoustic matrix."""

import argparse
import json
import math
import statistics
from pathlib import Path


def metrics(rows):
    usable = [row for row in rows if row["prediction"]["converged"]]
    errors = [row["prediction"]["speed"] - row["experimental"] for row in usable]
    relative = [100 * error / row["experimental"] for error, row in zip(errors, usable)]
    worst_absolute = max(range(len(errors)), key=lambda index: abs(errors[index]))
    worst_relative = max(range(len(relative)), key=lambda index: abs(relative[index]))
    return {
        "rows": len(rows),
        "converged": len(usable),
        "convergencePercent": 100 * len(usable) / len(rows),
        "MAEMetresPerSecond": statistics.fmean(map(abs, errors)),
        "biasMetresPerSecond": statistics.fmean(errors),
        "RMSMetresPerSecond": math.sqrt(statistics.fmean(error * error for error in errors)),
        "AARDPercent": statistics.fmean(map(abs, relative)),
        "worstAbsoluteDeviationMetresPerSecond": errors[worst_absolute],
        "worstAbsoluteRowID": usable[worst_absolute]["rowID"],
        "worstRelativeDeviationPercent": relative[worst_relative],
        "worstRelativeRowID": usable[worst_relative]["rowID"],
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--scored", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    scored = json.loads(arguments.scored.read_text())
    rows = scored["rows"]
    systems = {}
    for system in ["N2", "CH4", "H2", "O2", "MIXb"]:
        system_rows = [row for row in rows if row["system"] == system]
        systems[system] = {
            "metrics": metrics(system_rows),
            "isotherms": [
                {
                    "temperatureK": temperature,
                    "metrics": metrics([row for row in system_rows if row["T"] == temperature]),
                }
                for temperature in sorted({row["T"] for row in system_rows})
            ],
        }
    promoted = sorted(
        [
            row for row in rows
            if row["system"] == "O2" and row["T"] == 301.15 and row["P"] >= 24_120_000
        ],
        key=lambda row: row["P"],
    )
    result = {
        "schemaVersion": 1,
        "source": {
            "author": "Ibrahim Al-Siyabi",
            "title": "Effect of impurities on CO2 stream properties",
            "year": 2013,
            "repositoryHandle": "http://hdl.handle.net/10399/2643",
            "sourceFile": "Al-SiyabiI_0313_pe.pdf",
            "table": "Table 3.2, pages 47-52 of the thesis",
            "pressureBasis": "absolute",
            "speedOfSoundUnit": "m/s",
            "reportedSpeedOfSoundAccuracyMetresPerSecond": 1,
            "reportedCompositionUncertaintyMolePercent": 0.3,
            "temperatureStabilityK": 0.05,
            "extraction": "Exact numerical PDF tables; no graph digitization or EOS-derived source values.",
        },
        "teqp": {
            "version": "0.23.1",
            "commit": "a68eb9cabf47af2c4aba0d272ac10fbca4c10eca",
            "rootSelection": "homogeneousLiquidOrDense",
        },
        "compositions": {
            "N2": {"CO2": 0.9556, "N2": 0.0444},
            "CH4": {"CO2": 0.9539, "CH4": 0.0461},
            "H2": {"CO2": 0.9547, "H2": 0.0453},
            "O2": {"CO2": 0.9348, "O2": 0.0652},
            "MIXb": {"CO2": 0.9532, "CH4": 0.021, "H2": 0.008, "N2": 0.0178},
        },
        "systems": systems,
        "candidateBlocks": [
            {
                "id": "alsiyabi2013-o2-301k-high-pressure-tail",
                "system": "O2",
                "decision": "promoted",
                "property": "speedOfSound",
                "phaseDomain": "homogeneousLiquidOrDense",
                "exactComposition": {"CO2": 0.9348, "O2": 0.0652},
                "temperatureK": 301.15,
                "minimumPressurePa": 24_120_000,
                "maximumPressurePa": 40_830_000,
                "includedRows": [row["rowID"] for row in promoted],
                "metrics": metrics(promoted),
                "immediateExcludedLowerPressureRow": "alsiyabi2013-o2-044",
                "rationale": "The complete contiguous six-row high-pressure tail is entirely within the reported +/-1 m/s accuracy, with sub-1 m/s MAE and RMS. The immediately adjacent 21.39 MPa row errs by +1.896119 m/s and defines the conservative lower boundary.",
            }
        ],
        "decisions": {
            "N2": "rejected: systematic -14.978396 m/s bias and 2.300656% AARD",
            "CH4": "rejected: full matrix MAE 1.903212 m/s; no complete isotherm is uncertainty-consistent",
            "H2": "rejected: full matrix MAE 5.869325 m/s and pressure-dependent systematic deviations",
            "O2OutsidePromotedBlock": "rejected: lower-pressure and other-isotherm errors exceed measurement accuracy",
            "MIXb": "rejected: no complete isotherm is uncertainty-consistent; best 301.15 K full isotherm has 5.365561 m/s MAE and 8.923266 m/s worst error",
            "H2S": "research-only: no primary row-level binary acoustic matrix obtained",
        },
        "performanceMilliseconds": {
            "promotedBlockMean": statistics.fmean(row["prediction"]["runtimeMs"] for row in promoted),
            "promotedBlockMedian": statistics.median(row["prediction"]["runtimeMs"] for row in promoted),
            "promotedBlockWorst": max(row["prediction"]["runtimeMs"] for row in promoted),
        },
        "rows": rows,
    }
    arguments.output.write_text(json.dumps(result, indent=2, allow_nan=False) + "\n")


if __name__ == "__main__":
    main()
