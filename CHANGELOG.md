# Changelog

## 0.1.0 — Foundation

- Created the native SwiftUI iOS project and local `PhaseXpertCore` package.
- Added IFE-derived design tokens, English vector logo and adaptive colors.
- Added SI unit conversion, composition validation and explicit normalization.
- Added provider, response, solver, traceability and phase-envelope contracts.
- Added non-scientific workflow, unavailable CoolProp and unavailable IFE
  providers.
- Added the versioned future IFE API request/response contract.
- Added unit and UI test foundations plus project documentation.
- Refined calculator styling with IFE blue accents, explicit operating-point
  labels, and an OK action for dismissing numeric keyboards.
- Standardized all user-facing pressure and temperature entry and display to
  bar absolute and °C while retaining SI internally.
- Added the restricted pure-CO₂ CoolProp provider, testable engine seam,
  native C++ bridge, MIT notice and reproducible XCFramework build tooling.
- Added preliminary result presentation with immutable scientific traceability.
- Added published pure-CO₂ reference checks and Release-optimized CoolProp
  builds, reducing the measured simulator cold calculation from about 70
  seconds to about 1.6 seconds on the test Mac.
- Added versioned, local-only SwiftData saved cases with search, sorting,
  metadata editing, duplication, deletion confirmation and edit/rerun.
- Added persistence round-trip and provenance-preservation tests.
- Added pairwise saved-case comparison for operating conditions, composition,
  model snapshots, phase and compatible finite property values.
- Added explicit compared-minus-reference semantics and safeguards that prevent
  unavailable, non-finite or unit-incompatible values from producing a
  numerical difference.
- Added approved light and dark PhaseXpert app-icon assets.
- Added a preliminary CoolProp HEOS pure-CO₂ saturation boundary and critical
  point, plotted with the current operating point in a pan/zoom Swift Chart.
- Added strict pure-fluid gating, cancellation, finite/monotonic boundary
  validation and explicit unavailable states for mixtures and other providers.
- Added a searchable, paginated PDF calculation report generated locally
  from the immutable saved-case snapshot.
- Added printable IFE styling, operating inputs, original/normalized
  composition, property status, warnings, model provenance, solver metadata,
  references, privacy text and scientific disclaimer.
- Added PDF signature, content, filename, long-document pagination and
  all-format non-finite rejection tests.
- Added a restricted preliminary CO₂-N₂ CoolProp spike for density and phase,
  using only binary interaction data from the pinned library release.
- Added a visible, blocking 10 mol% N₂ applicability cap, explicit unavailable
  status for mixture viscosity and phase envelopes, and no estimated mixing
  rule or fallback coefficients.
- Added binary rejection, malformed-output, provider-applicability and response
  serialization tests plus an independent experimental validation plan.
- Added a versioned experimental-density reference schema and evaluator that
  blocks unreviewed datasets, missing preapproved tolerances, unsupported
  compositions, non-finite values and incomplete predictions.
- Documented the NIST ThermoML ingestion route and two-person evidence gate for
  future CO₂-N₂ density validation; no experimental numeric claim is made yet.
