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

No CoolProp source or binary is included in the current milestone.

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

The UI input envelope is 218.15–423.15 K and 0.08–30 MPa absolute. It is an
engineering scope for test planning, not a validated model-accuracy statement.

| Scenario | Temperature | Absolute pressure |
|---|---:|---:|
| Ship transport | −55 to +15 °C | 0.5 to 7 MPa |
| Dense-phase pipeline | 0 to 50 °C | 7 to 30 MPa |
| Capture/compression | 0 to 150 °C | 0.08 to 30 MPa |

The first validation target is 90–100 mol% CO₂, at most 10 mol% total
impurities and at most 20 impurity entries. Component-specific maxima are not
yet defined and must come from source data and model validation.

Candidate identifiers currently scaffolded are CO₂, N₂, O₂, Ar, H₂O, CH₄, H₂,
CO, H₂S, He, ethane and propane. This is not a claim of calculation support.
SO₂, NO, NO₂, NH₃, Ne, Kr and Xe are intentionally omitted until the chosen
provider proves support.

## Planned property stages

1. Phase/region, density and dynamic viscosity.
2. Molar mass, compressibility factor and specific volume.
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

