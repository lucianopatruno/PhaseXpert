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

## Second-Generation Audit - Multicomponent Advanced CCS

EOS-CG-2021 is mathematically an N-component Helmholtz mixture model built
from all binary-specific constituent models. Neumann et al. describe the full
mixture model as the combination of binary models, and state that the approach
makes multicomponent mixture-property calculations possible. They also state
that all possible binary combinations are required, with simple predictive
combining rules used only when a binary-specific model cannot be correlated.
PhaseXpert must not substitute those default/predictive rules without an
explicit scientific gate.

Current PhaseXpert native status:

- `PhaseXpertTeqpBridge` exposes pure CO2, CO2+N2 diagnostic point/VLE, and
  binary EOS-CG CO2+H2 and CO2+CH4 density/diagnostic functions.
- The public Swift `TeqpEngine` protocol exposes no arbitrary-length
  composition vector or N-component teqp entry point.
- The bridge explicitly throws for thermodynamic properties and critical
  diagnostics outside EOS-CG CO2+H2 and CO2+CH4 binaries.
- `EOSCG2021TargetModelData.json` currently records CO2+N2, CO2+O2, CO2+Ar,
  CO2+H2 and CH4+CO2 target pairs, but not N2+CH4, N2+H2 or H2+CH4.

Ternary target conclusion:

| Target | Required pairs | PhaseXpert pair status | Decision |
| --- | --- | --- | --- |
| CO2 + N2 + CH4 | CO2+N2, CO2+CH4, N2+CH4 | CO2+N2 failed current Advanced gate; CO2+CH4 has limited binary gates; N2+CH4 is not encoded in PhaseXpert target data; no N-component bridge ABI | Unsupported |
| CO2 + N2 + CH4 + H2 | CO2+N2, CO2+CH4, CO2+H2, N2+CH4, N2+H2, CH4+H2 | CO2+H2 density-only binary gate; multiple impurity-impurity pairs absent; no N-component bridge ABI | Unsupported |

Independent validation exists for the ternary CO2+N2+CH4 VLE system: Ottøy et
al. measured 62 dew/bubble points from 223 K to 298 K and 0.8 MPa to 9.3 MPa
and compared them with EOS-CG-2019, reporting composition deviations below
0.5 mol% liquid and 1.0 mol% vapor. PhaseXpert does not yet encode these
validation rows or the required N2+CH4 pair, so no ternary diagnostic or
production calculation was implemented.

## Second-Generation Audit - Additional Advanced Impurities

| Impurity | Candidate model | Pure EOS / binary interaction provenance | Data located | Validation outcome | Status |
| --- | --- | --- | --- | --- | --- |
| O2 | EOS-CG/Gernert CO2+O2 with Fij = 0 and no departure function; newer O2-rich density papers are validation data rather than a new PhaseXpert model | CO2 Span-Wagner; O2 Schmidt/Stewart; EOS-CG/Gernert reducing parameters | Existing Mantovani 2012 PVT audit; Lozano-Martin/Staubach O2-rich PVT literature found | Existing PhaseXpert direct teqp density audit failed: 6/6 converged, AARD 7.3878%, worst 14.8035%. New literature is not CO2-rich low-O2 transport validation and does not repair the model gate. | No defensible model found |
| Ar | EOS-CG-2021 CO2+Ar update with Løvseth et al. departure function | CO2 Span-Wagner; Ar Tegeler; EOS-CG Table 4 and Løvseth/GERG-2008 departure | Existing Mantovani 2012 PVT audit; Løvseth CO2+Ar model paper located | Existing broad gate failed: AARD 3.40533%, worst 9.99102%; low-Ar subset worst about 0.731526% over only 3 points and no VLE gate. | Research only |
| CO | EOS-CG-2021 reports CO as a covered CCS component; CoolProp v8 has CO2+CO binary pair data | PhaseXpert has no native teqp CO2+CO model data/bridge path; CoolProp pair is General-provider evidence only | CO2+CO density and VLE literature found, including high-pressure density and Chapoy 2020 VLE | No PhaseXpert Advanced formulation or validation harness exists; no coefficients were imported or audited. | No defensible model found |
| H2S | EOS-CG-2021 reports H2S extension; acid-gas CO2/H2S/H2O/brine literature exists | PhaseXpert has no native teqp CO2+H2S model data/bridge path | CO2+H2S VLE/solubility literature found | No PhaseXpert Advanced formulation or validation harness exists; H2S must not be inferred from CoolProp or molar mass. | No defensible model found |

No additional Advanced impurity was enabled.

## Second-Generation Audit - General H2O / CoolProp

Pinned CoolProp v8.0.0 source at commit
`ae81610e7d23efc57f9d051c8e70a4d66e87537f` contains:

- `dev/fluids/Water.json`, with the Wagner-Pruss 2002 water EOS.
- `dev/mixtures/mixture_binary_pairs.json`, with a `CarbonDioxide` + `Water`
  pair using `CarbonDioxide-Water`, `F = 1`, `betaT = 1.030538`,
  `betaV = 1.021392`, `gammaT = 0.828472`, and `gammaV = 0.895156`.

CoolProp's own 8.0.0 mixture documentation says mixture calculations need
binary-pair information for each pair, only a limited set of mixture input
pairs is available, and estimation schemes should be used with extreme
caution. The documentation also describes a PT flash, but PhaseXpert PR #49
specifically removed unsafe high-level mixture PT/PhaseSI paths from Phase
Map. A CO2+Water binary pair therefore establishes only that CoolProp contains
some homogeneous/mixture machinery; it does not validate aqueous split, mutual
solubility, water dew/dropout, or pH.

PhaseXpert implementation blocker:

- The native `PhaseXpertCoolPropBridge` ABI is explicitly an 8-component dry
  CO2 mixture vector ordered CO2, N2, O2, Ar, CH4, H2, CO and H2S.
- `CoolPropProvider.supportedDryComponents` excludes `.water`.
- No native iOS bridge function exists for wet mixtures, water-rich aqueous
  phase, water dew, or mutual solubility.

General H2O remains unsupported. A future limited homogeneous General H2O
route would require a new wet-mixture ABI, iOS robustness tests, explicit
single-phase/homogeneous labeling, and validation that prevents users from
mistaking it for aqueous equilibrium.

## Second-Generation Audit - Advanced H2O

Candidate model classes located:

- EOS-CG / Gernert-Span humid-gas and CCS Helmholtz mixture model, including
  CO2+H2O in the original model and EOS-CG-2021 scope.
- Spycher-Pruess style mutual-solubility/phase-partitioning models for
  CO2-H2O and CO2-brine systems.
- Duan-Sun solubility models for CO2 in pure water and aqueous NaCl over
  broad T/P/salinity ranges.
- CPA/activity-coefficient approaches for CO2-water/brine density, solubility
  and enthalpy.

No Advanced H2O production capability was implemented because PhaseXpert does
not currently encode the EOS-CG CO2+H2O target coefficients in its native teqp
target-data file, has no water fluid path in the teqp bridge, and has no
validation matrix for H2O-in-CO2-rich phase, CO2-in-water-rich phase, water
dew/dropout, aqueous phase appearance, or density. Solubility-specific models
such as Spycher-Pruess or Duan-Sun are promising for future aqueous-phase
work, but they are not drop-in replacements for the dry Advanced EOS provider
and need separate units, activity conventions, brine inputs, and validation.

Advanced H2O remains unsupported.

## Second-Generation Audit - Aqueous Chemistry / pH

Recommended architecture remains:

`ThermodynamicModelProvider` for EOS/phase behavior plus a separate
aqueous-chemistry/speciation provider for aqueous phase composition, pH and
ionic species.

PHREEQC is a strong candidate for future research because USGS describes it as
a C/C++ program for aqueous geochemical calculations with ion-association,
Pitzer, SIT, gas, mineral and pressure/temperature capabilities, and lists its
usage as public domain. iOS feasibility still requires a separate binary-size,
database-size, threading, C++ runtime and licensing audit.

Minimum production inputs for pH:

- distinct aqueous phase presence and amount;
- dissolved CO2 or an equilibrium boundary condition to a CO2-rich phase;
- temperature;
- pressure when equilibrium constants or gas solubility depend on it;
- activity model and pH convention;
- salinity/ionic strength, alkalinity and major ions for realistic brines;
- H2S concentration/phase equilibrium before sulfide speciation is enabled.

Pure-water CO2 pH may be a useful first research prototype only after a
validated dissolved-CO2 input is available. It should report whether pH is
concentration-based or activity-based. Brine and H2S should be later extensions
because salinity changes activity coefficients and H2S adds HS- and S2-
equilibria plus additional acid-gas solubility coupling.
