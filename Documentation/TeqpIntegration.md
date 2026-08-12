# teqp pure-CO₂ integration

## Status

This is a deliberately narrow experimental native-provider milestone. It adds
an optional local teqp bridge for exactly 100 mol% CO₂. CoolProp remains the
default provider, and no existing calculation is routed to teqp unless the user
explicitly selects `teqp Pure CO₂ — Experimental`.

The generated teqp XCFramework is intentionally ignored by Git. A clean clone
therefore remains buildable without teqp and shows the provider as unavailable
until the local binary is built.

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

Numeric agreement with independent pure-CO₂ reference data remains validation
pending. A successful teqp execution is not a production accuracy claim.

## Next milestone

CO₂+N₂ must remain a separate milestone after this pure-CO₂ implementation is
reviewed and accepted. That future work needs its own model/data provenance,
mixture root/phase-selection strategy and independent validation plan.
