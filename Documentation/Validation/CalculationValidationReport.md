# Calculation Validation Report

## Scope

This milestone freezes the validation protocol for the current production
calculation surface and removes the non-scientific architecture demonstration
provider from production routing. It does not add a thermodynamic backend and
does not expand PhaseXpert's supported property or composition scope.

## Model Architecture Decision

`architecture-demo` was a production-registered provider whose implementation
returned no thermophysical values and existed only to exercise app workflow.
It is removed from production model selection and provider routing. Protocol
and serialization tests now use test-only providers defined in test targets.

`IFE Model` remains visible as an unavailable descriptor with the status
`Unavailable` and supporting text `This model is not available in this
version.` It is not registered as a provider, cannot receive calculation
requests and cannot fall back to CoolProp. Older saved records retain their
embedded model provenance; a saved request for `ife-model` loads as unavailable
and requires an explicit selectable model before recalculation.

## Frozen Reference Protocol

Committed pure-CO2 reference fixtures are listed in
`CalculationReferenceManifest.json`.

- Pure-CO2 density: 5 Mantilla et al. experimental P-rho-T points.
- Pure-CO2 viscosity: 4 low-density Schaefer et al. points and 5 cold dense
  Chapoy et al. points.
- Pure-CO2 critical point: 1 NIST Chemistry WebBook value.
- Pure-CO2 saturation pressure: candidate NIST WebBook provenance is recorded,
  but no liquid-vapour saturation-pressure fixture is committed.

The acceptance tolerances are fixed in the manifest and in
`PureCO2ReferenceValidationTests.swift`. Passing those runtime tests verifies
selected iOS-native calculation paths against independent experimental values,
but it does not justify removing the app-wide preliminary status.

## Current Gate Result

The complete scientific validation gate does not pass yet. The blocker is
evidence, not code execution:

- no committed independent pure-CO2 saturation-pressure fixture with license
  and uncertainty review;
- no committed CO2-N2 density table values with composition basis, units,
  uncertainty and redistribution terms.

The validation runner derives `overall_scientific_gate` from the required gate
statuses rather than from a hardcoded outcome. Strict-mode exit status uses the
same blocker list, so any blocked gate, failed gate or missing required
production observation yields `overall_scientific_gate: not_passed` and a
nonzero strict exit. Its `--allow-incomplete` mode writes deterministic evidence
for review without changing the scientific gate result.

## Production Observation Path

`PureCO2ReferenceValidationTests` writes native production-path observations
using schema `phasexpert-production-observations.v2`. Each observation records
fixture identity, reference identifier, input state, normalized composition,
provider identity, provider and model versions, calculation status, SI units,
returned phase and the calculated value or critical coordinates.

The deterministic runner accepts `Documentation/Validation/ProductionObservations.json`
with `--observations <path>`. Before evaluating deviations it rejects wrong
schema versions, wrong providers, missing provider/model versions, duplicate or
missing observations, fixture/reference mismatches, wrong property or unit,
state or composition mismatches, malformed statuses and non-finite outputs.

The production observation test can still write directly to
`PHASEXPERT_VALIDATION_OBSERVATIONS_PATH`. It also attaches the deterministic
JSON to the Xcode test result and emits a
`PHASEXPERT_VALIDATION_OBSERVATIONS_BASE64=` log line. Use
`Scripts/extract_validation_observations.py` to decode that payload without
manual editing of scientific values.

No committed result in this branch uses provider output as reference data. The
native observations are used only to compare production calculations against the
committed independent fixtures.

## Supported Range Matrix

| Capability | Current product state |
| --- | --- |
| Pure-CO2 density | Supported, preliminary; selected reference protocol frozen |
| Pure-CO2 dynamic viscosity | Supported, preliminary; selected reference protocol frozen |
| Pure-CO2 derived molar mass, specific volume and compressibility factor | Supported through transparent equations |
| Pure-CO2 caloric, acoustic, conductivity and derivative properties | Supported, preliminary |
| Pure-CO2 phase diagram | Supported, preliminary; pure-CO2 only |
| CO2-N2 density within the 10 mol% impurity guardrail | Supported, preliminary; independent fixture blocked |
| CO2-N2 viscosity | Unavailable |
| Multicomponent phase diagrams | Unavailable |
| IFE Model | Visible, unavailable |

## Reproduction

Run the deterministic validation evidence writer:

```text
python3 Scripts/validate_calculations.py --observations Documentation/Validation/ProductionObservations.json --allow-incomplete
```

Run strict scientific gating:

```text
python3 Scripts/validate_calculations.py --observations Documentation/Validation/ProductionObservations.json
```

Strict mode is expected to fail until the missing reference fixtures are
lawfully sourced and committed.
