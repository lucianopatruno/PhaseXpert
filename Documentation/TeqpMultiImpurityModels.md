# teqp multi-impurity model selection

## Status

This milestone starts the internal model-selection framework for the
user-facing `Advanced CCS Properties` provider. The stable provider ID remains
unchanged. Low-level teqp formulations are selected only behind the provider
boundary and must be disclosed in scientific traceability.

The next CCS mixture-model candidate is EOS-CG-2021, documented in
`Documentation/EOSCG2021Integration.md`. In that work, teqp is the native C++
engine and EOS-CG-2021 is the scientific formulation.

No impurity is enabled by inventory alone. A component becomes selectable for
teqp only after a formulation passes independent validation for a declared
property, composition, temperature and pressure range.

## Gate 0 version review

PhaseXpert retains teqp `v0.23.1`, commit
`a68eb9cabf47af2c4aba0d272ac10fbca4c10eca`, for this inventory stage. The
current official upstream release reviewed during this milestone is `v0.23.2`.
Its release notes describe Python 3.14 wheel publication and macOS x86_64 wheel
pipeline restoration; no required scientific model-data or native iOS build
benefit was identified. Upgrading would require rerunning the pure-CO₂
regression and auditing every embedded model record, so the pinned version is
unchanged.

## Internal formulation registry

`TeqpFormulationCatalog` records internal teqp formulations separately from the
user-facing provider. The production-enabled formulations are currently:

| Formulation ID | Components | Family | Status | Enabled properties | Phase envelope |
|---|---|---|---|---|---|
| `teqp-v0.23.1-pure-co2-span-wagner-density` | CO₂ | multifluid | production-enabled | density, Cv, Cp, Cp/Cv, speed of sound, molar mass, specific volume, Z | yes, pure-fluid saturation only |
| `teqp-v0.23.1-eoscg2021-co2-h2-gas-density-souissi2017` | CO₂+H₂ | EOS-CG-2021 | production-enabled, limited pass | homogeneous gas density at xH₂ = 0.05362 plus molar mass, specific volume, Z | no |
| `teqp-v0.23.1-eoscg2021-co2-ch4-gas-density-ghafri2016` | CO₂+CH₄ | EOS-CG-2021 / inherited GERG pair | production-enabled, expanded limited pass | homogeneous density at xCH₄ = 0.05 plus molar mass, specific volume, Z | no |

The CO₂+N₂ Gernert/GERG formulation from PR #42 is retained as
`teqp-v0.23.1-co2-n2-gerg-diagnostic` with `failedValidation` status. It is
not part of `productionFormulations` and therefore does not make N₂ selectable
for teqp.

## Gate A model inventory

The following matrix is taken from the pinned upstream teqp v0.23.1 source tree
under `teqp/fluiddata/dev`. `F = 0` and missing departure function means the
standard multifluid candidate has no binary departure term in the pinned data.

| Pair | Pure-fluid EOS records | Standard multifluid binary record | Departure function | Candidate teqp families | Current status |
|---|---|---|---|---|---|
| CO₂+N₂ | CO₂ `Span-JPCRD-1996`; N₂ `Span-JPCRD-2000` | `Gernert-Thesis-2013`, `F=1`, `betaT=0.994140013`, `gammaT=1.107654104`, `betaV=1.022709642`, `gammaV=1.047578256` | `Nitrogen-CarbonDioxide`, GERG-2008, `Kunz-JCED-2012` | standard multifluid; GERG residual; multifluid+activity Wilson example from teqp docs using Lasala et al. parameters | standard multifluid failed Gate C; Wilson example classified research-only because its parameter source is the example VLE fit rather than an independently validated predictive density formulation |
| CO₂+O₂ | CO₂ `Span-JPCRD-1996`; O₂ `Schmidt-FPE-1985,Stewart-JPCRD-1991` | `Gernert-Thesis-2013`, `F=0`, `betaT=1.0`, `gammaT=1.031986`, `betaV=1.0`, `gammaV=1.08446` | none | standard multifluid reducing function; GERG residual | failed Mantovani density bake-off; not enabled |
| CO₂+Ar | CO₂ `Span-JPCRD-1996`; Ar `Tegeler-JPCRD-1999` | `Gernert-Thesis-2013`, `F=1`, `betaT=1.027147`, `gammaT=0.968781`, `betaV=1.001378`, `gammaV=1.02971` | `Argon-CarbonDioxide`, GERG-2008, `Gernert-Thesis-2013` | standard multifluid; GERG residual | broad Mantovani density bake-off failed; low-Ar density-only subset remains non-production because three points do not define a robust property-specific production domain |
| CO₂+H₂ | CO₂ `Span-JPCRD-1996`; H₂ `Leachman-JPCRD-2009` | `Kunz-JCED-2012`, `F=0`, `betaT=0.942320195`, `gammaT=1.782924792`, `betaV=0.904142159`, `gammaV=1.15279255` | none | standard multifluid reducing function; GERG residual; EOS-CG-2021 Table 4/5 Beckmüller formulation | EOS-CG-2021 limited homogeneous gas-density support enabled at the Souissi 2017 domain |
| CO₂+CH₄ | CO₂ `Span-JPCRD-1996`; CH₄ `Setzmann-JPCRD-1991` | `Kunz-JCED-2012`, `F=1`, `betaT=1.02262449`, `gammaT=0.975665369`, `betaV=0.999518072`, `gammaV=1.002806594` | `Methane-CarbonDioxide`, GERG-2008, `Kunz-JCED-2012` | standard multifluid; GERG residual; EOS-CG-2021 inherited GERG pair | EOS-CG-2021 homogeneous density support enabled at the Ghafri 2016 gas block and high-temperature supercritical slice after beta/gamma mapping correction |

The teqp documentation states that GERG residual models include components
needed here, including methane, nitrogen, carbon dioxide, hydrogen, oxygen and
argon, but that the residual portions alone are sufficient for phase
equilibria and critical-locus tracing rather than complete caloric properties.
Therefore GERG residual candidates cannot by themselves justify enthalpy,
entropy or internal-energy exposure.

The teqp `Multifluid+Activity` documentation demonstrates CO₂+N₂ VLE with a
Wilson activity model using literature parameters from Lasala et al. and also
compares it with GERG-2008. Those parameters are an existing teqp-compatible
published candidate, not a PhaseXpert fit, but they have not yet been validated
against the PhaseXpert density and VLE matrix.

## Gate B validation survey

Initial independent references identified for the target binaries are:

| Pair | Density/PVT references | VLE references | Notes |
|---|---|---|---|
| CO₂+N₂ | Brugge et al. 1997; Mantovani et al. 2012 | Westman et al. 2016; Lasala et al. 2016 data embedded in teqp docs for the activity-model example | Standard Gernert/GERG model failed PR #42 Gate C; alternative formulations must be compared against the same primary data. |
| CO₂+O₂ | Mantovani et al. 2012; recent CO₂+O₂ PVT datasets require primary-source audit | Westman et al. 2016, DOI `10.1016/j.fluid.2016.04.002` | O₂ is high priority because Mantovani includes CO₂-rich PVT rows and Westman provides VLE. |
| CO₂+Ar | Mantovani et al. 2012 | published CO₂+Ar VLE sources require primary-source audit | Ar is high priority because Mantovani includes CO₂-rich PVT rows. |
| CO₂+H₂ | Sánchez-Vicente et al. 2013, DOI `10.1016/j.ijggc.2012.12.002`, reports CO₂+H₂ densities relevant to CCS; Souissi et al. 2017 ThermoML gas-density rows are now encoded for EOS-CG-2021 | CO₂+H₂ phase-behavior/VLE sources exist but no complete audited numerical matrix is encoded here | GERG natural-gas coverage must not be assumed accurate in CO₂-rich H₂ service; current production H₂ support is limited to the EOS-CG/Souissi homogeneous gas-density domain. |
| CO₂+CH₄ | Ghafri et al. 2016 NIST ThermoML density matrix is encoded and fully classified; the 301.14 K gas block and 308.15-313.15 K high-temperature supercritical slice are production-enabled for density only | Petropoulou et al. 2018, DOI `10.1016/j.fluid.2018.01.011`, reports CO₂+CH₄ VLE near 293-303 K; the earlier direct VLE diagnostic is superseded by the CH₄ mapping correction and is not production evidence | Current production CH₄ support is limited to EOS-CG/Ghafri homogeneous density only. |

## Current product decision

The requested target impurities are inventoried, with production enablement only
where a property-specific validation domain has passed:

| Impurity | Candidate formulation | Independent references | Density result | VLE result | Enabled range | Phase diagram |
|---|---|---|---|---|---|---|
| N₂ | Standard multifluid Gernert/GERG | Brugge 1997; Mantovani 2012; Westman 2016 | failed for user-facing support in PR #42 | failed to establish a supported range | none | no |
| N₂ | Multifluid+Activity Wilson candidate | Lasala et al.; PR #42 references for comparison | research-only: parameters are from the Lasala VLE example and are not accepted as an independently validated predictive density formulation | research-only: not a production validation set independent of the parameter source | none | no |
| O₂ | Standard multifluid reducing-function candidate | Mantovani 2012 Tables 2, 6 and 7; Westman 2016 CO₂+O₂ identified | failed: 6 direct teqp PVT points converged, worst relative density deviation `14.803493%` | not pursued for production after density gate failed | none | no |
| Ar | Standard multifluid Gernert/GERG candidate | Mantovani 2012 Tables 2, 8 and 9; CO₂+Ar VLE sources identified | failed for broad audited range: 6 direct teqp PVT points converged, low-Ar subset worst `0.731526%`, high-Ar subset worst `9.990878%` | not completed; low-Ar density-only promise is insufficient for phase-equilibrium support | none | no |
| H₂ | EOS-CG-2021 Table 4/5 Beckmüller formulation | Souissi et al. 2017 NIST ThermoML gas density; Sánchez-Vicente et al. 2013 retained as dense-domain context | limited homogeneous gas-density pass: 19/19 points, AARD 0.189492%, worst 0.370799% | no audited VLE matrix; phase equilibrium unavailable | xH₂ = 0.05362 exactly, T = 273.15/293.15/323.15 K, encoded gas-pressure ranges only | no |
| CH₄ | EOS-CG-2021 inherited GERG pair | Ghafri et al. 2016 NIST ThermoML density; Petropoulou et al. 2018 historical VLE diagnostic retained as superseded | full 180-row matrix converged but broad support failed: 1.3981775% AARD, 5.15195% worst; gas block pass: 6/6 points, 0.2034228% AARD, 0.413175% worst; high-temperature supercritical slice pass: 65 points, 1.1254775% AARD, 1.99333% worst | no audited corrected VLE matrix; phase equilibrium unavailable | xCH₄ = 0.05 exactly; 301.133-301.153 K and 1.99046-6.976 MPa; plus encoded 308.15-313.15 K high-temperature supercritical isotherm pressure bounds | no |

The machine-readable bake-off artifact is
`Documentation/Validation/TeqpMultiImpurityBakeoffResults.json`. It records the
representative Mantovani O₂ and Ar density points, direct teqp outputs and the
non-enabled scientific result for each requested impurity pair.

Pure-CO₂ teqp Cv, Cp and speed of sound are enabled. They are calculated from
the pinned Span-Wagner teqp ideal-gas and residual Helmholtz derivatives,
converted to mass basis, and checked against NIST Chemistry WebBook CO₂ fluid
property rows at gas, dense-liquid and supercritical states. Pure-CO₂
enthalpy, entropy and internal energy remain unavailable because the absolute
reference-state semantics are not yet independently accepted for PhaseXpert
results.

Pure-CO₂ teqp phase-envelope generation is enabled through the native
pure-fluid VLE saturation calculation. The generated boundary covers the
Span-Wagner CO₂ model from just above the triple-point temperature through the
critical point, avoids singular endpoints during sampling, appends the
authoritative critical point explicitly and rejects non-finite, non-positive or
non-monotonic saturation pressures. This does not enable any impurity phase
diagram.

Simultaneous multiple-impurity support is not enabled. Binary-pair validation
would not validate CO₂ plus several impurities because all impurity-impurity
interactions, multicomponent model assumptions and multicomponent experimental
evidence would still need to be audited.

## Implementation constraints

- Do not fit, tune or mutate binary interaction parameters inside PhaseXpert.
- Do not use Lorentz-Berthelot or other generic estimates as production
  scientific support.
- Do not expose a component through teqp merely because teqp contains a pure
  fluid file or GERG component name.
- Do not route teqp failures to CoolProp.
- Keep native runtime local/offline and keep generated XCFrameworks ignored.
