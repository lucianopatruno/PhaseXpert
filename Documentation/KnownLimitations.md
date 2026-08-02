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
- dry CO₂-rich mixture viscosity, caloric, heat-capacity, acoustic, conductivity and
  derivative properties and every mixture phase envelope are unavailable.
  No estimated mixing rule or fallback correlation is used.
- The IFE model formulation, coefficients and endpoint are not supplied.
- The broad input envelope is a test-planning domain, not a validated range.
- Components other than the explicitly restricted dry CO₂-rich mixture pair have no
  executable mixture support. Their identifiers remain future scaffolding.
- Saved-case comparison and its PDF/CSV reports are pairwise only. They do not
  rank models or establish accuracy.
- The phase chart does not support mixtures, bubble/dew separation, a
  two-phase area, cricondenbar or cricondentherm. Property-sweep PDFs contain
  the calculated sweep chart, but do not convert it into a phase envelope.
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

- Phase-diagram PNG and PDF embedding currently support only a real pure-CO₂ saturation boundary. CO₂-rich mixture phase envelopes remain unavailable and are never estimated for display or export.
- PDF phase-diagram embedding recalculates the boundary with the installed provider and therefore requires an exact recorded/current model-version and provider-version match.


## Restricted dry-mixture scope

The executable mixture component set is CO₂, N₂, O₂, Ar, CH₄ and H₂. Total
impurity is capped at 10 mol% as a temporary product guardrail, not a validated
accuracy range. Only density, provider phase, molar mass, specific volume and
compressibility factor are enabled. Mixture transport, caloric, acoustic,
derivative and phase-envelope results remain unavailable.
