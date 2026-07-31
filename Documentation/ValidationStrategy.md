# Validation strategy

## Layers

1. **Contract tests:** units, serialization, stable identifiers and malformed
   remote responses.
2. **Numerical tests:** independently sourced values across the domain,
   including single-phase, near-boundary and two-phase cases.
3. **Cross-implementation tests:** compare the candidate provider with a
   separately obtained reference implementation or dataset.
4. **Regression tests:** retain every accepted reference case and every
   numerical defect.
5. **Device tests:** cancellation, memory, performance and offline behaviour on
   supported iPhones.

## Reference case record

Every scientific assertion must record:

- source and version, with DOI/report/dataset identifier;
- pressure, temperature, composition and basis;
- expected phase and property value with units;
- uncertainty or reference precision;
- absolute and relative tolerance and its physical justification;
- provider, backend and coefficient versions;
- result and reviewer.

REFPROP may be one comparison source under IFE's licence, but software-to-
software agreement is not experimental validation. Prefer published
experimental density, phase-equilibrium and viscosity datasets spanning ship,
pipeline and capture conditions. Dataset selection remains an IFE scientific
decision.

## Required edge cases

- NaN, infinity and overflow-producing inputs;
- negative, duplicate and missing components;
- exactly at and just beyond composition tolerances;
- zero total composition;
- CO₂ tied with or smaller than an impurity;
- unsupported component and binary pair;
- pressure/temperature bounds;
- flash non-convergence and phase-envelope partial failure;
- cancellation, timeout, offline, rate limiting and model mismatch;
- malformed, non-finite, wrong-unit and mismatched-request remote responses.

Tolerances must be established before observing the implementation result and
must not be widened merely to obtain a passing test.

## Preliminary phase-boundary checks

Provider tests use non-scientific mock values only to verify orchestration:
pure-CO₂ gating, endpoint handling, ordered finite points, critical-point
labelling, cancellation and rejection of malformed values. They do not
validate CoolProp accuracy. A scientific saturation-pressure test will be
added only after IFE accepts an independent authoritative reference value and
a tolerance justified from that reference's uncertainty or precision.
