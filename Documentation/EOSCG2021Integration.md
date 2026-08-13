# EOS-CG-2021 integration

## Status

This milestone separates three concepts:

- user-facing provider: PhaseXpert's selectable advanced model;
- native engine: the local teqp C++ bridge and derivative/equilibrium tools;
- scientific formulation: a published CCS mixture EOS such as EOS-CG-2021.

The current production teqp provider remains pure CO₂ only. No impurity is
enabled by this document or by the extracted parameter artifact alone.

Until at least one impurity formulation passes the production validation gate,
the user-facing display name is:

`Advanced CO₂ & Phase Model (teqp)`

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
| CO₂+CH₄ | CH₄+CO₂ | GERG-2008 inherited | 0.999518 | 1.002806 | 1.000482 | 1.022624 | 1 | GERG-inherited candidate; reciprocal beta handling required for CO₂+CH₄ order |

The extraction intentionally stops before production use for pairs with
`Fij = 1` until the corresponding Table 5 departure-function coefficients are
fully audited and tested. No coefficient may be guessed or fitted inside
PhaseXpert.

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
- CO₂+CH₄: EOS-CG-2021 inherits GERG; validation against CO₂-rich density and
  VLE data decides whether a PhaseXpert subdomain can be enabled.

## Runtime policy

All iOS calculations must remain local, offline and deterministic. The native
bridge may embed published EOS-CG model data only after coefficient audit,
licence review and identity tests. Scientific traceability must report the
user-facing provider, native engine and scientific formulation separately.
