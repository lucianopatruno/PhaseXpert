# Advanced CCS speed-of-sound validation — 2026-08-21

## Decision

PhaseXpert promotes one property-specific limited-production acoustic gate: speed of sound for the exact measured CO₂/O₂ composition `xCO2 = 0.9348`, `xO2 = 0.0652`, at the nominal 301.15 K isotherm (the existing ±0.05 K nominal-isotherm tolerance), 24.12–40.83 MPa absolute, in the homogeneous liquid/dense domain. Density, Cp, Cv, phase classification, VLE, and transport properties are not promoted by this evidence. CO₂/N₂, CO₂/CH₄, CO₂/H₂, CO₂/H₂S, and the evaluated dry multicomponent mixture remain research-only for acoustics.

## teqp formulation and acoustic path

The calculation uses pinned teqp v0.23.1, commit `a68eb9cabf47af2c4aba0d272ac10fbca4c10eca`, with the existing EOS-CG mixture construction and the PR #60 phase-domain-aware density-root selection. No EOS parameter or binary interaction parameter was changed or fitted.

At fixed composition the native path evaluates the complete ideal plus residual reduced Helmholtz derivatives. With `alpha = alpha0 + alphar`, reduced density `delta`, reciprocal reduced temperature `tau`, mixture molar mass `M`, and molar gas constant `R`:

```
cv/R = -(alpha0_tautau + alphar_tautau)
D = 1 + 2*alphar_delta + alphar_deltadelta
C = 1 + alphar_delta - alphar_deltatau
cp/R = cv/R + C^2/D
w^2 = (R*T/M) * (D + C^2/(cv/R))
```

The bridge requires a finite positive result, positive Cv and Cp, mechanical stability, and a positive minimum eigenvalue of the total-Helmholtz Hessian. The new arbitrary-N ABI contains exceptions and returns structured status; it reuses the existing density-root implementation. Cp and Cv are internal derivatives and remain unsupported user-facing properties.

## Primary data and provenance

The validation source is Ibrahim Al-Siyabi, *Effect of impurities on CO2 stream properties* (Heriot-Watt University doctoral thesis, 2013), public repository handle <http://hdl.handle.net/10399/2643>, Table 3.2 (thesis pages 47–52). All 300 numerical rows were extracted from the public PDF tables, not graphs: 60 CO₂/N₂, 61 CO₂/CH₄, 57 CO₂/H₂, 62 CO₂/O₂, and 60 dry MIXb rows. The thesis reports speed-of-sound accuracy ±1 m/s, gravimetric composition uncertainty ±0.3 mol%, and temperature stability 0.05 K. Pressures are absolute. Row values, predictions, provenance, isotherm stratification, and integrity fields are preserved in `AlSiyabi2013AdvancedSpeedOfSoundValidation.json`.

The acquisition campaign also searched repository inventory, NIST TRC/ThermoML, publisher supplements, institutional and author repositories, Crossref/DataCite, Zenodo, Figshare, Mendeley Data, theses, metrology repositories, and EOS-CG/GERG citation chains. Wegge et al., DOI `10.1016/j.jct.2016.03.036`, is a primary CO₂/Ar source but covers 25.019 and 49.896 mol% Ar, outside this milestone's priority and low-Ar CCS scope. Fernández-Vicente et al., DOI `10.1016/j.jct.2016.07.033`, is methane-rich biogas rather than a CO₂-rich CCS mixture. No primary row-level CO₂/H₂S binary acoustic matrix was recovered. The machine-readable acquisition audit records routes and blockers without reproducing inaccessible copyrighted content.

## Full-dataset results

All 300 states converged using the dense homogeneous root selection. Errors are prediction minus experiment.

| System and exact impurity composition | Rows | MAE (m/s) | Bias (m/s) | RMS (m/s) | AARD (%) | Worst abs. (m/s) | Worst rel. (%) | Decision |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| N₂, x=0.0444 | 60/60 | 14.978396 | -14.978396 | 15.077697 | 2.300656 | -18.491011 | -3.621210 | rejected: systematic error far beyond ±1 m/s |
| CH₄, x=0.0461 | 61/61 | 1.903212 | -0.636270 | 2.161184 | 0.293260 | +4.541147 | +0.768303 | rejected: no complete isotherm uncertainty-consistent |
| H₂, x=0.0453 | 57/57 | 5.869325 | -5.311570 | 7.380977 | 0.989511 | -25.304366 | -6.053676 | rejected: pressure-dependent deviations exceed ±1 m/s |
| O₂, x=0.0652 | 62/62 | 3.806427 | +3.760566 | 5.323033 | 0.673819 | +12.991072 | +2.952869 | broad domain rejected; narrow block assessed below |
| MIXb: CO₂/CH₄/H₂/N₂ = .9532/.021/.008/.0178 | 60/60 | 6.835265 | +6.835265 | 8.201763 | 1.276794 | +21.308767 | +6.457202 | rejected: no complete isotherm uncertainty-consistent |

For MIXb, even the best complete isotherm (301.15 K) has 5.365561 m/s MAE and 8.923266 m/s worst absolute error. It therefore does not support a multicomponent production gate. The complete N₂ and H₂ isotherms show persistent systematic errors. CH₄ is substantially better, but no complete isotherm is consistent with the ±1 m/s accuracy; no gate was manufactured from scattered favorable rows.

## Promoted contiguous O₂ block

The complete contiguous six-row high-pressure tail at 301.15 K contains source rows `o2-047`, `o2-050`, `o2-053`, `o2-056`, `o2-059`, and `o2-062`. It gives 6/6 convergence, 0.538573 m/s MAE, +0.474074 m/s bias, 0.639985 m/s RMS, 0.085971% AARD, 0.978416 m/s worst absolute error, and 0.169570% worst relative error. Every included row is within the reported ±1 m/s accuracy. The immediately adjacent lower-pressure row at 21.39 MPa errs by +1.896119 m/s, providing an evidence-based lower boundary. No interpolation across composition is claimed: only the exact nominal composition is accepted within the canonical numerical equality tolerance. No extension beyond the first and last included pressures is allowed.

## Product behavior

`speedOfSound` is an independent Advanced capability-matrix property. At an approved state the provider routes only through the native arbitrary-N teqp acoustic path and requests the dense homogeneous root. Requested density or caloric properties are returned explicitly unavailable under the acoustic-only gate; there is no CoolProp fallback and no component dropping. The existing result/unit architecture displays `Speed of sound` in m/s. Capability-driven guidance and the scientific shield identify the exact composition, 301.15 K nominal isotherm, 241.2–408.3 bar(a), source, and acoustic-only scope. Pure-CO₂ behavior and all accepted density/VLE/water logic are unchanged.

Representative host diagnostic runtimes across the six promoted states were 21.563 ms mean, 20.529 ms median, and 24.439 ms worst. The diagnostic artifact was regenerated from the scored row file by `Scripts/finalize-advanced-speed-of-sound.py`; generated teqp XCFramework products remain ignored and are not committed.
