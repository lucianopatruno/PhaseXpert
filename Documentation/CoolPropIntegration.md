# CoolProp integration spike

## Status

The Swift provider, native C bridge and reproducible XCFramework build script
are present. The generated binary is not committed or linked yet, so the
application remains buildable and CoolProp remains unavailable.

This separation is intentional: a binary is not accepted until its device and
simulator slices, upstream revision, licence and behavior have been inspected.

## Pinned upstream

- CoolProp tag: `v8.0.0`
- Licence: MIT
- Backend planned for this spike: `HEOS`
- Enabled fluid: pure carbon dioxide only
- Enabled properties: mass density and dynamic viscosity

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
2. builds static libraries for iPhone and iPhone Simulator;
3. compiles the PhaseXpert C bridge;
4. combines the bridge and CoolProp archives;
5. creates
   `Vendor/CoolProp/PhaseXpertCoolPropBridge.xcframework`;
6. copies the licence and records the resolved Git revision.

Generated binaries are ignored by Git until the build is reproduced and
reviewed. Do not download an unverified binary from an unofficial source.

## Native contract

`PhaseXpertCoolPropBridge.h` exposes only:

- pure-CO₂ calculation from pressure in Pa and temperature in K;
- density in kg/m³;
- dynamic viscosity in Pa·s;
- a controlled phase enumeration;
- linked library version;
- bounded diagnostic buffers and integer error codes.

C++ exceptions never cross the C or Swift boundary. The bridge rejects
non-finite/non-positive input and output.

## Swift contract

`CoolPropEngine` is independent of C++. `CoolPropProvider`:

- declares no capabilities when the binary is absent;
- accepts only pure CO₂;
- rejects states outside the preliminary app domain;
- checks cancellation and native output;
- marks every successful value as preliminary and validation-pending;
- returns unavailable status for properties outside the spike;
- does not generate a phase envelope.

Tests use a deterministic mock engine to verify orchestration and status
handling. Mock values are never registered in the running app.

## Acceptance before linking

- Build succeeds for arm64 iPhone and arm64/x86_64 simulator slices.
- The XCFramework exposes only the intended C module.
- CoolProp version and Git revision are recorded.
- MIT notices are present.
- Existing app and core tests still pass without the binary.
- Native smoke tests reject NaN, infinity and invalid state points.
- No mixture can reach the native bridge.

Linking and the real pure-CO₂ reference tests form the next commit after the
artifact is built successfully on the user's Mac.

