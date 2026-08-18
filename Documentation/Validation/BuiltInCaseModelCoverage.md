# Built-in CCS case model coverage

Date: 2026-08-18

## Product acceptance target

Every source-based case in `BuiltInCaseCatalog` must be accepted by at least one executable thermodynamic provider at its stored pressure, temperature and composition without dropping components, silently normalizing composition, estimating missing binary interaction parameters or falling back to another provider.

## Current milestone

`General Properties (CoolProp)` is extended as a **preliminary, validation-pending** calculation path for the dry component set CO2, N2, O2, Ar, CH4, H2, CO and H2S, subject to the existing PhaseXpert guardrails:

- CO2 must be the unique largest component.
- Total impurity must be greater than zero and no more than 10 mol%.
- Mole fractions must sum to one without implicit native normalization.
- The native bridge uses only binary interaction entries shipped with pinned CoolProp v8.0.0.
- `apply_simple_mixing_rule` is not called and binary interaction parameters are not mutated.
- Mixture outputs remain density, provider phase, and transparently derived molar mass, specific volume and compressibility factor.
- The 10 mol% cap is a product guardrail, not a validated accuracy range.
- Results remain explicitly preliminary and must not be used for engineering, safety, commercial or regulatory decisions until independent validation is completed.

This milestone does **not** broaden the production validation gate of `Advanced CCS Properties`. Its H2, CH4, VLE and phase-envelope limits remain unchanged.

## Built-in acceptance matrix

| Built-in case | Stored impurities | General Properties target | Advanced CCS production gate |
| --- | --- | --- | --- |
| Northern Lights cargo specification example | CO, H2, O2, H2S | preliminary calculation path | unsupported composition |
| Brevik CCS conditioned export example | N2, CO, H2, O2, H2S | preliminary calculation path | unsupported composition |
| Porthos pipeline specification example | N2, CH4, Ar, H2 | preliminary calculation path | unsupported simultaneous impurities |
| Aramis ship specification example | CO, H2, N2, O2 | preliminary calculation path | unsupported composition |

## Validation required before merge

1. `PhaseXpertCore` tests must pass, including exact built-in provider-gate regressions.
2. The CoolProp XCFramework must be rebuilt from pinned v8.0.0 because the native ABI changed.
3. A native iOS regression must execute all four exact stored cases and confirm finite positive density and an explicit provider phase or explicit calculation failure; no case may be silently altered.
4. Normal Xcode build must pass with the rebuilt bridge.
5. Human review must confirm the Calculator preserves all loaded built-in components, including CO and H2S.

Passing this milestone establishes executable **preliminary model coverage**, not independent thermodynamic accuracy validation.
