# Known limitations

- The architecture demo produces no scientific values.
- The CoolProp provider remains preliminary. Pure CO₂ now exposes density,
  viscosity, phase, caloric and heat-capacity properties, speed of sound,
  conductivity, Joule–Thomson coefficient and a pure-fluid saturation
  boundary. These expanded outputs have not completed independent PhaseXpert
  validation. The restricted dry CO₂-rich mixture spike supports density and phase, with
  a temporary 10 mol% total impurity cap that is not a validated accuracy range. Both
  executable paths report molar mass, specific volume and Z as transparent
  derived values rather than independent EOS outputs.
- Derived values inherit the validation status and uncertainty of their
  recorded composition and calculated density inputs.
- Enthalpy, entropy and internal energy use CoolProp's default reference state;
  comparisons require matching recorded model and provider versions.
- No independently sourced numeric dry CO₂-rich mixture cases have yet been approved and
  ingested. Mixture results must not be used for engineering decisions.
- Dry CO₂-rich mixture viscosity, caloric, heat-capacity, acoustic, conductivity and
  derivative properties remain unavailable. Mixture phase envelopes are
  provider-calculated but have not completed independent PhaseXpert validation.
  No estimated mixing rule or fallback correlation is used.
- The IFE model formulation, coefficients and endpoint are not supplied.
- The NeqSim provider is remote-only and unavailable until an endpoint is
  configured. Production use requires HTTPS service deployment, authentication
  decisions and operational monitoring. Localhost development does not prove
  production networking.
- NeqSim results are preliminary integration outputs. Successful NeqSim,
  CoolProp or cross-model agreement is not experimental validation and must not
  be used as an accuracy claim.
- NeqSim currently supports only the selected CO₂/N₂ `SystemSrkEos` +
  `classic` configuration backed by the pinned NeqSim interaction table. Other
  components and properties remain unavailable unless the service explicitly
  returns finite values and provenance.
- The broad input envelope is a test-planning domain, not a validated range.
- Components other than the explicitly restricted dry CO₂-rich mixture pair have no
  executable mixture support. Their identifiers remain future scaffolding.
- Saved-case comparison and its PDF/CSV reports are pairwise only. They do not
  rank models or establish accuracy.
- The phase chart separates provider bubble/dew branches but does not calculate
  or label cricondenbar or cricondentherm and does not infer a validated
  two-phase operating region from the display geometry.
- CoolProp can return usable bubble/dew points without completing construction
  or satisfying pressure closure for some supported compositions. PhaseXpert
  displays only finite provider-returned points when both branches are present,
  marks the trace incomplete/open and convergence false, and never joins,
  extrapolates or completes the trace cosmetically.
- CoolProp 8.0.0's native mixture-envelope continuation has no upstream
  iteration bound and may not reach its pressure-closure or near-pure-phase exit
  for some CO₂/N₂ compositions. PhaseXpert applies a tracked downstream cap of
  256 successfully calculated continuation steps, starts at 0.8 bar(a), and
  disables optional refinement. Reaching the cap returns only real accumulated
  provider points with incomplete/open status; PhaseXpert does not extrapolate
  or close the trace. The UI retains its 30-second presentation deadline.
- Phase-diagram PNG rendering uses SwiftUI `ImageRenderer` on the main actor.
  It is never started automatically when provider points arrive; the live chart
  renders first and image generation begins only after an explicit user action.
- Saved cases are local-only. Backup, sync and recovery UI are not implemented.
- Persisted saved-case import remains deliberately deferred until schema
  validation, duplicate handling, provenance protection and migration
  safeguards are designed and tested.
- The first SwiftData schema is versioned; no historical migration stage exists
  yet because there is no prior released schema.
- The support contact, copyright owner/year and final disclaimer need IFE
  confirmation.
- Xcode is unavailable in the implementation environment; a clean Xcode 26
  build and test run is required on the user's Mac.
- Docker is required for reproducible NeqSim service build validation.

- Phase-diagram PNG and PDF embedding support real pure-CO₂ saturation and
  supported dry-mixture envelopes. A failed or unavailable provider envelope
  remains unavailable and is never replaced with an estimated display curve.
- PDF phase-diagram embedding recalculates the boundary with the installed provider and therefore requires an exact recorded/current model-version and provider-version match.


## Restricted dry-mixture scope

The executable mixture component set is CO₂, N₂, O₂, Ar, CH₄ and H₂. Total
impurity is capped at 10 mol% as a temporary product guardrail, not a validated
accuracy range. Only density, provider phase, molar mass, specific volume and
compressibility factor are enabled. Mixture transport, caloric, acoustic,
derivative results remain unavailable. Phase envelopes are preliminary,
validation-pending provider outputs.

CoolProp's bounded density continuation can return finite bubble/dew points far
outside PhaseXpert's declared 0.8–300 bar(a), −55–150 °C app domain. Such a
trace is scientifically unusable in this app and is rejected in full with an
explicit unavailable message. PhaseXpert does not clip, reconnect, interpolate
or extrapolate it. Consequently, a supported mixture state calculation does not
guarantee that a mixture phase diagram is available.
