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

The validation runner therefore exits nonzero in strict mode. Its
`--allow-incomplete` mode writes deterministic evidence for review without
claiming a successful scientific gate.

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
python3 Scripts/validate_calculations.py --allow-incomplete
```

Run strict scientific gating:

```text
python3 Scripts/validate_calculations.py
```

Strict mode is expected to fail until the missing reference fixtures are
lawfully sourced and committed.
