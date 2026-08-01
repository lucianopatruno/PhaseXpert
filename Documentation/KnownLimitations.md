# Known limitations

- The architecture demo produces no scientific values.
- The CoolProp provider remains preliminary. Pure CO₂ supports density,
  dynamic viscosity, phase identification and a pure-fluid saturation
  boundary. The restricted CO₂-N₂ spike supports density and phase, with
  a temporary 10 mol% N₂ cap that is not a validated accuracy range. Both
  executable paths report molar mass, specific volume and Z as transparent
  derived values rather than independent EOS outputs.
- Derived values inherit the validation status and uncertainty of their
  recorded composition and calculated density inputs.
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
  two-phase area, cricondenbar or cricondentherm. The calculation PDF does not
  yet embed a phase-envelope record or the interactive phase chart; standalone
  chart-image export remains a placeholder.
- Saved cases are local-only. Backup, sync and recovery UI are not implemented.
- The first SwiftData schema is versioned; no historical migration stage exists
  yet because there is no prior released schema.
- The support contact, copyright owner/year and final disclaimer need IFE
  confirmation.
- Xcode is unavailable in the implementation environment; a clean Xcode 26
  build and test run is required on the user's Mac.

- Phase-diagram PNG and PDF embedding currently support only a real pure-CO₂ saturation boundary. CO₂-rich mixture phase envelopes remain unavailable and are never estimated for display or export.
- PDF phase-diagram embedding recalculates the boundary with the installed provider and therefore requires an exact recorded/current model-version and provider-version match.
