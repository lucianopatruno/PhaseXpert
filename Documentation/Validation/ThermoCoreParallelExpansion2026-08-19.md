# Thermodynamic Core Parallel Expansion - 2026-08-19

Starting base: `2126787d96f13ea3b25eff0c113c4bb701d8d348`.

This record captures the scientific decisions for the parallel core expansion
milestone. It does not promote a model from numerical convergence alone.

## Workstream A - Advanced CCS Multicomponent Architecture

Corrected current Advanced CCS state at the start of the milestone:

| Component | Selectable / visible in Advanced composition surface | Formulation present for diagnostics | Production density | Production phase / VLE | Production caloric / acoustic | Validation status | Exact gate |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CO2 | Yes | Yes | Yes | Yes, pure saturation envelope only | Yes for density-derived pure CO2 Cv, Cp, Cp/Cv and speed of sound; h/u/s and transport unavailable | Preliminary / validation pending | Pure CO2 inside provider P/T domain, with subcritical saturation-near states reported unavailable when no unique homogeneous density exists |
| N2 | Yes as a component identity and surveyed Advanced impurity; user-facing Advanced calculations with CO2+N2 are rejected | Yes, `co2NitrogenGernertGergDiagnostic`, status `failedValidation`, plus native CO2/N2 diagnostic point/VLE bridge | No | No | No | Failed validation / diagnostic only | No production gate; the app may let users specify N2, but `TeqpProvider.applicabilityIssues` and `calculate` reject CO2+N2 with no CoolProp fallback |
| CH4 | Yes | Yes, EOS-CG-2021/GERG diagnostic and production density/VLE metadata | Yes | Yes, narrow VLE classification/envelope only | No production caloric/acoustic; hidden diagnostics only | Limited production | xCH4 = 0.05 exactly; density in encoded Ghafri et al. 2016 slices; VLE from 293.13 K to 298.142 K inside Petropoulou et al. 2018 ordinary VLE bounds |
| H2 | Yes | Yes, EOS-CG-2021 diagnostic and production density metadata | Yes | No | No production caloric/acoustic; hidden diagnostics only | Limited production | xH2 = 0.05362 exactly; homogeneous gas density on Souissi et al. 2017 273.15 K, 293.15 K and 323.15 K isotherms within observed gas-pressure ranges |
| O2 | Yes as a component identity and surveyed Advanced impurity; production Advanced route rejects it | Yes, Gernert and EOS-CG-2021 diagnostics | No | No | No | Failed validation / diagnostic only | No production gate |
| Ar | Yes as a component identity and surveyed Advanced impurity; production Advanced route rejects it | Yes, Gernert and EOS-CG-2021 diagnostics | No | No | No | Failed validation / research only | No production gate; low-Ar evidence remains density-only diagnostic |
| CO | No Advanced production support; component exists for General dry-mixture workflows | No PhaseXpert Advanced native route | No | No | No | Unsupported | No production gate |
| H2S | No Advanced production support; component exists for General dry-mixture workflows | No PhaseXpert Advanced native route | No | No | No | Unsupported | No production gate |
| H2O | No Advanced production support; component identity exists | No PhaseXpert Advanced native route | No | No | No | Unsupported | No production gate |
| Simultaneous impurities | Composition can be represented by `CanonicalComposition`; Advanced production calculations are rejected | Pinned upstream teqp can construct generic multifluid models from complete pair data, but PhaseXpert has no linked N-component provider route or validation gate | No | No | No | Unsupported | No production gate |

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
milestone. EOS-CG-2021 itself is a multicomponent Helmholtz-energy CCS mixture
model, but the current PhaseXpert production ABI exposes only pure CO2 and
selected binary formulation calls, and no independent multicomponent validation
gate has been encoded.

## Workstream B - Additional Advanced CCS Impurities

| Impurity | Models investigated | Evidence | Decision |
| --- | --- | --- | --- |
| O2 | Pinned teqp Gernert/multifluid and EOS-CG-2021 CO2+O2 reducing-parameter model with Fij = 0 and no departure function | Mantovani et al. 2012 PVT audit converged 6/6 but failed density gate: AARD 7.3878%, worst relative density deviation 14.8035% | Reject / no defensible production model |
| Ar | Pinned teqp Gernert/GERG and EOS-CG-2021 CO2+Ar model with Lovseth GERG-2008 departure function | Mantovani et al. 2012 broad density gate failed: AARD 3.40533%, worst relative deviation 9.99102%; low-Ar subset remains diagnostic only without VLE gate | Research only |
| CO | Pinned upstream teqp has CO pure-fluid data and a CO2+CO pair record, but PhaseXpert has no linked Advanced native route or validation artifact; CoolProp preliminary support does not count as Advanced validation | No committed CO2+CO Advanced PVT/VLE validation matrix | Reject / no defensible production model |
| H2S | Pinned upstream teqp has H2S pure-fluid data and a CO2+H2S pair record, but PhaseXpert has no linked Advanced native route or validation artifact; CoolProp preliminary support does not count as Advanced validation | No committed CO2+H2S Advanced PVT/VLE validation matrix | Reject / no defensible production model |

No new Advanced impurity is promoted.

## Workstream C - Water Thermodynamics

`ComponentID.water` exists, but neither production provider supports H2O today.

General Properties / CoolProp: not enabled. The current native CoolProp bridge
is scoped to pure CO2 and dry CO2 mixtures and has no proven iOS ABI for water,
wet CO2 mixtures, water dew, aqueous split, or mutual solubility. Homogeneous
HEOS mixture execution, even if later made to run, must not be presented as a
rigorous aqueous equilibrium model without separate validation.

Advanced CCS / teqp: not enabled. Pinned upstream teqp contains H2O pure-fluid
data and a CO2+H2O pair with `CarbonDioxide-Water` departure terms, and a
generic upstream construction probe can assemble wet multifluid systems. The
current PhaseXpert generated teqp bridge still exposes CO2, N2, O2, Ar, H2 and
CH4 model paths only; it has no linked wet-mixture ABI, water solubility gate,
aqueous-phase model, or validation artifact.

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
- `EOSCG2021TargetModelData.json` currently records only a 6-component
  PhaseXpert target subset for prior binary work. Pinned upstream teqp v0.23.1
  data contain all 9 pure-fluid files requested for this continuation and at
  least one binary-pair record for all 36 pairs in the 9-component subset, but
  those records have not all been imported into the PhaseXpert generated model
  header or validated for production gates.

Pinned upstream teqp audit:

| Item | Result |
| --- | --- |
| teqp revision | `a68eb9cabf47af2c4aba0d272ac10fbca4c10eca` (`v0.23.1`) |
| Pure-fluid files found | CO2, N2, CH4, H2, O2, Ar, CO, H2S, H2O |
| Requested pair records found | 36 / 36 in `teqp/fluiddata/dev/mixtures/mixture_binary_pairs.json` |
| Departure functions found in requested subset | CO2+N2, CO2+CH4, CO2+Ar, CO2+H2O, N2+CH4, CH4+H2, generalized air-water pairs for N2/O2/CO with H2O |
| Construction probe | PASS for CO2+N2+CH4, CO2+N2+O2, CO2+N2+Ar, CO2+N2+H2, CO2+N2+CH4+H2, CO2+N2+O2+Ar and the full 9-component set using `teqp::build_multifluid_model` |
| Production implication | Construction proves teqp can assemble an N-component multifluid object from upstream data; it is not density, VLE, phase, caloric, acoustic or aqueous validation |

The 36 requested pair records found in pinned upstream teqp are:

| Pair | Upstream pair record / departure status |
| --- | --- |
| CO2+N2 | Gernert/GERG record, `F=1`, departure `Nitrogen-CarbonDioxide` |
| CO2+CH4 | GERG record, `F=1`, departure `Methane-CarbonDioxide` |
| CO2+H2 | GERG/Kunz-cited record, `F=0`, no departure in pinned upstream data |
| CO2+O2 | Gernert record, `F=0`, no departure |
| CO2+Ar | Gernert/Lovseth-style record, `F=1`, departure `Argon-CarbonDioxide` |
| CO2+CO | Gernert record, `F=0`, no departure |
| CO2+H2S | Kunz-cited record, `F=0`, no departure |
| CO2+H2O | Gernert record, `F=1`, departure `CarbonDioxide-Water` |
| N2+CH4 | GERG record, `F=1`, departure `Methane-Nitrogen` |
| N2+H2 | Kunz-cited record, `F=0`, no departure |
| N2+O2 | Gernert record, `F=0`, no departure |
| N2+Ar | Gernert record, `F=0`, no departure |
| N2+CO | Gernert record, `F=0`, no departure |
| N2+H2S | Kunz-cited record, `F=0`, no departure |
| N2+H2O | Gernert air-water record, `F=1`, departure `GeneralizedAirWater` |
| CH4+H2 | GERG record, `F=1`, departure `Methane-Hydrogen` |
| CH4+O2 | Kunz-cited record, `F=0`, no departure |
| CH4+Ar | Kunz-cited record, `F=0`, no departure |
| CH4+CO | Kunz-cited record, `F=0`, no departure |
| CH4+H2S | Kunz-cited record, `F=0`, no departure |
| CH4+H2O | Kunz-cited record, `F=0`, no departure |
| H2+O2 | Kunz-cited record, `F=0`, no departure |
| H2+Ar | Kunz-cited record, `F=0`, no departure |
| H2+CO | Kunz-cited record, `F=0`, no departure |
| H2+H2S | Kunz-cited record, `F=0`, no departure |
| H2+H2O | Kunz-cited record, `F=0`, no departure |
| O2+Ar | Gernert record, `F=0`, no departure |
| O2+CO | Gernert record, `F=0`, no departure |
| O2+H2S | Kunz-cited record, `F=0`, no departure |
| O2+H2O | Gernert air-water record, `F=0.6017`, departure `GeneralizedAirWater` |
| Ar+CO | Gernert record, `F=0`, no departure |
| Ar+H2S | Kunz-cited record, `F=0`, no departure |
| Ar+H2O | Gernert record, `F=0`, no departure |
| CO+H2S | Kunz-cited record, `F=0`, no departure |
| CO+H2O | Gernert air-water record, `F=0.9897`, departure `GeneralizedAirWater` |
| H2S+H2O | Kunz-cited record, `F=0`, no departure |

Ternary target conclusion:

| Target | Required pairs | PhaseXpert pair status | Decision |
| --- | --- | --- | --- |
| CO2 + N2 + CH4 | CO2+N2, CO2+CH4, N2+CH4 | All three pairs are present in pinned upstream teqp data and the ternary model constructs; PhaseXpert still lacks linked N-component provider ABI and encoded Ottøy validation rows | Unsupported |
| CO2 + N2 + CH4 + H2 | CO2+N2, CO2+CH4, CO2+H2, N2+CH4, N2+H2, CH4+H2 | All six pairs are present in pinned upstream teqp data and the quaternary model constructs; PhaseXpert still lacks linked N-component provider ABI and production validation | Unsupported |

Independent validation exists for the ternary CO2+N2+CH4 VLE system: Ottøy et
al. measured 62 dew/bubble points from 223 K to 298 K and 0.8 MPa to 9.3 MPa
and compared them with EOS-CG-2019, reporting composition deviations below
0.5 mol% liquid and 1.0 mol% vapor. PhaseXpert does not yet encode these
validation rows in executable form, so no ternary production calculation was
implemented. The next implementation step is an N-component native ABI backed
by generated model data for the selected subset, followed by direct Ottøy VLE
validation rather than relying on construction success.

## Second-Generation Audit - Additional Advanced Impurities

| Impurity | Candidate model | Pure EOS / binary interaction provenance | Data located | Validation outcome | Status |
| --- | --- | --- | --- | --- | --- |
| O2 | EOS-CG/Gernert CO2+O2 with Fij = 0 and no departure function; newer O2-rich density papers are validation data rather than a new PhaseXpert model | CO2 Span-Wagner; O2 Schmidt/Stewart; EOS-CG/Gernert reducing parameters | Existing Mantovani 2012 PVT audit; Lozano-Martin/Staubach O2-rich PVT literature found | Existing PhaseXpert direct teqp density audit failed: 6/6 converged, AARD 7.3878%, worst 14.8035%. New literature is not CO2-rich low-O2 transport validation and does not repair the model gate. | No defensible model found |
| Ar | EOS-CG-2021 CO2+Ar update with Løvseth et al. departure function | CO2 Span-Wagner; Ar Tegeler; EOS-CG Table 4 and Løvseth/GERG-2008 departure | Existing Mantovani 2012 PVT audit; Løvseth CO2+Ar model paper located | Existing broad gate failed: AARD 3.40533%, worst 9.99102%; low-Ar subset worst about 0.731526% over only 3 points and no VLE gate. | Research only |
| CO | EOS-CG-2021 reports CO as a covered CCS component; pinned upstream teqp has CO pure-fluid data and CO2+CO binary pair data | PhaseXpert has no linked native teqp CO2+CO provider route; upstream pair data are not a production gate | CO2+CO density and VLE literature found, including high-pressure density and Chapoy 2020 VLE | No PhaseXpert Advanced validation harness exists for CO2+CO; no production domain derived. | No defensible production model found |
| H2S | EOS-CG-2021 reports H2S extension; pinned upstream teqp has H2S pure-fluid data and CO2+H2S binary pair data | PhaseXpert has no linked native teqp CO2+H2S provider route; H2S must not be inferred from CoolProp or molar mass | CO2+H2S VLE/solubility literature found | No PhaseXpert Advanced validation harness exists for CO2+H2S; no production domain derived. | No defensible production model found |

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

No Advanced H2O production capability was implemented. Pinned upstream teqp
provides traceable H2O pure-fluid data and a CO2+H2O pair with a
`CarbonDioxide-Water` departure function, and the construction probe confirms
that wet multifluid models can be assembled. PhaseXpert does not yet generate
or link those wet model records into its native iOS bridge, and no validation
matrix is encoded for H2O-in-CO2-rich phase, CO2-in-water-rich phase, water
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
