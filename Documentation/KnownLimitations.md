# Known limitations

- The architecture demo produces no scientific values.
- The CoolProp provider remains preliminary and restricted to pure CO₂ density,
  dynamic viscosity, phase identification and a pure-fluid saturation
  boundary.
- The IFE model formulation, coefficients and endpoint are not supplied.
- The broad input envelope is a test-planning domain, not a validated range.
- Individual impurity limits and binary-pair coverage are not established.
- Saved-case comparison is pairwise only. It does not rank models or establish
  accuracy, and it does not yet export a comparison report.
- The phase chart does not support mixtures, bubble/dew separation, a
  two-phase area, cricondenbar or cricondentherm. The calculation PDF records
  whether phase-boundary information was available but does not yet embed the
  interactive phase chart; standalone chart-image export remains a placeholder.
- Saved cases are local-only. Backup, sync and recovery UI are not implemented.
- The first SwiftData schema is versioned; no historical migration stage exists
  yet because there is no prior released schema.
- The support contact, copyright owner/year and final disclaimer need IFE
  confirmation.
- Xcode is unavailable in the implementation environment; a clean Xcode 26
  build and test run is required on the user's Mac.
