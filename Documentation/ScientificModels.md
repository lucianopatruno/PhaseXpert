# Scientific models

## What CoolProp is

CoolProp is an open-source C++ thermophysical-property library with wrappers
for several languages. Its HEOS backend implements high-accuracy equations of
state for supported pure fluids and mixture calculations for supported binary
pairs. Its presence alone is not evidence that a particular CO₂-rich
multicomponent mixture, transport property or phase envelope is validated for
IFE's intended use.

The approved spike is therefore restricted:

- no production accuracy claim;
- no silent fallback to an incompletely supported backend;
- each mixture pair and requested property must pass capability checks;
- results remain visibly preliminary until independent comparison is complete;
- licence texts, notices, binary architecture and App Store packaging are
  reviewed before distribution.

The pure-CO₂ provider, restricted dry CO₂-rich mixture path, native C bridge and reproducible
build script are included. The generated CoolProp binary is intentionally not
committed; when built at the documented local path it is linked conditionally
for iOS.

An experimental native teqp provider is also scaffolded for exactly 100 mol%
CO₂. It is not the default provider. It solves density locally through teqp's
pinned pure-CO₂ multifluid model and reports viscosity and broader properties
as unavailable rather than borrowing them from CoolProp. The native bridge also
contains validation-gated CO₂+N₂ binary VLE and subcritical point-classification
primitives built from pinned upstream teqp data; these are not yet a
user-facing supported mixture domain.

## Alternatives considered

| Option | Strengths | Principal limitations for this app |
|---|---|---|
| CoolProp HEOS | Offline, open source, broad property API, C++ core | Mixture-pair/transport coverage varies; iOS build and validation work required |
| teqp | Offline C++ equation-of-state framework with native pure-CO₂ and validation-gated CO₂+N₂ bridge code in PhaseXpert | Experimental in PhaseXpert; user-facing scope is only pure-CO₂ density, with viscosity, phase envelopes and mixtures unavailable until independent validation passes |
| REFPROP | Strong reference implementation and broad property coverage | Proprietary licence; redistribution and iOS embedding require explicit NIST permission/terms |
| GERG-2008 implementation | Strong basis for natural-gas-like mixtures and phase behaviour | Component set and CO₂-rich impurity coverage are limited; implementation/data licensing and edge-domain validation required |
| Cubic EOS such as Peng–Robinson | Compact, offline and phase-equilibrium capable | Needs sourced pure-component data and binary interaction parameters; density and transport accuracy may be inadequate without validated corrections |
| IFE-controlled API | Central model governance and rapid updates | Network, security, availability, privacy and server validation obligations |

Recommended sequence: use CoolProp only as an integration and comparison spike;
retain the provider abstraction; make the production model decision after
reference validation and legal review. REFPROP is valuable as an independent
comparison tool if IFE has an appropriate licence, but should not be embedded
without explicit redistribution rights.

## Initial engineering domain

The UI input envelope is −55–150 °C and 0.8–300 bar absolute. It is an
engineering scope for test planning, not a validated model-accuracy statement.

| Scenario | Temperature | Absolute pressure |
|---|---:|---:|
| Ship transport | −55 to +15 °C | 5 to 70 bar abs |
| Dense-phase pipeline | 0 to 50 °C | 70 to 300 bar abs |
| Capture/compression | 0 to 150 °C | 0.8 to 300 bar abs |

The current executable dry-mixture scope accepts 90–100 mol% CO₂ with any
combination of N₂, O₂, Ar, CH₄ and H₂ and applies a temporary maximum of
10 mol% total impurity. The cap is a software-product guardrail, not a validated
accuracy statement. Wet, acid-gas and heavier-hydrocarbon components remain
unsupported until their executable model paths and validation evidence exist.

Candidate identifiers currently scaffolded are CO₂, N₂, O₂, Ar, H₂O, CH₄, H₂,
CO, H₂S, He, ethane and propane. This is not a claim of calculation support.
SO₂, NO, NO₂, NH₃, Ne, Kr and Xe are intentionally omitted until the chosen
provider proves support.

## Planned property stages

1. Phase/region, density and dynamic viscosity.
2. Molar mass, compressibility factor and specific volume. **Implemented as
   explicit derived properties for the executable pure and dry-mixture paths.**
3. Enthalpy, entropy, internal energy, heat capacities, speed of sound,
   thermal conductivity and Joule–Thomson coefficient. **Implemented for pure
   CO₂ as preliminary CoolProp outputs; independent validation remains open.**
4. Response properties and vapour/liquid fractions where the provider defines
   them unambiguously.

Every value carries one of: calculated, unavailable, outside validated range,
extrapolated, or failed. Unsupported values never receive fabricated numbers.

## Reporting safeguards

Pairwise comparison reports use the immutable saved calculation records on
both sides. Every numeric difference is defined as compared minus reference;
the report never ranks the models or implies that the smaller or larger value
is more accurate. PDF and CSV output retain units, status, warnings, model and
provider versions, provenance and calculation/request identifiers.

Property-sweep PDF charts use only finite values whose recorded status is
calculated. Straight segments are drawn only between adjacent successful
provider samples. A failed, unavailable or non-finite sample breaks the path;
PhaseXpert never fills the gap or interpolates a scientific value. The chart
is a visualization of the serialized provider responses, not an accuracy or
validation claim.

## Phase-envelope approach

The selected provider must generate the envelope from equilibrium calculations.
For a flash-based implementation, use continuation along bubble and dew
branches, warm-start adjacent points, bracket temperature or pressure roots,
limit iterations, reject non-finite fugacity residuals, and record tolerances,
iteration counts and failures. Detect the critical region using provider
capabilities rather than joining curves cosmetically.

The UI will use Swift Charts for the resulting provider points and an overlay
gesture for pan/zoom and point inspection. If the provider returns no envelope,
the chart stays unavailable. No decorative curve is permitted.

### Implemented preliminary phase boundaries

The CoolProp provider now exposes a narrower pure-fluid operation. For exactly
100 mol% CO₂, it obtains triple-point temperature, critical temperature and
critical pressure from the linked CoolProp release, then evaluates saturation
pressure with `PropsSI(P,T,Q=0)` at ordered temperatures strictly inside those
limits. For a pure fluid, the bubble and dew pressures coincide; PhaseXpert
therefore plots one **pure CO₂ saturation boundary**, not two visually separate
branches and not an enclosed mixture phase envelope.

Every returned temperature and pressure must be finite and positive, and
pressure must increase with the sampled temperature. Any failed, non-finite or
non-monotonic point rejects the complete curve so the UI cannot connect across
a numerical gap. The critical point is a separate provider value. Straight
line segments between calculated points are a display operation only.

The result remains preliminary and validation-pending. Independent
saturation-pressure reference cases have not yet been accepted, so the curve
must not be used for engineering, safety, commercial or regulatory decisions.
For an accepted dry CO₂-rich composition, the native bridge creates one HEOS
`AbstractState`, applies the exact mole fractions and calls CoolProp's low-level
`build_phase_envelope` routine. PhaseXpert accepts the trace only when every finite positive point lies inside
the declared 0.8–300 bar(a), −55–150 °C app domain and the returned bubble/dew
branches remain usable. A single out-of-domain point rejects the full trace.
PhaseXpert does not clip, insert scientific samples, reconnect gaps, close
branches cosmetically or replace a failed envelope. The unavailable IFE provider returns no boundary.

No independent mixture bubble/dew reference cases or tolerances have been
approved. These envelopes are provider outputs, not validated PhaseXpert data.

### Implemented restricted dry CO₂-rich calculation

Provider version 0.8.2 admits 100 mol% CO₂ or dry mixtures containing CO₂ plus
one or more of N₂, O₂, Ar, CH₄ and H₂. CO₂ must be uniquely largest, the
fractions must sum explicitly to one, and total impurity must be in (0, 0.10].
The upper bound is a temporary PhaseXpert product guardrail and is not presented
as a validated model-accuracy range.

The native bridge constructs fluid identifiers from a fixed component list and
uses only mixture interaction entries shipped with pinned CoolProp 8.0.0.
PhaseXpert never calls CoolProp's estimated simple mixing rule, never overwrites
binary interaction parameters, never silently normalizes fractions and has no
fallback correlation. A missing pair or numerical failure is returned as a
calculation failure.

Mixture output remains limited to density, provider phase, and the transparent
derived values M, v and Z. Mixture viscosity, caloric, acoustic, conductivity,
derivative properties are deliberately unavailable. Phase envelopes use the
provider routine described above and remain validation pending. Mixture
boundaries use CoolProp's native HEOS density continuation, starting at the
declared 0.8 bar(a) PhaseXpert minimum and with optional refinement disabled.
The pinned CoolProp 8.0.0 source contains an unbounded `for (;;)` continuation
whose only normal exits require pressure closure or an almost-pure incipient
phase. The tracked PhaseXpert downstream patch caps that loop at 256
successfully calculated provider steps. Reaching the cap leaves the provider
trace incomplete and open. The provider exposes it only if every returned point
also remains inside the declared app domain; otherwise the diagram is explicitly
unavailable. PhaseXpert does not clip, interpolate, extrapolate or cosmetically
close the trace.
Every result records exact composition, library/provider version, method and
validation-pending warnings. Contract coverage is not independent numeric
validation.

### Implemented derived engineering properties

PhaseXpert derives three values after a provider returns a finite, positive
calculated density. These are transparent post-processing definitions, not
additional CoolProp equation-of-state calls:

- mixture molar mass: M = Σ xᵢMᵢ;
- specific volume: v = 1/ρ;
- compressibility factor: Z = pM/(ρRT), using
  R = 8.31446261815324 J/(mol·K).

Calculations use Pa, K, kg/m³ and kg/mol internally. Molar mass is presented in
g/mol, specific volume in m³/kg, and Z is dimensionless. CO₂, N₂, O₂, Ar, CH₄ and H₂ molecular weights are recorded
from NIST Chemistry WebBook SRD 69 (DOI `10.18434/T4D303`). The gas constant is the NIST 2022
CODATA value. A component without reviewed molar-mass data produces an
unavailable result; an invalid pressure, temperature or density produces a
failed result. Inputs are never normalized in this layer. The values inherit
the preliminary validation status of the provider density and composition.


### Implemented expanded pure-CO₂ state

Provider version 0.6.0 uses one CoolProp HEOS AbstractState update at the
recorded pressure and temperature for exactly 100 mol% CO₂. It returns
mass-specific enthalpy, entropy and internal energy, Cp, Cv, speed of sound,
thermal conductivity and the single-phase Joule–Thomson derivative. PhaseXpert
derives Cp/Cv and converts the derivative from K/Pa to °C/bar for display.

All native outputs must be finite. Density, viscosity, Cp, Cv, speed of sound
and conductivity must also be positive; caloric values and the Joule–Thomson
coefficient remain signed. Missing or malformed values are never replaced by
plausible numbers. Enthalpy, entropy and internal energy retain CoolProp's
default reference state, which is recorded in warnings and provenance.

CoolProp identifies Span and Wagner (1996), DOI 10.1063/1.555991, as the CO₂
equation of state; Huber et al. (2016), DOI 10.1063/1.4940892, for thermal
conductivity; and Laesecke and Muzny (2017), DOI 10.1063/1.4977429, for
viscosity. Formulation traceability is not an accuracy-validation claim.
Expanded properties remain unavailable for every mixture.
