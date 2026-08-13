# teqp native integration

## Status

This is a deliberately narrow experimental native-provider milestone. It adds
an optional local teqp bridge for exactly 100 mol% CO₂, plus validation-gated
CO₂+N₂ research infrastructure. CoolProp remains the default provider, and no
existing calculation is routed to teqp unless the user explicitly selects
`Advanced Phase & Mixture Model (teqp)`.

## CO₂+N₂ Gate A finding

Pinned teqp v0.23.1 contains traceable upstream data for a CO₂+N₂ multifluid
model. The relevant records in the pinned upstream tree are:

- `CarbonDioxide.json`: CO₂ fluid model, CAS `124-38-9`,
  `BibTeX_EOS = Span-JPCRD-1996`, molar mass `0.0440098 kg/mol`,
  critical state `T = 304.1282 K`, `p = 7,377,300 Pa`, and EOS limits
  `T_max = 2000 K`, `p_max = 800,000,000 Pa`;
- `Nitrogen.json`: N₂ fluid model, CAS `7727-37-9`,
  `BibTeX_EOS = Span-JPCRD-2000`, molar mass `0.02801348 kg/mol`,
  critical state `T = 126.192 K`, `p = 3,395,800 Pa`, and EOS limits
  `T_max = 2000 K`, `p_max = 2,200,000,000 Pa`;
- `mixture_binary_pairs.json`: CO₂/N₂ pair record with
  `Name1 = CarbonDioxide`, `Name2 = Nitrogen`,
  `function = Nitrogen-CarbonDioxide`, `F = 1.0`,
  `betaT = 0.994140013`, `gammaT = 1.107654104`,
  `betaV = 1.022709642`, `gammaV = 1.047578256`, and
  `BibTeX = Gernert-Thesis-2013`;
- `mixture_departure_functions.json`: departure function
  `Name = Nitrogen-CarbonDioxide`, alias `KW5`, `type = GERG-2008`,
  `Npower = 2`, and `BibTeX = Kunz-JCED-2012`.

The teqp repository licence remains the NIST disclaimer of copyright and
warranty. These data are upstream teqp model data; PhaseXpert does not tune
binary interaction parameters, does not substitute CoolProp parameters and does
not claim an independently validated CO₂+N₂ operating range from these records.

## CO₂+N₂ Gate B native layer

The native build now embeds the pinned CO₂, N₂, CO₂/N₂ binary-pair and
CO₂/N₂ GERG-2008 departure-function JSON directly in the XCFramework. The app
does not load model JSON from the filesystem at runtime and does not require
Python, network access or external services on device.

The bridge adds a narrow binary VLE implementation equivalent to teqp
v0.23.1's documented `mix_VLE_Tx` residual system for the concrete
CarbonDioxide + Nitrogen multifluid model. It enforces equality of pressure,
CO₂ chemical potential and N₂ chemical potential between equilibrium phases,
with the Jacobian assembled from teqp's automatic-differentiation Helmholtz
derivatives. The implementation deliberately avoids the broader `teqpcpp`
wrapper path because that path still encounters the AppleClang issue described
below.

For CO₂-rich subcritical initialization, the bridge starts from teqp's pure-CO₂
saturation state and continues through intermediate liquid-phase N₂
compositions before solving the requested `T, x_liquid` point. A companion dew
solve uses the same VLE primitive and brackets liquid composition until the
vapor-phase N₂ composition matches the requested bulk composition.

The native point classifier is retained only as research infrastructure. For a
requested subcritical `P, T, z` CO₂/N₂ state, it calculates bubble pressure at
`x_liquid = z`, dew pressure at `y_vapor = z`, and uses those converged
boundaries only to classify clearly vapor-side, clearly dense/liquid-side or
inside/on-envelope two-phase states. Clearly single-phase states then solve
the homogeneous multifluid EOS for density at the specified overall
composition. Two-phase states return explicit two-phase status and do not
invent a unique homogeneous bulk density or phase fraction. This is not yet a
general T-p-z flash solver. Gate C failed for user-facing CO₂/N₂ support with
the pinned teqp v0.23.1 Gernert/GERG binary model, so this code is not exposed
as a supported teqp mixture domain.

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
headers/schema support, generates traceable C++ headers containing the pinned
CO₂, N₂, CO₂/N₂ binary-pair and CO₂/N₂ departure-function JSON data, and
compiles `Native/TeqpBridge/src/PhaseXpertTeqpBridge.cpp`
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
- CO₂/N₂ binary `mix_VLE_Tx` diagnostics for bridge validation;
- CO₂/N₂ subcritical point classification for validation-gated vapor,
  dense/liquid and two-phase states;
- molar density and root count for bridge diagnostics;
- limited phase state: stable vapor, stable liquid, and supercritical when
  those states are established by the bridge; otherwise `unknown`.

The density solve samples positive molar-density space, brackets sign changes
of teqp pressure minus requested pressure, and then selects a stable branch
only when teqp's pure-fluid stability information can support that choice.
For `T > Tc`, the bridge keeps the single-phase supercritical behavior. For
`T < Tc`, it computes the pure-CO₂ saturation state at the requested
temperature using the pinned teqp CarbonDioxide ancillary saturated liquid and
vapor densities as initial guesses, then solves the same pressure-equality and
chemical-potential-equality residuals documented in teqp v0.23.1
`algorithms/VLE_pure.hpp`. The request pressure is compared with the resulting
`Psat(T)` using `max(1 Pa, 1e-8 * Psat)` as the saturation tolerance. Pressures
clearly below `Psat` select the root closest to teqp's stable saturated-vapor
density; pressures clearly above `Psat` select the root closest to teqp's
stable saturated-liquid density. States on or too close to saturation return
an explicit unavailable/error result because a unique homogeneous bulk density
is not reported there.

The bridge intentionally keeps this VLE solve local and narrow instead of
including teqp's broader `VLE_pure.hpp` header directly, because that header
also includes the unrelated `teqpcpp` and critical-tracing path that failed
the AppleClang feasibility gate. The residual equations and Newton update are
transcribed from the pinned teqp v0.23.1 header and call teqp's own Helmholtz
derivative APIs and CO₂ ancillary data; no CoolProp, hand-coded saturation
correlation or external service is used.

## Supported scope

Supported:

- exactly 100 mol% CO₂;
- density;
- transparently derived molar mass, specific volume and compressibility factor
  through the existing PhaseXpert derived-property layer.

Validation-gated and not yet user-facing:

- CO₂+N₂ binary VLE at subcritical CO₂-rich conditions;
- CO₂+N₂ homogeneous single-phase density when the state is clearly outside
  the two-phase pressure interval established by the native VLE primitive;
- explicit CO₂+N₂ two-phase state classification without bulk density or phase
  fraction.

Unavailable:

- viscosity and all transport properties;
- enthalpy, entropy, internal energy, heat capacities, acoustic properties,
  thermal conductivity and Joule-Thomson coefficient;
- phase envelopes;
- user-facing CO₂+N₂ calculations and all other mixtures through teqp; Gate C
  failed to establish a supported N₂ domain for this pinned binary model.

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

Stable-root regression checks for subcritical CO₂ use teqp equilibrium
internally rather than treating CoolProp as a reference. At 293.15 K, the
bridge calculates `Psat = 5,729,052.58147522 Pa`, saturated liquid density
`773.386541899471 kg/m³`, and saturated vapor density
`194.201601224353 kg/m³`. The reported user case, 293.15 K and 15 MPa, has
three mathematical density roots but is clearly above saturation and returns
the stable liquid density `903.956424708662 kg/m³`. A 293.15 K and 1 MPa vapor
case is clearly below saturation and returns stable vapor density
`19.0985287213064 kg/m³`. A 293.15 K and 6 MPa case that previously failed
because it had multiple mathematical roots now returns stable compressed-liquid
density `782.648269336157 kg/m³`. A request exactly at the calculated
293.15 K saturation pressure still returns the explicit no-unique-homogeneous
density error.

`PhaseXpertTests/TeqpNativeBridgeValidationTests.swift` adds the corresponding
iOS XCTest coverage for `NativeTeqpEngine`. With the generated
framework-style teqp XCFramework present, those tests run in ordinary Xcode app
test builds and exercise Swift calling through `NativeTeqpEngine` into the C
bridge and compiled teqp EOS.

These checks validate only the narrow pure-CO₂ density path at the listed
single-phase points and the conservative saturation-line rejection behavior.
They do not establish production accuracy, phase-boundary accuracy, transport
properties, mixtures, spinodal/metastable behavior, near-critical equilibrium
robustness or physical-iPhone manual acceptance.

Native CO₂+N₂ diagnostic bridge tests cover binary model provenance, exact CO₂/N₂ binary
parameter traceability in the version string, one converged 293.15 K
`mix_VLE_Tx` solve at 3 mol% liquid N₂, equality of the bridge's pressure and
chemical-potential residuals, deterministic repeated VLE solves, invalid
composition and P/T handling, one clear homogeneous gas state, one clear
homogeneous dense state, one supercritical homogeneous state and one explicit
two-phase classification. These tests exercise the algorithmic bridge only;
they are not independent experimental validation and therefore do not open a
supported user-facing CO₂/N₂ range.

## CO₂+N₂ Gate C validation audit

Independent CO₂+N₂ validation was started against tabulated literature data
without enabling any user-facing N₂ support. The first density handoff contained
a provenance error: the 303.22 K, 343.15 K and 383.14 K rows at 4.15 mol% and
9.79 mol% N₂ were incorrectly associated with Mazzoccoli, Bosio and Arato
(2012), DOI `10.1021/je300590v`. That paper covers 273.15 K to 293.15 K,
1 MPa to 20 MPa and CO₂-rich mixtures above 85 mol% CO₂; it does not contain
the high-temperature rows used in that probe.

Those high-temperature rows are from Mantovani, Chiesa, Valenti, Gatti and
Consonni (2012), "Supercritical pressure-density-temperature measurements on
CO₂-N₂, CO₂-O₂ and CO₂-Ar binary mixtures", `Journal of Supercritical Fluids`
61, 34-43, DOI `10.1016/j.supflu.2011.09.001`. Table 2 gives molar
compositions N1 = 0.9585 CO₂ + 0.0415 N₂ and N2 = 0.9021 CO₂ + 0.0979 N₂.
Tables 4 and 5 report density in kg/m³ with stated density uncertainty
`±0.2 kg/m³`. Those rows are valid primary-source records for a diagnostic,
but they are not Mazzoccoli data and should not be used as evidence about
Mazzoccoli agreement.

The corrected primary-source density probe added Brugge, Holste, Hall, Gammon
and Marsh (1997), "Densities of Carbon Dioxide + Nitrogen from 225 K to 450 K
at Pressures up to 70 MPa", `Journal of Chemical & Engineering Data` 42,
903-907, DOI `10.1021/je970044w`. The audited rows are from Table 1, mixture
`xA = 0.90921`. Although the OCR header is ambiguous, the table molar mass
`Mr = 42.5575 g/mol` confirms `xA` is the CO₂ mole fraction, so
`zN₂ = 0.09079`. Table 1 reports molar density in mol/m³; PhaseXpert converts
to kg/m³ with the tabulated mixture molar mass. The paper reports density
accuracy better than `±0.1%`.

The first Brugge run exposed a classifier defect rather than a density-root
failure. `px_teqp_calculate_co2_n2_point` used the pure-CO₂ critical
temperature as the binary phase-topology switch and therefore forced
subcritical bubble/dew continuation for all 300 K CO₂/N₂ states. At
`zN₂ = 0.09079`, the corrected fixed-composition critical solve gives
`Tcrit = 296.236695374 K`, and each 300 K Brugge state has one locally stable
homogeneous EOS root. The bridge now evaluates the mixture critical conditions
from teqp Helmholtz derivatives: the total Helmholtz concentration Hessian
includes residual plus ideal-gas terms, the critical point is solved at fixed
composition by setting the minimum Hessian eigenvalue and the third derivative
along the critical eigenvector to zero, and homogeneous roots are accepted only
when locally stable. If mixture critical topology is unavailable and VLE
topology cannot be established, a single locally stable homogeneous root is
returned with `unknown` phase rather than a fabricated vapor/liquid label.

| Reference point | Source table | T / K | P / MPa | zN₂ | Reference density / kg/m³ | Before fix | After fix teqp density / kg/m³ | Absolute deviation / kg/m³ | Relative deviation |
|---|---|---:|---:|---:|---:|---:|---|---:|---:|---:|
| Brugge low 300 K | Table 1, xCO₂ = 0.90921 | 300.00 | 1.031 | 0.09079 | 18.427397 | VLE-continuation failure | 18.441624941 | 0.014227941 | 0.000772108 |
| Brugge intermediate 300 K | Table 1, xCO₂ = 0.90921 | 300.00 | 7.677 | 0.09079 | 252.791550 | VLE-continuation failure | 251.927159444 | -0.864390556 | -0.003419381 |
| Brugge dense 300 K | Table 1, xCO₂ = 0.90921 | 300.00 | 26.591 | 0.09079 | 854.937617 | VLE-continuation failure | 854.510447034 | -0.427169966 | -0.000499650 |
| Brugge low 320 K | Table 1, xCO₂ = 0.90921 | 320.00 | 1.111 | 0.09079 | 18.512512 | 18.504236 | 18.504235709 | -0.008276291 | -0.000447065 |
| Brugge intermediate 350 K | Table 1, xCO₂ = 0.90921 | 350.00 | 18.865 | 0.09079 | 479.410237 | 478.009731 | 478.009731476 | -1.400505524 | -0.002921309 |
| Brugge dense 400 K | Table 1, xCO₂ = 0.90921 | 400.00 | 68.626 | 0.09079 | 783.015442 | 782.416388 | 782.416388116 | -0.599053884 | -0.000765060 |

Brugge's `±0.1%` statement is experimental measurement accuracy, not an
automatic acceptance threshold for a predictive mixture EOS. The observed
teqp/GERG-type prediction deviation is therefore recorded separately from
measurement uncertainty. The worst Brugge deviation after the classifier fix is
`0.341938%` at 300 K and 7.677 MPa.

Re-audited Mantovani CO₂-rich diagnostic rows provide lower-N₂ coverage at
4.15 mol% N₂ and a second high-N₂ point at 9.79 mol% N₂. They are from
Mantovani Tables 2, 4 and 5, use mole fractions, report density in kg/m³ and
state `±0.2 kg/m³` density uncertainty. The suspicious low-pressure rows were
checked directly against the primary table text: the 383.14 K, about 1 MPa
rows are in the CO₂+N₂ N1/N2 tables, not copied from the CO₂+O₂ or CO₂+Ar
tables, and they are measured experimental densities.

| Reference point | Source table | T / K | P / MPa | zN₂ | Reference density / kg/m³ | teqp density / kg/m³ | Absolute deviation / kg/m³ | Relative deviation |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| Mantovani N1 gas | Tables 2 and 4 | 383.14 | 1.002 | 0.0415 | 13.08 | 13.912941465 | 0.832941465 | 0.063680540 |
| Mantovani N1 supercritical | Tables 2 and 4 | 343.15 | 12.000 | 0.0415 | 305.25 | 311.017446365 | 5.767446365 | 0.018894173 |
| Mantovani N1 dense | Tables 2 and 4 | 303.22 | 12.001 | 0.0415 | 715.67 | 730.139902518 | 14.469902518 | 0.020218680 |
| Mantovani N2 gas | Tables 2 and 5 | 383.14 | 1.000 | 0.0979 | 12.48 | 13.572064197 | 1.092064197 | 0.087505144 |
| Mantovani N2 supercritical | Tables 2 and 5 | 343.15 | 12.002 | 0.0979 | 275.24 | 277.739339622 | 2.499339622 | 0.009080583 |
| Mantovani N2 dense | Tables 2 and 5 | 303.22 | 12.003 | 0.0979 | 599.42 | 598.830599868 | -0.589400132 | -0.000983284 |

An independent direct-upstream teqp probe was then compiled against the same
pinned `v0.23.1` source files and embedded CO₂/N₂ model data, bypassing
`px_teqp_calculate_co2_n2_point` and solving the homogeneous EOS density
directly. The direct teqp densities matched the PhaseXpert bridge densities to
the printed precision for all six Mantovani rows (`direct_minus_bridge = 0`).
The discrepancy is therefore not a PhaseXpert classifier or density-conversion
bug.

| Reference point | Ideal-gas density / kg/m³ | Direct teqp density / kg/m³ | PhaseXpert bridge density / kg/m³ | Experimental density / kg/m³ |
|---|---:|---:|---:|---:|
| Mantovani N1 gas | 13.634040964 | 13.912941465 | 13.912941465 | 13.08 |
| Mantovani N1 supercritical | 182.310470006 | 311.017446365 | 311.017446365 | 305.25 |
| Mantovani N1 dense | 206.335502613 | 730.139902518 | 730.139902518 | 715.67 |
| Mantovani N2 gas | 13.323618011 | 13.572064197 | 13.572064197 | 12.48 |
| Mantovani N2 supercritical | 178.545655484 | 277.739339622 | 277.739339622 | 275.24 |
| Mantovani N2 dense | 202.074554747 | 598.830599868 | 598.830599868 | 599.42 |

Low-density diagnostics at 400 K and 1 MPa showed the native binary density
approaches the ideal-gas limit using the expected mixture molar mass, recovers
the pure-CO₂ limit smoothly as N₂ tends to zero and decreases continuously as
N₂ increases from 1 mol% to 10 mol%. That supports the CO₂/N₂ component order
and mass-density conversion path but is not independent validation.

The VLE probe used Westman, Stang, Løvseth, Austegard, Snustad, Størset and
Ertesvåg (2016), "Vapor-liquid equilibrium data for the carbon dioxide and
nitrogen (CO₂ + N₂) system at the temperatures 223, 270, 298 and 303 K and
pressures up to 18 MPa", `Fluid Phase Equilibria 409`, 207-241,
DOI `10.1016/j.fluid.2015.09.034`. Appendix B states that liquid and vapor
composition sample rows with the same experiment identifier correspond to the
same VLE experiment. The checked 298 K liquid/vapor pair rows therefore remain
traceable table rows rather than graph-digitized points. The source reports
maximum standard uncertainties of 0.006 K, 0.003 MPa and 0.0004 mole fraction,
with the text cautioning that critical-region 298 K and 303 K composition
uncertainties may be larger than the table values.

| Reference pair | T / K | xN₂ reference | yN₂ reference | P reference / Pa | P teqp / Pa | ΔP / Pa | Relative ΔP | yN₂ teqp | ΔyN₂ |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| L18/V20 | 298.158 | 0.00641000 | 0.01826000 | 6,709,000 | 6,710,001.2 | 1,001.2 | 0.00014924 | 0.01834897 | 0.00008897 |
| L20/V22 | 298.161 | 0.01616000 | 0.04048000 | 7,100,300 | 7,101,178.1 | 878.1 | 0.00012367 | 0.04073288 | 0.00025288 |
| L21/V23 | 298.162 | 0.02475000 | 0.05565000 | 7,419,100 | 7,416,718.5 | -2,381.5 | -0.00032099 | 0.05568633 | 0.00003633 |
| L22/V25 | 298.175 | 0.03950000 | 0.07208000 | 7,894,600 | 7,886,844.3 | -7,755.7 | -0.00098241 | 0.07234970 | 0.00026970 |
| L24/V27 | 298.171 | 0.04971000 | 0.07539000 | 8,147,900 | 8,147,186.4 | -713.6 | -0.00008758 | 0.07816210 | 0.00277210 |

The same probe reported native equilibrium residuals at or near zero for all
five Westman points, with worst internal pressure residual `0.00169 Pa`,
worst CO₂ chemical-potential residual `3.2e-7` and worst N₂
chemical-potential residual `3.68e-7`. That confirms the bridge solves its
equilibrium equations, but it does not by itself validate the model for
PhaseXpert use. The fifth Westman comparison still has a material
vapor-composition deviation of `0.00277210` mole fraction N₂ near 5 mol%
liquid N₂, greater than the nominal mole-fraction uncertainty.

After the Mantovani audit, Gate C is no longer blocked by a suspected
transcription error or by the pure-CO₂ critical-temperature bug, but it still
does not establish a useful validated PhaseXpert N₂ range. Mantovani's
4.15 mol% N₂ rows are correctly transcribed and direct upstream teqp agrees
with the PhaseXpert bridge, but the relative deviations remain `1.889%` to
`6.368%` for the gas/supercritical points and `2.022%` for the dense point.
The Brugge 9.079 mol% N₂ matrix converges but has a worst relative deviation
of `0.341938%`. The Westman VLE matrix remains good through about 4 mol%
liquid N₂ but has an unexplained `0.00277210` absolute vapor-composition
discrepancy near 5 mol% liquid N₂. Therefore the validated teqp N₂ range is
empty, PhaseXpert must not expose CO₂+N₂ calculations through teqp, and Gates D
and E must not proceed from this implementation without additional scientific
and numerical investigation.

## Next milestone

The pinned teqp v0.23.1 Gernert/GERG CO₂+N₂ binary model failed Gate C for a
user-facing PhaseXpert N₂ range. Scientifically defensible next options are:

1. evaluate another independently sourced CO₂+N₂ mixture model compatible with
   teqp;
2. evaluate whether a newer or purpose-specific CO₂+N₂ parameterization exists
   with appropriate redistribution rights and independent validation evidence;
3. expand validated pure-CO₂ teqp thermodynamic properties after establishing
   complete definitions, units, basis and reference-state conventions;
4. implement pure-CO₂ teqp saturation and phase-diagram functionality
   independently of N₂.

PhaseXpert should not tune coefficients or fit binary interaction parameters
inside the app without a separate research and validation project.

The active multi-impurity model-selection inventory is maintained in
`Documentation/TeqpMultiImpurityModels.md`.
