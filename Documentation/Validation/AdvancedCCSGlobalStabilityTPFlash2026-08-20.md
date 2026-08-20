# Advanced CCS global stability and TP flash — 2026-08-20

## Implemented formulation

At fixed T/P/feed `z`, the reference density is selected from every mechanically stable EOS density root; the reference root with minimum `sum(z_i*mu_i)` is used. For trial composition `w` and each mechanically and locally compositionally stable trial-density root, the dimensionless tangent-plane distance is

`TPD(w,rho_w) = sum_i w_i [mu_i(T,rho_w,w)-mu_i(T,rho_z,z)]/(R T)`.

The native model supplies pressure and chemical potentials from residual-Helmholtz partial-density gradients. Trial compositions use N−1 log ratios and softmax reconstruction. TPD below −2e−6 is unstable; −2e−6 through −1e−9 is near-neutral; values at or above −1e−9 are stable. Sensitivity checks used stricter equilibrium residuals (2e−7) and showed the demonstrator minimum, −0.00342270, is three orders of magnitude outside the ambiguity band.

Every objective evaluation enumerates roots on a 180-point logarithmic grid from 1e−7 to 100000 mol/m³, brackets sign changes and bisects for 70 iterations. Roots require positive finite `dp/drho`; trial roots additionally require positive total-Helmholtz-Hessian minimum eigenvalue. The deterministic multistart pattern search begins at the feed and each component-enriched simplex point, evaluates both coordinate directions, and halves its log-ratio step through 5e−3. Distinct minima are composition-deduplicated. No global mutable state or random initialization is used.

## Generic TP flash

The flash uses `ln(rhoL)`, `ln(rhoV)`, N−1 liquid log ratios, N−1 vapor log ratios and a logistic vapor fraction, for 2N+1 variables. Its 2N+1 equations are N fugacity/chemical-potential equalities, two EOS pressure equations and N−1 independent component material balances. TPD supplies the competing-phase seed; the companion composition is constructed at a bounded candidate vapor fraction so the initial material balance is exact. A central-difference Levenberg–Marquardt corrector with damping and backtracking enforces maximum material-balance error below 2e−8, maximum dimensionless fugacity residual below 2e−7 and both relative pressure residuals below 2e−7. Both phases must remain distinct and locally stable. Because this formulation enforces balance intrinsically without K variables, Rachford–Rice and successive substitution are not used.

## Diagnostics

The CO₂/N₂/CH₄ demonstrator uses 298.138 K, 7.05 MPa and `z=[0.9697,0.0152,0.0151]`, a midpoint constructed from compatible Ottøy L1/V1 boundary compositions for self-consistency only. TPD is −0.00342270 (unstable). Flash returns vapor fraction 0.488943006, `x=[0.980735693,0.008788545,0.010475762]`, `y=[0.958165156,0.021901442,0.019933402]`, maximum material residual 1.33e−8 and maximum fugacity residual 2.70e−8. This is not independent phase-fraction validation.

Generic tests classify the four-component Razmjoo OxyComb-I state at 312.35 K/1.952 MPa as stable (minimum TPD 0) and the five-component TransportSpec state at 313.15 K/10 MPa as stable (minimum TPD −1.93e−15). These are EOS safety diagnostics, not new VLE validation.

## Ottøy failure diagnosis and regression

All 18 baseline failures are classified in `Ottoy2020FailedRowClassification.json`: 17 reached chemical-potential/pressure stationary pairs but failed local Hessian positivity, while V28 additionally produced negative pressure and severe local instability. They are physical-model/stationary-phase acceptance failures, not missing density brackets, LM/Jacobian failures, tolerance failures or unclosed compositions. Criteria were not loosened. Consequently the accepted final boundary results remain bubble 21/31, AARD 0.542199%, bias −0.446304%, RMS 0.649702%, worst 1.268690%; dew 23/31, AARD 1.504217%, bias −1.177069%, RMS 2.620868%, worst 10.279512%, with unchanged composition metrics in the preceding VLE note.

## Performance and status

Profiling identified repeated 900-point trial density scans as dominant. A dedicated 180-point scan retained logarithmic full-range root enumeration and reduced the ternary TPD+flash focused test from 31.596 s to 1.596 s (19.8×) on the iPhone 17 simulator. The N=4 and N=5 TPD pair required 14.938 s and 653/1255 root evaluations respectively. Further acceleration requires validated analytic composition derivatives or safe within-call bracket continuation.

Pressure-sweep continuation, reverse-sweep hysteresis, phase-envelope tracing and phase-map gridding remain unimplemented: one independently checked interior flash is insufficient to validate branch-history behavior or envelope topology. TPD and TP flash remain research-only, with no Advanced capability-matrix, phase-classification, bubble/dew, envelope or UI production promotion. Built-ins remain outside a validated phase domain; no built-in composition or state was changed.
