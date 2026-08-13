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
- Removed automatic main-actor PNG rendering from phase-diagram appearance;
  the calculated chart now renders first and image export starts only after an
  explicit user action.
- Bounded native dry-mixture phase-envelope continuation to the declared
  0.8 bar(a) PhaseXpert pressure-domain minimum, disabled CoolProp's optional
  refinement pass, retained only real provider points in-domain and recorded
  the truncation and solver settings in reportable provenance.
- Replaced non-terminating CoolProp mixture-envelope continuation with bounded
  pointwise HEOS PQ bubble/dew sampling over 0.8–300 bar(a), stopping branches
  at the first post-start provider failure and reporting attempted/failed
  provider flashes without interpolation or inferred closure.
- Removed the unsuccessful standalone mixture-PQ sampling experiment after
  manual validation showed no usable 3 mol% N₂ branches. Restored CoolProp's
  working density continuation and added a deterministic 256-provider-step
  downstream cap to its upstream-unbounded loop, with focused regression
  coverage for both 3 and 10 mol% N₂.
- Refreshed Xcode's local-package graph whenever the ignored CoolProp
  XCFramework is confirmed or rebuilt, and restored the prior framework after
  failed rebuilds so a temporary missing artifact cannot remain cached.
- Added end-to-end provider/view-model coverage for 3 and 10 mol% N₂ plus a
  visible-app regression for the 3 mol% N₂ phase diagram.
- Removed the physical-device-fragile Swift Charts scrollable-domain state
  from phase-boundary rendering, display the complete finite provider domain
  directly, and require the actual chart element in the visible-app regression.
- Rejected complete CoolProp mixture phase-envelope traces when any returned
  point leaves the declared 0.8–300 bar(a), −55–150 °C PhaseXpert domain,
  instead of plotting or clipping a finite but scientifically unusable
  continuation.
- Bumped CoolProp provider provenance to 0.8.2 and replaced chart-presence
  regressions with focused pressure- and temperature-domain rejection coverage.
- Removed the low-visibility custom keyboard “OK” control; numeric keyboards
  now dismiss interactively while scrolling and retain previous/next navigation.
- Made CO₂ a read-only exact remainder in both ppm and mol% composition entry,
  with live validation and no normalization of impurity values.
- Added an explicit destructive “Remove impurity” action to each impurity menu
  while retaining swipe-to-delete behavior.
- Added the first deliberately narrow experimental teqp milestone: optional
  native pure-CO₂ density support through a local C++ bridge, with mixtures and
  viscosity explicitly unavailable and CoolProp remaining the default provider.
- Renamed the user-facing provider labels to General Properties (CoolProp) and
  Advanced Phase & Mixture Model (teqp) while preserving stable provider IDs.
- Documented the pinned teqp v0.23.1 CO₂+N₂ model-data provenance and added a
  validation-gated native binary VLE/point-classification research layer; teqp
  CO₂+N₂ remains unavailable to users.
- Corrected the native teqp CO₂+N₂ Gate C density-validation provenance:
  high-temperature 303-383 K diagnostic rows are Mantovani et al. 2012
  (`10.1016/j.supflu.2011.09.001`), not Mazzoccoli et al. 2012
  (`10.1021/je300590v`); added Brugge et al. 1997
  (`10.1021/je970044w`) as the audited primary PVT source, and fixed the
  binary point classifier so it no longer uses pure-CO₂ critical temperature as
  the CO₂/N₂ phase-topology switch. Gate C remains not passed, with no
  user-facing N₂ range enabled, because the Mantovani low-N₂ rows are correctly
  transcribed and reproduced by direct upstream teqp and the PhaseXpert bridge,
  and Gate C genuinely failed to establish a defensible user-facing sub-domain
  for the pinned binary model.
- Added the first teqp internal formulation catalog and multi-impurity model
  inventory document. The user-facing teqp provider still enables only pure
  CO₂; N₂, O₂, Ar, H₂ and CH₄ are inventoried for validation-gated future
  formulations but remain unavailable through teqp until independent gates pass.
- Added a native teqp pure-CO₂ saturation boundary for the existing Phase
  Diagram workflow, using teqp VLE saturation points through the critical point
  while keeping all impurity phase diagrams unavailable until validation passes.
- Added direct teqp multi-impurity bake-off results for the O₂ and Ar pinned
  standard multifluid candidates against audited Mantovani 2012 density rows.
  O₂ and Ar remain unavailable through teqp because the evaluated candidates did
  not establish a production density+VLE domain.
