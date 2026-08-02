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

- Added export of the real provider-calculated pure CO₂ phase diagram as PNG.
- Added the calculated phase diagram and searchable phase-boundary provenance to PDF reports when the saved provider versions match the installed provider.
- Made the calculator shield open scientific traceability, aligned pressure and temperature inputs with composition fields, and added keyboard previous/next navigation.
- Added a persisted light/dark appearance toggle, selected CoolProp by default, and standardized absolute-pressure labels as `bar(a)`.

- Added safeguarded, provider-independent derivation of mixture molar mass,
  specific volume and compressibility factor from recorded mole fractions, SI
  state and calculated density, with explicit formulas and provenance.
- Added reviewed NIST molecular weights for the executable CO₂-N₂ domain and
  explicit unavailable/failed states when required inputs are unsupported or
  non-physical.

- Expanded the pure-CO₂ native bridge and provider with enthalpy, entropy,
  internal energy, Cp, Cv, Cp/Cv, speed of sound, thermal conductivity and the
  Joule–Thomson coefficient using one HEOS state update.
- Added signed-value handling, finite/physical safeguards, reference-state
  provenance, pure-fluid gating, mixture-unavailable behavior and contract
  tests for the expanded property set.


- Grouped calculation results into state, thermodynamic, transport/acoustic,
  derived and additional sections, with display-only engineering unit
  conversions and copy/share summaries.
- Added bounded pressure and temperature property sweeps that execute the
  selected provider at every point, preserve per-point provenance, expose
  progress/cancellation, leave failures as chart gaps and export traceable CSV.

- Expanded the preliminary mixture scope to dry CO₂-rich combinations of N₂,
  O₂, Ar, CH₄ and H₂ using only interaction entries shipped by CoolProp 8.0.0.
- Enforced a visible 10 mol% total-impurity product guardrail without claiming
  it as a validated accuracy range; mixture expanded properties and phase
  envelopes remain unavailable.
- Added reviewed NIST molar masses for transparent mixture M, v and Z
  derivations.
- Fixed select-all editing for pressure and temperature, centered the property
  sweep action, and made each scientific reference open its own destination.
- Declared that PhaseXpert uses no non-exempt encryption in generated app
  metadata for App Store Connect export-compliance processing.
- Added searchable, paginated pairwise comparison reports in PDF and CSV with
  explicit compared-minus-reference semantics, immutable calculation IDs,
  units, statuses, warnings and complete model/provider provenance.
- Added professional searchable property-sweep PDF reports with IFE styling,
  vector axes, units and legend; only adjacent successful provider points are
  connected, while failed and unavailable points remain gaps.
- Added reporting snapshot serialization and focused pagination, unavailable-
  value, non-finite-value, content and traceability tests.
- Made molar ppm the default impurity input basis, with CO₂ calculated as the
  exact remainder to 1,000,000 ppm; retained explicit mol% entry and preserved
  the original basis in immutable calculation snapshots.
- Added real CoolProp HEOS dry-mixture bubble/dew phase envelopes for the
  existing supported component set and 10 mol% product guardrail, with no
  estimated mixing rule, fallback curve or interpolated scientific values.
- Extended phase-diagram PNG and searchable PDF reporting with mixture
  composition, bubble/dew legends, solver/model provenance and calculation
  traceability.
- Replaced system disclosure labels with a reusable app-owned expandable row
  so expandable options use the same typography as neighboring actions.
- Allowed usable provider bubble/dew traces to remain visible when CoolProp
  does not set its pressure-closure flag, while marking convergence false and
  explicitly refusing to close the trace cosmetically.
- Preserved finite, branch-complete provider points when CoolProp stops before
  setting its construction-complete flag, while marking the trace incomplete,
  open and non-converged without extrapolating or closing it.
- Matched expandable-row labels and chevrons to the body typography and IFE
  blue action color used by neighboring Form actions.
- Replaced the unbounded phase-diagram loading state with a 30-second
  presentation deadline while retaining the original provider calculation in
  the background and automatically displaying any late successful response.
