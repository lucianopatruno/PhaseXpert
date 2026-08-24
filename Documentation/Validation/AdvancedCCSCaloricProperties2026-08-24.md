# Advanced CCS Caloric Properties - 2026-08-24

## Outcome

The pinned teqp engine already calculates homogeneous arbitrary-N `Cp`, `Cv`, `Cp/Cv`, and speed of sound through the native N-component thermodynamic-state ABI. This milestone found no lawfully accessible exact row-level CO2-rich CCS caloric table suitable for an independent production gate. No caloric property is promoted and no UI or capability matrix is broadened.

## Implementation audit

`px_teqp_calculate_ncomponent_thermodynamic_state` first uses the existing phase-aware density-root selector, then evaluates complete fixed-composition Helmholtz derivatives. Residual derivatives come from `teqp::TDXDerivatives` on the pinned multifluid EOS. Ideal derivatives come from `teqp::IdealHelmholtz`, built without replacement coefficients from every component JSON `alpha0` term using teqp's `CoolProp2teqp_alphaig_term_reformatter`.

The implemented mass-basis relations are evaluated from molar Helmholtz derivatives:

- `Cv/R = -(a020 + ar20)`
- `Cp/R = Cv/R + (1 + ar01 - ar11)^2 / (1 + 2 ar01 + ar02)`
- `gamma = Cp/Cv`
- the existing speed path uses the same `Cv`, density derivative, and temperature-density coupling.

The ABI is arbitrary-N, explicitly sized, rejects compositions that do not close rather than normalizing them, uses the existing stable-root policy, rejects non-finite/non-positive derivatives and never lets exceptions cross C. No native change was required.

## Reference-state audit

The pinned component ideal models retain their JSON `alpha0` reference terms, but PhaseXpert has not established that their additive enthalpy, internal-energy, or entropy conventions match a traceable experimental mixture convention. The Advanced ABI therefore intentionally exposes none of `h`, `u`, or `s`. `Cp`, `Cv`, and their ratio do not depend on arbitrary additive reference constants. Enthalpy differences and excess enthalpy could cancel additive references, but no corresponding Advanced implementation and complete row-level validation were established here. Absolute `h`, `u`, and `s` remain unsupported.

## Evidence acquisition

The audit searched NIST/TRC/ThermoML, GERG/EOS-CG references, publisher archives, Crossref/DataCite/OpenAlex, institutional repositories, accepted manuscripts, and citation chains. Primary candidates included Bishnoi and Robinson's CO2/CH4 Cp work (1971), Bishnoi, Hamaliuk, and Robinson's CO2/N2 Cp work (1972), Boulton and Stein's near-equimolar CO2/CH4 Cp-ratio work (1988), Pu et al.'s 22-row CO2/CH4 Cv work (2025), Hejmadi, Katz, and Powers' CO2/N2 excess-enthalpy work (1971), and the recent CO2/H2 Joule-Thomson campaign. Exact experimental tables were inaccessible or paywalled; no values were transcribed from graphs, secondary EOS comparisons, or snippets.

The open Cornell dissertation on supercritical-fluid Cp was inspected. It corroborates methods, composition ranges, and uncertainty classes for historical CO2/CH4 and CO2/N2 campaigns, but does not republish their exact rows. Its own exact mixture table concerns CO2/methanol, outside the supported Advanced component set, and was not used as CCS validation evidence.

## Property-specific decision

| Property | Calculable | Independently validated for a new mixture gate | Production-enabled |
|---|---|---|---|
| Cp | Yes | No exact rows acquired | No |
| Cv | Yes | No exact rows acquired | No |
| Cp/Cv | Yes | Neither underlying property independently validated | No |
| h | No Advanced ABI; reference convention unresolved | No | No |
| u | No Advanced ABI; reference convention unresolved | No | No |
| s | No Advanced ABI; reference convention unresolved | No | No |

No capability-matrix, provider-routing, result-UI, validation-shield, or built-in-case change is scientifically justified. Existing density, acoustic, phase-behavior, General Properties, and pure-CO2 decisions remain unchanged.

## Performance

Ten measured repetitions after one warm-up at the four-component state `z = 0.942 CO2 + 0.023 N2 + 0.022 CH4 + 0.013 H2`, 313.15 K and 11.001 MPa took 58.127208 ms median, 58.2476792 ms mean, and 59.220166 ms worst on the iPhone 17 simulator. The repeated complete native results were identical. This is diagnostic performance, not validation evidence.
