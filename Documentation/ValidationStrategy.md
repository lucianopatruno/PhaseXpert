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

## NeqSim remote-provider validation

The PR23 service tier must run before claiming remote NeqSim availability:

- service unit tests for schema, health/capability metadata and malformed
  requests;
- direct pinned-NeqSim smoke calculations for pure CO₂, 97/3 CO₂/N₂ and
  90/10 CO₂/N₂ at 10 bar(a), 20 °C and 150 bar(a), 20 °C;
- phase-envelope smoke calculations for the same three compositions;
- API contract tests against a local container;
- Swift provider tests with deterministic non-scientific mocks for transport,
  finite-value safeguards, request-ID mismatches, unavailable endpoint,
  unsupported properties, branch separation, cancellation and stale-result
  behavior;
- standard iPhone 17 simulator validation for the app.

The smoke matrix demonstrates integration only. It is not scientific or
experimental validation.

Tolerances must be established before observing the implementation result and
must not be widened merely to obtain a passing test.

## Preliminary phase-boundary checks

Provider tests use non-scientific mock values only to verify orchestration:
pure-CO₂ gating, endpoint handling, ordered finite points, critical-point
labelling, cancellation and rejection of malformed values. They do not
validate CoolProp accuracy. A scientific saturation-pressure test will be
added only after IFE accepts an independent authoritative reference value and
a tolerance justified from that reference's uncertainty or precision.


## Dry CO₂-rich mixture validation plan

The current mixture implementation is a software-integration milestone, not a
validated property model. Its 10 mol% total-impurity cap limits testing and
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
single-/two-phase classification checks. Mixture viscosity remains disabled.
Mixture phase envelopes remain explicitly preliminary until independently
sourced bubble/dew cases, uncertainties and acceptance criteria are approved.


## Expanded pure-CO₂ property validation plan

The expanded provider contract is covered initially by deterministic
orchestration and safeguard tests. Those tests verify units, signed-value
handling, Cp/Cv derivation, mixture gating and non-finite rejection; their mock
numbers are not scientific reference values.

Before any production accuracy statement, IFE must approve independent cases
for enthalpy, entropy, internal energy, Cp, Cv, speed of sound, thermal
conductivity and Joule–Thomson coefficient across ship, pipeline and capture
states. Caloric comparisons must use a documented matching reference state.
Thermal-conductivity cases should be traced to Huber et al. (2016), DOI
10.1063/1.4940892, or an independent experimental dataset. Joule–Thomson
testing must include positive, zero-crossing-near and negative cases and avoid
undefined two-phase derivatives. Tolerances remain unset until reference
uncertainty and the intended claim are approved.
