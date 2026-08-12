# teqp pure-CO₂ integration

## Status

This is a deliberately narrow experimental native-provider milestone. It adds
an optional local teqp bridge for exactly 100 mol% CO₂. CoolProp remains the
default provider, and no existing calculation is routed to teqp unless the user
explicitly selects `teqp Pure CO₂ — Experimental`.

The generated teqp XCFramework is intentionally ignored by Git. A clean clone
therefore remains buildable without teqp and shows the provider as unavailable
until the local binary is built. When the generated teqp XCFramework is present,
ordinary Xcode app builds include it and show the provider as available.

## Pinned upstream

- Project: `usnistgov/teqp`
- Tag: `v0.23.1`
- Commit: `a68eb9cabf47af2c4aba0d272ac10fbca4c10eca`
- Licence: NIST disclaimer of copyright and warranty from `LICENSE.md`
- Model data: upstream `teqp/fluiddata/dev/fluids/CarbonDioxide.json`
- CO₂ EOS provenance in that data: `BibTeX_EOS` is `Span-JPCRD-1996`
- teqp paper cited by upstream: Bell and Deiters (2021), DOI
  `10.1021/acs.iecr.1c00847`

The build records the resolved upstream revision, submodule revisions and
licence beside the generated artifact under `Vendor/teqp/`. Those files are
ignored like the generated binary and must be inspected before distribution.

## Native build strategy

`Scripts/build-teqp-xcframework.sh` clones the pinned tag with submodules into a
temporary build directory, configures teqp only far enough to unpack its bundled
headers/schema support, generates a traceable C++ header containing the pinned
CO₂ JSON data, and compiles `Native/TeqpBridge/src/PhaseXpertTeqpBridge.cpp`
directly into static libraries for:

- `ios-arm64`;
- iOS Simulator `arm64`;
- iOS Simulator `x86_64`.

The script packages those static libraries as static framework slices inside
`PhaseXpertTeqpBridge.xcframework`:

- `ios-arm64/PhaseXpertTeqpBridge.framework`;
- `ios-arm64_x86_64-simulator/PhaseXpertTeqpBridge.framework`;
- each framework contains the static binary `PhaseXpertTeqpBridge`,
  `Headers/PhaseXpertTeqpBridge.h` and `Modules/module.modulemap`.

This framework-style layout is deliberate. The first static-library
XCFramework package used `HeadersPath = Headers` with a top-level
`Headers/module.modulemap`, matching the existing CoolProp static-library
XCFramework layout. When both binary targets were present, Xcode processed both
XCFrameworks into the same product include directory and both commands claimed
`include/module.modulemap`. Packaging teqp as a framework-style XCFramework
keeps its module map inside `PhaseXpertTeqpBridge.framework/Modules/`, so it no
longer collides with CoolProp's existing `include/module.modulemap` output.

The bridge uses teqp's header-level multifluid model and does not link the
broader `teqpcpp` wrapper. During feasibility testing, the upstream
`teqpcpp` target did not compile with AppleClang 21 because
`critical_pure.hpp` contains two `tdx::template get_Ar11/get_Ar12` calls that
AppleClang rejects. The narrow bridge avoids that wrapper path and compiled for
the required iOS object architectures.

## Runtime contract

The C ABI exposes:

- linked teqp version/provenance text;
- pure-CO₂ density from pressure in Pa and temperature in K;
- molar density and root count for bridge diagnostics;
- limited phase state, currently only `supercritical` when the input state is
  above the model critical temperature and pressure; otherwise `unknown`.

The density solve samples positive molar-density space, brackets sign changes
of teqp pressure minus requested pressure, and accepts a result only when
exactly one positive density root is found. Multiple roots are reported as a
failure; PhaseXpert does not choose one arbitrarily.

## Supported scope

Supported:

- exactly 100 mol% CO₂;
- density;
- transparently derived molar mass, specific volume and compressibility factor
  through the existing PhaseXpert derived-property layer.

Unavailable:

- viscosity and all transport properties;
- enthalpy, entropy, internal energy, heat capacities, acoustic properties,
  thermal conductivity and Joule-Thomson coefficient;
- phase envelopes;
- CO₂+N₂ and all other mixtures.

Unsupported compositions return provider-domain errors and are not silently
sent to CoolProp.

## Validation basis

The bridge feasibility gate established native compilation for the required
device and simulator object architectures. Provider tests verify explicit
provider selection, pure-CO₂ result mapping, unsupported-mixture rejection,
viscosity-unavailable behavior and the absence of CoolProp fallback.

Direct native bridge probing against the retained Mantilla et al. (2010)
experimental density references in `Documentation/PureCO2Validation.md`
produced the following results. The acceptance tolerance is the pre-existing
PhaseXpert rule for this source: reported expanded uncertainty plus 0.1% of
experimental density.

| Region | T / K | P / Pa | Reference density / kg/m³ | teqp density / kg/m³ | Absolute deviation / kg/m³ | Relative deviation | Tolerance / kg/m³ | Result |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| gas-like | 310.00 | 1,998,000 | 37.614000 | 37.603006 | 0.010994 | 0.000292272 | 0.246614 | pass |
| near-critical dense | 310.00 | 10,014,000 | 686.160000 | 686.431111 | 0.271111 | 0.000395114 | 1.047160 | pass |
| dense liquid-like | 310.00 | 29,966,000 | 921.817000 | 921.860028 | 0.043028 | 0.000046677 | 0.987817 | pass |
| supercritical | 350.00 | 19,981,000 | 613.586000 | 613.738164 | 0.152164 | 0.000247992 | 0.828586 | pass |
| high-temperature supercritical | 400.00 | 29,994,000 | 561.435000 | 561.411573 | 0.023427 | 0.000041727 | 0.679435 | pass |

The probe also verified that the known two-phase state 280 K and 6 MPa returns
the explicit multiple-root error instead of selecting an arbitrary density.

`PhaseXpertTests/TeqpNativeBridgeValidationTests.swift` adds the corresponding
iOS XCTest coverage for `NativeTeqpEngine`. With the generated
framework-style teqp XCFramework present, those tests run in ordinary Xcode app
test builds and exercise Swift calling through `NativeTeqpEngine` into the C
bridge and compiled teqp EOS.

These checks validate only the narrow pure-CO₂ density path at the listed
single-phase points and one conservative two-phase rejection behavior. They do
not establish production accuracy, phase-boundary accuracy, transport
properties, mixtures or physical-iPhone manual acceptance.

## Next milestone

CO₂+N₂ must remain a separate milestone after this pure-CO₂ implementation is
reviewed and accepted. That future work needs its own model/data provenance,
mixture root/phase-selection strategy and independent validation plan.
