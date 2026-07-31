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


## CO₂-N₂ spike validation plan

The executable evidence schema, review gate and selected source route are
documented in [CO2N2DensityValidation.md](CO2N2DensityValidation.md).

The current binary implementation is a software-integration spike, not a
validated property model. Its 10 mol% N₂ cap limits first-release testing and
must not be described as an accuracy range.

Candidate independent experimental sources are:

- Mazzoccoli, Bosio and Arato (2012), *Pressure-Density-Temperature
  Measurements of Binary Mixtures Rich in CO₂ for Pipeline Transportation in
  the CCS Process*, DOI
  [10.1021/je300590v](https://doi.org/10.1021/je300590v). The publication covers
  CO₂-rich pipeline mixtures from 273.15 K to 293.15 K and 1 MPa to 20 MPa.
- Brugge, Holste, Hall, Gammon and Marsh (1997), *Densities of Carbon Dioxide +
  Nitrogen from 225 K to 450 K at Pressures up to 70 MPa*, DOI
  [10.1021/je970044w](https://doi.org/10.1021/je970044w).
- Westman et al. (2016), *Vapor-liquid equilibrium data for the carbon dioxide
  and nitrogen system at 223, 270, 298 and 303 K and pressures up to 18 MPa*,
  DOI
  [10.1016/j.fluid.2015.09.034](https://doi.org/10.1016/j.fluid.2015.09.034).

Before a scientific test is added, IFE must obtain the actual tabulated value
through a lawful source and record composition, state, property, units,
reported uncertainty and citation. The pass tolerance must be derived from the
reference uncertainty and the intended model claim before the CoolProp result
is inspected.

Initial coverage should include ship/capture low-temperature states, dense
pipeline states, points on both sides of the critical region and explicit
single-/two-phase classification checks. Mixture viscosity and mixture phase
envelopes remain disabled until property-specific references and acceptance
criteria are approved.
