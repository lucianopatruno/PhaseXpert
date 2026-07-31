# Known limitations

- The architecture demo produces no scientific values.
- The CoolProp provider remains preliminary. Pure CO₂ supports density,
  dynamic viscosity, phase identification and a pure-fluid saturation
  boundary. The restricted CO₂-N₂ spike supports density and phase only, with
  a temporary 10 mol% N₂ cap that is not a validated accuracy range.
- No independently sourced numeric CO₂-N₂ cases have yet been approved and
  ingested. Mixture results must not be used for engineering decisions.
- CO₂-N₂ dynamic viscosity and every mixture phase envelope are unavailable.
  No estimated mixing rule or fallback correlation is used.
- The IFE model formulation, coefficients and endpoint are not supplied.
- The broad input envelope is a test-planning domain, not a validated range.
- Components other than the explicitly restricted CO₂-N₂ pair have no
  executable mixture support. Their identifiers remain future scaffolding.
- Saved-case comparison is pairwise only. It does not rank models or establish
  accuracy, and it does not yet export a comparison report.
- The phase chart does not support mixtures, bubble/dew separation, a
  two-phase area, cricondenbar or cricondentherm. Chart and report export remain
  placeholders.
- Saved cases are local-only. Backup, sync and recovery UI are not implemented.
- The first SwiftData schema is versioned; no historical migration stage exists
  yet because there is no prior released schema.
- The support contact, copyright owner/year and final disclaimer need IFE
  confirmation.
- Xcode is unavailable in the implementation environment; a clean Xcode 26
  build and test run is required on the user's Mac.
