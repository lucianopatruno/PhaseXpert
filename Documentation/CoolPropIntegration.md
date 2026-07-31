# CoolProp integration spike

## Status

The Swift provider, native C bridge and reproducible XCFramework build script
are present. The generated binary remains intentionally uncommitted. When it
is built at the documented local path, Swift Package Manager links it for iOS;
clean clones remain buildable and expose CoolProp as unavailable.

The integration is preliminary. It makes no production accuracy claim and must
not be used for engineering, safety, commercial or regulatory decisions.

## Pinned upstream and enabled scope

- CoolProp tag: `v8.0.0`
- Licence: MIT
- Backend: `HEOS`
- Pure CO₂: density, dynamic viscosity, phase and saturation boundary
- CO₂-N₂ binary: density and phase only
- Temporary binary cap: `0 < x(N₂) <= 0.10`
- CO₂-N₂ viscosity: unavailable
- CO₂-N₂ phase envelope: unavailable

The 10 mol% N₂ cap is an implementation-test restriction, not a validated
accuracy range. The bridge uses only the CO₂-N₂ interaction data distributed
with the pinned CoolProp release. PhaseXpert does not call
`apply_simple_mixing_rule`, does not overwrite binary interaction parameters
and does not invent missing coefficients.

The build script records the resolved upstream Git revision beside the
generated artifact. It also copies the upstream licence. The checked-in licence
at `ThirdParty/CoolProp/LICENSE` is from the pinned tag.

## Build the XCFramework

Prerequisites on macOS:

- Xcode 26 command-line tools
- Git
- CMake

From the repository root:

```sh
Scripts/build-coolprop-xcframework.sh
```

The script:

1. clones the pinned CoolProp tag with required submodules into a temporary
   build directory;
2. builds Release static libraries for iPhone and iPhone Simulator;
3. compiles the PhaseXpert C bridge;
4. combines the bridge and CoolProp archives;
5. creates
   `Vendor/CoolProp/PhaseXpertCoolPropBridge.xcframework`;
6. copies the licence and records the resolved Git revision.

Generated binaries are ignored by Git. Rebuild the XCFramework after any bridge
header or implementation change; otherwise Xcode may compile against a stale
native ABI. Do not download an unverified binary from an unofficial source.

## Native contract

`PhaseXpertCoolPropBridge.h` exposes:

- pure-CO₂ density, dynamic viscosity and phase from pressure in Pa and
  temperature in K;
- restricted CO₂-N₂ density and phase from SI state and mole fractions;
- linked library version;
- pure-CO₂ saturation pressure and triple/critical limits;
- bounded diagnostic buffers and integer error codes.

The binary function rejects non-finite or non-positive state input,
non-normalized or negative fractions, CO₂ that is not the largest component and
N₂ above the temporary cap. C++ exceptions never cross the C or Swift boundary.
Native output is checked for finiteness and physical sign.

The mixture fluid string uses the explicit supplied mole fractions with
`HEOS::CarbonDioxide&Nitrogen`. No fallback pair or estimated mixing rule is
permitted.

## Swift contract

`CoolPropEngine` is independent of C++. `CoolPropProvider`:

- declares no capabilities when the binary is absent;
- accepts pure CO₂ or the restricted CO₂-N₂ binary only;
- exposes the N₂ cap through provider applicability validation before
  calculation;
- rejects states outside the preliminary app domain;
- checks cancellation and native output;
- marks every successful value as preliminary and validation-pending;
- reports mixture viscosity as unavailable rather than fabricating a value;
- returns one pure-CO₂ saturation boundary and a critical point;
- returns no phase boundary for mixtures or when the binary is absent.

Tests use a deterministic mock engine to verify orchestration, rejection,
serialization and status handling. Mock values are never registered in the
running app and are not scientific reference values.

## Scientific validation gate

The selected first density-validation source is:

- Mazzoccoli, Bosio and Arato (2012), *Pressure-Density-Temperature
  Measurements of Binary Mixtures Rich in CO₂ for Pipeline Transportation in
  the CCS Process*, DOI
  [10.1021/je300590v](https://doi.org/10.1021/je300590v).

It covers CO₂-rich mixtures relevant to pipeline transport. Published numeric
tables have not yet been ingested into the repository, so this spike does not
claim agreement with that dataset. A traceable copy of the reference values,
their uncertainty and an approved tolerance must be added before any validation
claim.

Additional candidate references are listed in
[ValidationStrategy.md](ValidationStrategy.md).

## Acceptance before production use

- Rebuild and inspect arm64 iPhone and arm64/x86_64 simulator slices.
- Record the CoolProp version and resolved Git revision.
- Retain MIT notices and attribution.
- Run pure-CO₂ regression tests after rebuilding the bridge.
- Verify 95/5 mol% CO₂/N₂ density and phase execute on device and simulator.
- Verify mixture viscosity and phase envelope remain explicitly unavailable.
- Verify N₂ above 10 mol% and any third component are blocked.
- Add independently sourced density cases with inputs, values, uncertainty and
  justified tolerances.
- Complete scientific review and remove no warning until approval is recorded.
