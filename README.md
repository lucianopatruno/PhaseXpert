# PhaseXpert

PhaseXpert is a native iPhone application for traceable thermophysical and
phase-property calculations for CO₂-rich mixtures.

> **Scientific status:** this repository currently contains the application
> foundation and a non-scientific architecture demo provider. It does **not**
> yet produce engineering results. CoolProp and the IFE Model are represented
> by unavailable provider descriptors only.

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

The `PhaseXpertCore` local Swift package can also be tested from its directory:

```sh
swift test
```

## Current milestone

- SwiftUI app shell with Calculator, Saved Cases, Phase Diagram, Model
  Information and About areas
- IFE-derived asset colors, light/dark variants and the approved English IFE
  logo extracted without redrawing or recoloring
- SI-first pressure and temperature conversions, including explicit gauge
  pressure reference
- composition and model-domain validation with explicit normalization
- provider-independent request, response, metadata and phase-envelope contracts
- unavailable CoolProp and IFE providers plus a clearly labelled
  non-scientific workflow provider
- versioned future IFE API data-transfer contract
- core unit tests and a main-workflow UI smoke test
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

This milestone uses Apple frameworks only and has no third-party runtime
dependency. CoolProp is not copied, linked, or redistributed yet. Licence and
notices must be reviewed before any integration is shipped. See
[References and Licences](Documentation/ReferencesAndLicences.md).

## Testing

Tests cover absolute/gauge pressure and temperature conversion, composition
totals, explicit normalization, duplicates, CO₂ dominance, provider lookup,
unsupported components and API serialization. Scientific reference-value tests
will be added with the selected independent reference dataset; no tolerance
will be chosen before that source and its uncertainty are documented.

This environment does not contain Xcode, so the committed project must be
built and tested on a Mac before the milestone is accepted.

## Configuration and secrets

The current app has no network endpoint or authentication configuration.
Future service endpoints must use build configuration, and credentials must
come from a secure runtime authentication flow and Keychain—not source files.
Certificate validation must never be bypassed.

## Known limitations

See [Known Limitations](Documentation/KnownLimitations.md). In particular:

- no scientific property calculation is connected;
- phase-envelope plotting, persistence, comparison and export are placeholders;
- impurity-specific validated limits are not established;
- an App Store icon has not been approved or supplied.

## Documentation

- [Architecture and directory structure](Documentation/Architecture.md)
- [Scientific models and phase-envelope strategy](Documentation/ScientificModels.md)
- [IFE Model API contract](Documentation/IFEModelAPI.md)
- [Validation strategy](Documentation/ValidationStrategy.md)
- [Adding providers and components](Documentation/ExtendingPhaseXpert.md)
- [References and licences](Documentation/ReferencesAndLicences.md)
- [App Store preparation](Documentation/AppStoreChecklist.md)
- [Known limitations](Documentation/KnownLimitations.md)
- [Changelog](CHANGELOG.md)

