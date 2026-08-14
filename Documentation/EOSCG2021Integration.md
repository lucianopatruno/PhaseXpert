# EOS-CG-2021 integration

## Status

This milestone separates three concepts:

- user-facing provider: PhaseXpert's selectable advanced model;
- native engine: the local teqp C++ bridge and derivative/equilibrium tools;
- scientific formulation: a published CCS mixture EOS such as EOS-CG-2021.

The production advanced provider now supports pure CO₂ plus two
property-specific impurity domains: CO₂+H₂ homogeneous gas density at the exact
Souissi et al. 2017 ThermoML composition and isotherm pressure ranges, and
CO₂+CH₄ homogeneous gas density at the exact Ghafri et al. 2016 ThermoML gas
composition and pressure range. No other impurity, phase equilibrium, phase
envelope, mixture heat capacity, mixture speed of sound, reference-state
property or transport property is enabled by this document or by the extracted
parameter artifact alone.

The user-facing display name is:

`Advanced CCS Properties`

The stable provider ID remains `teqp-pure-co2-experimental` for saved-case
compatibility.

## Primary source

EOS-CG-2021 is documented in:

Neumann, Herrig, Bell, Beckmüller, Lemmon, Thol and Span,
"EOS-CG-2021: A Mixture Model for the Calculation of Thermodynamic Properties
of CCS Mixtures," *International Journal of Thermophysics* 44, 178 (2023),
DOI `10.1007/s10765-023-03263-6`.

The article is open access under CC BY 4.0. It states that the model is
formulated in terms of Helmholtz energy, covers gas, liquid, supercritical and
phase-equilibrium states, and includes CO₂, N₂, O₂, Ar, H₂ and CH₄ among its
16 components. The article identifies Table 4 as the reducing-parameter and
`Fij` table and Table 5 as the departure-function parameter table. It also
states that automatic differentiation, including teqp, can be used for the
required Helmholtz derivatives.

## Gate A feasibility

EOS-CG-2021 uses the same broad multiparameter multifluid Helmholtz structure
that the existing native teqp bridge already exercises:

- pure-fluid Helmholtz EOS;
- composition reducing functions with `betaT`, `gammaT`, `betaV`, `gammaV`;
- pair weighting factor `Fij`;
- binary departure functions;
- derivative-based pressure, heat-capacity, speed-of-sound and fugacity
  relations.

Therefore the first production implementation path is to express EOS-CG-2021
as custom teqp multifluid model data and reuse the native teqp bridge for
residual/ideal Helmholtz derivatives, density roots and equilibrium residuals.
Julia, Python and network services remain excluded from iOS runtime.

## Extracted target-pair parameters

The machine-readable extraction for PhaseXpert's target subset is
`Documentation/Validation/EOSCG2021TargetModelData.json`. It records the Table
4 values for:

| PhaseXpert pair | EOS-CG-2021 order | Source in paper | betaT | gammaT | betaV | gammaV | Fij | Initial decision |
|---|---|---|---:|---:|---:|---:|---:|---|
| CO₂+N₂ | N₂+CO₂ | GERG-2008 inherited | 1.005895 | 1.107654 | 0.977795 | 1.047578 | 1 | numerically equivalent to PR #42 GERG after reciprocal beta handling; not a new N₂ candidate |
| CO₂+O₂ | CO₂+O₂ | EOS-CG/Gernert-Span | 1.000000 | 1.031986 | 1.000000 | 1.084460 | 0 | candidate; no departure function |
| CO₂+Ar | CO₂+Ar | Løvseth et al. | 0.998705 | 1.039675 | 1.003766 | 1.013833 | 1 | candidate; Table 5 departure function required |
| CO₂+H₂ | CO₂+H₂ | Beckmüller et al. | 0.979000 | 1.961000 | 1.198000 | 0.842000 | 1 | candidate; Table 5 departure function required |
| CO₂+CH₄ | CH₄+CO₂ | GERG-2008 inherited | 1.022624 | 0.975665 | 0.999518 | 1.002807 | 1 | GERG-inherited candidate; reciprocal beta handling required for CO₂+CH₄ order |

The extraction also records Table 5 departure-function terms for CO₂+N₂,
CO₂+Ar, CO₂+H₂ and CO₂+CH₄. The target EOS-CG term types map onto teqp
v0.23.1's existing `GERG-2008`, `Gaussian+Exponential` and `Exponential`
departure builders; no new native term type has been identified for these
five target binaries. No coefficient may be guessed or fitted inside
PhaseXpert.

A standalone direct-construction probe using the pinned teqp v0.23.1 headers,
vendored fluid JSON data and the extracted EOS-CG Table 4/5 records constructed
custom CO₂+O₂, CO₂+Ar, CO₂+H₂ and CO₂+CH₄ multifluid models successfully. This
confirms native representation feasibility for the target records, but it is
not production validation. Production enablement still requires EOS-CG identity
checks and independent PVT/VLE validation against primary data for each
property-specific domain.

`Scripts/build-teqp-xcframework.sh` now prepares generated native headers with
the target CO₂, N₂, O₂, Ar, H₂ and CH₄ fluid JSON records plus
`Documentation/Validation/EOSCG2021TargetModelData.json`. The checked-in
XCFramework remains generated and ignored; rebuilding it is required only when
the native bridge ABI or embedded model-data fingerprint changes.

The first direct-density bake-off against the already-audited Mantovani 2012
CO₂+O₂ and CO₂+Ar rows is recorded in
`Documentation/Validation/TeqpMultiImpurityBakeoffResults.json`:

| Pair | EOS-CG candidate | Density points | AARD | Worst relative deviation | Result |
|---|---|---:|---:|---:|---|
| CO₂+O₂ | Table 4 reducing parameters, `Fij = 0`, no departure function | 6 | 7.3878% | 14.8035% | Fail |
| CO₂+Ar | Table 4 reducing parameters plus Table 5 Løvseth departure function | 6 | 3.40533% | 9.99102% | Fail |
| CO₂+H₂ | Table 4 reducing parameters plus Table 5 Beckmüller departure function | 19 gas-density points | 0.189492% | 0.370799% | Limited homogeneous gas-density pass; production-enabled only for the encoded domain |
| CO₂+CH₄ | Corrected GERG-inherited reducing parameters plus GERG-2008 departure function | 180 homogeneous density rows; 6-row gas block production subset | 1.3981775% overall; 0.2034228% gas block | 5.15195% overall; 0.413175% gas block | Limited homogeneous gas-density pass for the gas block only |
| CO₂+CH₄ | Prior mis-mapped GERG-inherited record | 5 VLE points | n/a | 47.3955% pressure; 0.01705 absolute yCH₄ | Superseded by CH₄ Table 4 mapping bug |

The CO₂+Ar 3.08 mol% subset remains a useful diagnostic with worst density
deviation 0.732631%, but it is not user-facing support because the evidence is
only three Mantovani density points and does not define a robust independent
property-specific production domain.

The CO₂+CH₄ direct VLE probe used the NIST ThermoML encoding of Petropoulou
et al. 2018. That historical result is now superseded: a pinned Clapeyron
EOS_CG database audit found that PhaseXpert's CH₄+CO₂ Table 4 values had been
mis-mapped. The corrected CH₄+CO₂ values are recorded in
`Documentation/Validation/EOSCG2021TargetModelData.json`, and the prior VLE
deviation must not be cited as an EOS-CG model failure until the corrected
implementation is rerun.

A corrected direct-teqp homogeneous gas-density probe is recorded in
`Documentation/Validation/EOSCGDirectTeqpDensityProbeResults.json`. It gives:

| Pair/domain | Reference data | Points | AARD | Worst relative deviation |
|---|---|---:|---:|---:|
| CO₂+H₂ gas, xH₂ = 0.05362 | Souissi et al. 2017 NIST ThermoML | 19 | 0.189492% | 0.370799% |
| CO₂+CH₄ gas, zCO₂ = 0.95 | Ghafri et al. 2016 NIST ThermoML gas block | 6 | 0.203422% | 0.413173% |

The CO₂+H₂ gas-density result is production-enabled only for the exact
validated domain. The CO₂+CH₄ gas subset is also production-enabled only for
the exact validated Ghafri gas-block domain: xCH₄ = 0.05, 301.14 K ± 0.02 K
and 1.99046-6.976 MPa. The full 180-row Ghafri matrix converges, but dense and
near-critical deviations are diagnostic only and do not justify broader CH₄
support.

A runnable Clapeyron EOS_CG oracle was not available in the managed
Xcode/Codex environment. Instead,
`Documentation/Validation/EOSCGStaticIdentityAudit.json` compares the pinned
Clapeyron.jl v0.6.26 EOS_CG source/database records with PhaseXpert's
EOS-CG model data field-by-field for CO₂+N₂, CO₂+O₂, CO₂+Ar, CO₂+H₂ and
CO₂+CH₄. The static audit result is `PASS`, and it records the corrected
CO₂+CH₄ beta/gamma order bug found in the earlier implementation.

## Immediate validation implications

- CO₂+N₂: EOS-CG-2021 inherits the same GERG formulation already rejected for
  PhaseXpert user-facing N₂ support in PR #42. The implementation task is a
  single numerical equivalence check, followed by an alternative published N₂
  formulation search.
- CO₂+O₂: the EOS-CG Table 4 candidate is the first implementation target
  because it has no departure term and can be represented with the reducing
  function alone.
- CO₂+Ar and CO₂+H₂: both require exact Table 5 departure-function extraction
  before any validation bake-off.
- CO₂+H₂: direct native construction works, and the open Souissi et al. 2017
  NIST ThermoML gas-density matrix is now encoded in
  `Documentation/Validation/HydrogenThermoML2017Density.json` with 19
  machine-readable points at xH₂ = 0.05362. Static EOS-CG identity plus the
  direct teqp density probe establish a limited homogeneous gas-density
  production domain at the encoded composition/isotherms/pressure ranges. The
  dedicated acquisition artifact
  `Documentation/Validation/HydrogenValidationDataAcquisition.json` records
  the source audit: Sánchez-Vicente et al. 2013 is directly relevant but its
  numerical PVT table was not accessible through the checked metadata,
  repository or ThermoML routes; Cheng et al. 2019 ThermoML data are accessible
  but H₂-rich and 673 K rather than CO₂-rich CCS impurity data; and Owuna et
  al. 2025 appears relevant from metadata but the numerical tables/PDF were not
  accessible to this agent. No H₂ validation values are inferred from snippets
  or plots.
- CO₂+CH₄: EOS-CG-2021 inherits GERG; the first direct Petropoulou/ThermoML VLE
  probe is superseded by the CH₄ beta/gamma mapping correction. The corrected
  Ghafri 2016 full-matrix diagnostic converges but is not a broad pass, while
  the 6-row gas-density block establishes a limited homogeneous gas-density
  production domain.
- Simultaneous impurity support is not implied by binary construction. The
  EOS-CG-2021 authors report that multicomponent validation data remain
  comparatively scarce, so PhaseXpert must keep multicomponent impurity entry
  disabled until an explicit multicomponent validation gate passes.

## Runtime policy

All iOS calculations must remain local, offline and deterministic. The native
bridge may embed published EOS-CG model data only after coefficient audit,
licence review and identity tests. Scientific traceability must report the
user-facing provider, native engine and scientific formulation separately.
