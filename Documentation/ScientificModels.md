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

The pure-CO₂ provider, restricted CO₂-N₂ path, native C bridge and reproducible
build script are included. The generated CoolProp binary is intentionally not
committed; when built at the documented local path it is linked conditionally
for iOS.

## Alternatives considered

| Option | Strengths | Principal limitations for this app |
|---|---|---|
| CoolProp HEOS | Offline, open source, broad property API, C++ core | Mixture-pair/transport coverage varies; iOS build and validation work required |
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

The current executable mixture spike accepts 90–100 mol% CO₂ with N₂ as the
only impurity and applies a temporary maximum of 10 mol% N₂. This cap is a
software-integration boundary, not a validated accuracy statement. Other
component-specific maxima must come from source data and model validation.

Candidate identifiers currently scaffolded are CO₂, N₂, O₂, Ar, H₂O, CH₄, H₂,
CO, H₂S, He, ethane and propane. This is not a claim of calculation support.
SO₂, NO, NO₂, NH₃, Ne, Kr and Xe are intentionally omitted until the chosen
provider proves support.

## Planned property stages

1. Phase/region, density and dynamic viscosity.
2. Molar mass, compressibility factor and specific volume. **Implemented as\n   explicit derived properties for the executable CO₂ and CO₂-N₂ paths.**
3. Enthalpy, entropy, internal energy, heat capacities, speed of sound and
   thermal conductivity where validated.
4. Response properties and vapour/liquid fractions where the provider defines
   them unambiguously.

Every value carries one of: calculated, unavailable, outside validated range,
extrapolated, or failed. Unsupported values never receive fabricated numbers.

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

### Implemented preliminary pure-CO₂ boundary

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
Mixtures and the unavailable IFE provider return no boundary.

### Implemented restricted CO₂-N₂ calculation

Provider version 0.5.0 admits exactly two executable composition families:

- 100 mol% CO₂, retaining the existing density, viscosity and saturation path;
- a binary CO₂-N₂ mixture with CO₂ uniquely largest and
  `0 < x(N₂) <= 0.10`, returning density and provider phase only.

The binary calculation uses CoolProp HEOS and only the CO₂-N₂ interaction data
shipped with the pinned CoolProp 8.0.0 release. PhaseXpert supplies explicit
mole fractions and never enables CoolProp's estimated simple mixing rules or
overwrites pair parameters. If the pair data is unavailable or calculation
fails, the request fails; there is no fallback correlation.

Mixture dynamic viscosity and mixture phase envelopes are deliberately
unavailable. All binary results carry validation-pending warnings, the exact
model/library version and the numerical method. The implementation has
contract and serialization tests but no independently sourced numeric
acceptance cases yet; see `ValidationStrategy.md`.

CoolProp 8.0.0 identifies Span and Wagner (1996), DOI
`10.1063/1.555991`, as the equation-of-state reference for its carbon-dioxide
fluid implementation. PhaseXpert records that source with the provider
metadata; citing the formulation does not constitute independent validation of
the compiled implementation.


### Implemented derived engineering properties

PhaseXpert derives three values after a provider returns a finite, positive
calculated density. These are transparent post-processing definitions, not
additional CoolProp equation-of-state calls:

- mixture molar mass: M = Σ xᵢMᵢ;
- specific volume: v = 1/ρ;
- compressibility factor: Z = pM/(ρRT), using
  R = 8.31446261815324 J/(mol·K).

Calculations use Pa, K, kg/m³ and kg/mol internally. Molar mass is presented in
g/mol, specific volume in m³/kg, and Z is dimensionless. CO₂ (44.0095 g/mol)
and N₂ (28.0134 g/mol) molecular weights are recorded from NIST Chemistry
WebBook SRD 69. A component without reviewed molar-mass data produces an
unavailable result; an invalid pressure, temperature or density produces a
failed result. Inputs are never normalized in this layer. The values inherit
the preliminary validation status of the provider density and composition.
