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
- Pure CO₂: density, dynamic viscosity, phase, enthalpy, entropy, internal
  energy, Cp, Cv, Cp/Cv, speed of sound, thermal conductivity,
  Joule–Thomson coefficient and saturation boundary
- Dry CO₂-rich mixtures containing N₂, O₂, Ar, CH₄ or H₂: density, phase and
  provider bubble/dew phase envelope
- Temporary total-impurity cap: `0 < Σx(impurity) <= 0.10`
- Mixture viscosity and expanded state properties: unavailable

The 10 mol% total-impurity cap is an implementation-test restriction, not a validated
accuracy range. The bridge uses only interaction data distributed
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

- pure-CO₂ density, dynamic viscosity, enthalpy, entropy, internal energy,
  Cp, Cv, speed of sound, thermal conductivity, Joule–Thomson coefficient and
  phase from pressure in Pa and temperature in K;
- restricted dry-mixture density and phase from SI state and mole fractions;
- linked library version;
- pure-CO₂ saturation pressure and triple/critical limits;
- a bounded array of bubble, dew and provider-critical mixture-envelope points;
- bounded diagnostic buffers and integer error codes.

The mixture functions reject non-finite or non-positive state input,
non-normalized or negative fractions, CO₂ that is not the largest component and
total impurity above the temporary cap. C++ exceptions never cross the C or Swift boundary.
Native output is checked for finiteness and physical sign. The pure-fluid path
uses one HEOS AbstractState update per operating point; the Joule–Thomson
coefficient uses the single-phase derivative (∂T/∂p)h. Cp/Cv is derived in
Swift from the two returned heat capacities.

The state calculation fluid string and phase-envelope `AbstractState` use the
explicit supplied fractions and fixed supported component list. The envelope
must be built and closed by CoolProp and fit the bounded output array. No
fallback pair, estimated mixing rule or inserted scientific point is permitted.

## Swift contract

`CoolPropEngine` is independent of C++. `CoolPropProvider`:

- declares no capabilities when the binary is absent;
- accepts pure CO₂ or the restricted dry-mixture component set only;
- exposes the total-impurity cap through provider applicability validation before
  calculation;
- rejects states outside the preliminary app domain;
- checks cancellation and native output;
- marks every successful value as preliminary and validation-pending;
- reports mixture viscosity and every expanded pure-fluid-only property as
  unavailable rather than fabricating a value;
- returns one pure-CO₂ saturation boundary and a critical point;
- returns the real provider bubble/dew envelope for an accepted dry mixture;
- rejects incomplete, non-finite or branch-deficient envelopes.

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
- Verify all expanded pure-CO₂ outputs are finite on device and simulator.
- Confirm signed Joule–Thomson values and CoolProp reference-state caloric
  values are preserved rather than rejected as non-positive.
- Verify 95/5 mol% CO₂/N₂ density and phase execute on device and simulator.
- Verify mixture viscosity remains explicitly unavailable.
- Verify binary and multicomponent dry-mixture bubble/dew envelopes execute,
  preserve branches and export without estimated points.
- Verify total impurity above 10 mol% and unsupported components are blocked.
- Add independently sourced density cases with inputs, values, uncertainty and
  justified tolerances.
- Complete scientific review and remove no warning until approval is recorded.


## Expanded pure-CO₂ property status

Provider version 0.6.0 exposes caloric, heat-capacity, acoustic, conductivity
and Joule–Thomson results only for exactly 100 mol% CO₂. The C bridge returns SI
values from the pinned CoolProp HEOS state. Swift converts the Joule–Thomson
coefficient from K/Pa to °C/bar for presentation and derives Cp/Cv.

Enthalpy, entropy and internal energy use the pinned CoolProp default reference
state; saved records retain that model/library version. CoolProp documents the
CO₂ equation of state as Span and Wagner (1996), thermal conductivity as Huber
et al. (2016), and viscosity as Laesecke and Muzny (2017). These references
identify the implemented formulations but do not constitute independent
PhaseXpert validation.
