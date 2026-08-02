# PhaseXpert

PhaseXpert is a native iPhone application for traceable thermophysical and
phase-property calculations for CO₂-rich mixtures.

> **Scientific status:** the optional native CoolProp 8.0.0 bridge provides
> preliminary pure-CO₂ density, viscosity, phase, caloric, heat-capacity,
> acoustic, conductivity and Joule–Thomson results plus restricted dry CO₂-rich
> density/phase calculations and provider bubble/dew envelopes containing N₂,
> O₂, Ar, CH₄ and H₂ up to 10 mol% total impurity. Both state paths also report explicitly
> derived molar mass, specific volume and compressibility factor. Validation is incomplete, so
> these results must not be used for engineering, safety, commercial or
> regulatory decisions. The IFE Model remains unavailable.

Developed by the **IFE Flow Technology Department**.

## Requirements

- macOS with Xcode 26 and its current iOS SDK
- iOS 18.0 or later
- An Apple Developer team for installation on a physical device

iOS 18 is the minimum because this is a new internal application with no
legacy installed base. It provides current SwiftUI, SwiftData and accessibility
APIs while covering devices expected to remain supported throughout initial
validation. Reconsider the target before public distribution if IFE requires
older managed devices.

## Build

1. Clone the repository.
2. Open `PhaseXpert.xcodeproj`.
3. Select the `PhaseXpert` scheme and an iOS 18+ simulator.
4. Build with **Product > Build**.
5. Run tests with **Product > Test**.

For a physical iPhone, select the PhaseXpert target, open **Signing &
Capabilities**, enable automatic signing, and select your Apple Developer team.
Keep the bundle identifier `no.ife.phasexpert` unless IFE has reserved a
different identifier. No signing material or team identifier belongs in Git.

The repository provides staged validation commands to avoid repeating slow UI
tests during every compiler correction:

```sh
bash Scripts/validate-phase-xpert.sh fast
bash Scripts/validate-phase-xpert.sh standard
bash Scripts/validate-phase-xpert.sh release
```

See [Development Workflow](Documentation/DevelopmentWorkflow.md) for the
validation tiers, simulator override and conditional CoolProp rebuild behavior.

## Current milestone

- SwiftUI app shell with Calculator, Saved Cases, Phase Diagram, Model
  Information and About areas
- IFE-derived asset colors, light/dark variants and the approved English IFE
  logo extracted without redrawing or recoloring
- SI-first pressure and temperature conversions, including explicit gauge
  pressure reference
- composition and model-domain validation with explicit normalization
- default molar-ppm impurity entry with CO₂ completed as the exact remainder,
  while retaining explicit mol% entry as an alternative
- provider-independent request, response, metadata and phase-envelope contracts
- a CoolProp 8.0.0 provider with expanded pure-CO₂ thermodynamic, acoustic and
  transport outputs plus restricted dry CO₂-rich mixture density/phase calculations; molar mass,
  specific volume and Z are
  derived transparently from recorded inputs and calculated density; an
  unavailable IFE provider, and a
  non-scientific demo provider
- immutable results grouped into state, thermodynamic, transport/acoustic and
  derived sections, with presentation-only engineering units, copy/share actions
  and concise or expert scientific traceability
- versioned, local-only SwiftData saved cases with search, sorting, metadata
  editing, duplication, confirmed deletion and edit/rerun
- pairwise saved-case comparison for operating points, composition, model
  snapshots, phase and compatible property values, with searchable PDF and
  long-form CSV compared-minus-reference reports
- preliminary provider-calculated pressure–temperature diagrams: one
  saturation boundary for pure CO₂ and separate bubble/dew branches for the
  supported dry CO₂-rich mixtures, including the current operating point
- local JSON, CSV and paginated PDF calculation-report export preserving the
  saved record, units, warnings and provider provenance
- bounded, cancellable pressure or temperature property sweeps using a real
  provider calculation at every point, with explicit gaps, phase labels,
  selected-point inspection, provenance-rich CSV export and searchable PDF
  reports containing vector charts of successful provider points
- versioned future IFE API data-transfer contract
- core, scientific-reference, persistence and workflow UI tests
- empty privacy manifest: no tracking and no collected data

## Architecture

The UI depends on `PhaseXpertCore`, not on a thermodynamic library. Providers
conform to `ThermodynamicModelProvider`; replacing the architecture demo with a
local library or remote IFE service does not require changing persistence or
views.

See [Architecture](Documentation/Architecture.md),
[Scientific Models](Documentation/ScientificModels.md), and
[IFE API Contract](Documentation/IFEModelAPI.md).

## Dependencies and licences

The generated CoolProp XCFramework is intentionally ignored by Git and must be
built locally with `Scripts/build-coolprop-xcframework.sh`. CoolProp is
MIT-licensed; its pinned source revision and licence notice are recorded beside
the generated artifact and must be included in distribution review. See
[References and Licences](Documentation/ReferencesAndLicences.md).

## Testing

Tests cover absolute/gauge pressure and temperature conversion, composition
totals, explicit normalization, duplicates, CO₂ dominance, provider lookup,
unsupported components, provider-specific dry-mixture limits, API and calculation
response serialization, selected published pure-CO₂ reference points, and
persistence round trips, and searchable multipage PDF calculation reports. Each
scientific tolerance is
documented with its source and purpose.

This environment does not contain Xcode, so the committed project must be
built and tested on a Mac before the milestone is accepted.

## Configuration and secrets

The current app has no network endpoint or authentication configuration.
Future service endpoints must use build configuration, and credentials must
come from a secure runtime authentication flow and Keychain—not source files.
Certificate validation must never be bypassed.

## Known limitations

See [Known Limitations](Documentation/KnownLimitations.md). In particular:

- CoolProp calculations are preliminary; expanded pure-CO₂ properties have
  not completed independent PhaseXpert validation, while dry mixtures containing N₂, O₂, Ar, CH₄ or H₂ remain
  limited to density and phase with at most 10 mol% total impurity;
- derived molar mass, specific volume and Z inherit the validation status of
  their composition and density inputs and are not independent EOS outputs;
- dry-mixture phase envelopes are preliminary CoolProp outputs and have not
  completed independent PhaseXpert validation; continuation begins at the
  declared 0.8 bar(a) PhaseXpert domain minimum and does not represent the
  lower-pressure envelope;
- property-sweep charts connect adjacent successful calculations for
  visualization only; failures and unavailable values remain explicit gaps in
  both interactive and PDF charts;
- comparison is pairwise and its PDF/CSV exports report numerical differences,
  not model accuracy;
- saved cases are local-only and do not sync between devices;
- impurity-specific validated limits are not established.

## Documentation

- [Development workflow](Documentation/DevelopmentWorkflow.md)
- [Architecture and directory structure](Documentation/Architecture.md)
- [Scientific models and phase-envelope strategy](Documentation/ScientificModels.md)
- [CoolProp integration spike](Documentation/CoolPropIntegration.md)
- [IFE Model API contract](Documentation/IFEModelAPI.md)
- [Validation strategy](Documentation/ValidationStrategy.md)
- [Adding providers and components](Documentation/ExtendingPhaseXpert.md)
- [References and licences](Documentation/ReferencesAndLicences.md)
- [App Store preparation](Documentation/AppStoreChecklist.md)
- [Known limitations](Documentation/KnownLimitations.md)
- [Changelog](CHANGELOG.md)
