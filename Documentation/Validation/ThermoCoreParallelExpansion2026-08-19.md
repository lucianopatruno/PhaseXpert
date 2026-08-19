# Thermodynamic Core Parallel Expansion - 2026-08-19

Starting base: `2126787d96f13ea3b25eff0c113c4bb701d8d348`.

This record captures the scientific decisions for the parallel core expansion
milestone. It does not promote a model from numerical convergence alone.

## Workstream A - Advanced CCS Multicomponent Architecture

Current production Advanced CCS state at the start of the milestone:

| Component set | Density | Phase / VLE | Cp | Cv | Speed of sound | Critical | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CO2 | Enabled | Pure saturation envelope | Enabled | Enabled | Enabled | Pure critical marker through existing envelope endpoint | Preliminary / validation pending |
| CO2 + H2 | Enabled only at xH2 = 0.05362 and validated Souissi et al. 2017 gas isotherm pressure ranges | Unsupported | Unsupported | Unsupported | Unsupported | Unsupported | Limited pass for homogeneous gas density only |
| CO2 + CH4 | Enabled only at xCH4 = 0.05 in encoded Ghafri et al. 2016 density slices | VLE classification/envelope enabled only at xCH4 = 0.05 from 293.13 K to 298.142 K | Unsupported | Unsupported | Unsupported | Unsupported | Limited pass for density and narrow VLE gate |
| CO2 + N2 | Unsupported | Unsupported | Unsupported | Unsupported | Unsupported | Unsupported | Failed validation / diagnostic only |
| CO2 + O2 | Unsupported | Unsupported | Unsupported | Unsupported | Unsupported | Unsupported | Failed validation / diagnostic only |
| CO2 + Ar | Unsupported | Unsupported | Unsupported | Unsupported | Unsupported | Unsupported | Failed validation / diagnostic only |
| Simultaneous impurity mixtures | Unsupported | Unsupported | Unsupported | Unsupported | Unsupported | Unsupported | Unsupported |

Implemented groundwork:

- `CanonicalComposition` preserves all submitted active components, validates
  finite non-negative mole fractions, rejects duplicates, requires the existing
  exact total tolerance, and sorts only by stable `ComponentID` catalog order.
- `AdvancedCCSCapabilityMatrix` returns property-specific support decisions
  with validation state, formulation identifier, phase domain, and rejection
  reasons.
- `TeqpProvider` rejects ternary and larger Advanced CCS mixtures before any
  native engine call and includes all active components in the rejection reason.

No ternary or quaternary Advanced CCS production calculation is enabled in this
milestone because the current native ABI exposes only pure CO2 and binary
formulation calls, and no independent multicomponent validation gate exists.

## Workstream B - Additional Advanced CCS Impurities

| Impurity | Models investigated | Evidence | Decision |
| --- | --- | --- | --- |
| O2 | Pinned teqp Gernert/multifluid and EOS-CG-2021 CO2+O2 reducing-parameter model with Fij = 0 and no departure function | Mantovani et al. 2012 PVT audit converged 6/6 but failed density gate: AARD 7.3878%, worst relative density deviation 14.8035% | Reject / no defensible production model |
| Ar | Pinned teqp Gernert/GERG and EOS-CG-2021 CO2+Ar model with Lovseth GERG-2008 departure function | Mantovani et al. 2012 broad density gate failed: AARD 3.40533%, worst relative deviation 9.99102%; low-Ar subset remains diagnostic only without VLE gate | Research only |
| CO | No Advanced CCS native/teqp formulation or validation artifact found; CoolProp preliminary support does not count as Advanced validation | No committed CO2+CO Advanced PVT/VLE validation matrix | Reject / no defensible model |
| H2S | No Advanced CCS native/teqp formulation or validation artifact found; CoolProp preliminary support does not count as Advanced validation | No committed CO2+H2S Advanced PVT/VLE validation matrix | Reject / no defensible model |

No new Advanced impurity is promoted.

## Workstream C - Water Thermodynamics

`ComponentID.water` exists, but neither production provider supports H2O today.

General Properties / CoolProp: not enabled. The current native CoolProp bridge
is scoped to pure CO2 and dry CO2 mixtures and has no proven iOS ABI for water,
wet CO2 mixtures, water dew, aqueous split, or mutual solubility. Homogeneous
HEOS mixture execution, even if later made to run, must not be presented as a
rigorous aqueous equilibrium model without separate validation.

Advanced CCS / teqp: not enabled. The current teqp inventory and bridge expose
CO2, N2, O2, Ar, H2, and CH4 model paths only. No CO2+H2O formulation,
coefficient provenance, binary interaction provenance, water solubility gate,
aqueous-phase model, or validation artifact is present.

Production status: water remains unsupported in both General Properties and
Advanced CCS Properties in this milestone.

## Workstream D - Aqueous Chemistry / pH

pH is applicable only to an aqueous phase. It must not be assigned to dry gas,
dense CO2 without aqueous water, or a generic homogeneous EOS state.

Recommended architecture: add a separate aqueous-chemistry provider family in
`PhaseXpertCore`, beside thermodynamic model providers, with explicit inputs
for aqueous phase basis, dissolved CO2 or gas/liquid boundary condition, water
amount/activity model, salinity/ionic strength, alkalinity or charge-balance
basis, temperature, pressure only within the selected constants' validity range,
and cited equilibrium/solubility constants.

No production pH implementation or prototype is added because the repository
contains no sourced carbonate-equilibrium constants, activity model, Henry-law
or solubility model, validation dataset, or license-reviewed chemistry library.

Production status: research-only.
