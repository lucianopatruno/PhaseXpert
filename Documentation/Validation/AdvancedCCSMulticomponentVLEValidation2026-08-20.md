# Advanced CCS multicomponent VLE validation — 2026-08-20

## Scope and source

This milestone evaluates predictive CO₂/N₂/CH₄ bubble and dew pressure with the pinned teqp v0.23.1 commit `a68eb9cabf47af2c4aba0d272ac10fbca4c10eca`. The independent experimental source is Ottøy et al., *Fluid Phase Equilibria* 509 (2020) 112444, DOI `10.1016/j.fluid.2019.112444`, CC BY 4.0. The accepted source artifact contains 31 liquid/bubble rows and 31 vapor/dew rows. Published four-decimal mole fractions are preserved. Where their rounded sum differs from one by ±0.0001, validation explicitly closes CO₂ as `1-xN2-xCH4`; the adjustment is stored per row and is not a proportional normalization.

## Implemented thermodynamics

For N components at fixed temperature, a bubble calculation fixes liquid composition `x`; a dew calculation fixes vapor composition `y`. Both solve N chemical-potential equalities and one pressure equality. The unknown vector has N+1 independent variables: `ln(rhoL)`, `ln(rhoV)`, and N−1 log ratios for the incipient-phase composition. Softmax reconstruction makes every mole fraction positive and makes the sum exactly one. Thus the system is square without separate normalization equations.

The native bridge obtains residual Helmholtz energy, its partial-density gradient and Hessian from `IsochoricDerivatives::build_Psir_fgradHessian_autodiff`. It evaluates pressure as `rho*R*T - Psir + sum(rhoi*dPsir/drhoi)` and chemical potential, up to the species reference term that cancels between phases, as `dPsir/drhoi + R*T*ln(rhoi)`. Residuals are `(muL_i-muV_i)/(R*T)` and `(pL-pV)/max(0.1 MPa,(|pL|+|pV|)/2)`.

## Numerical method and safety

The solver is native C++ to keep the iterative derivative calls on one side of the ABI. It uses deterministic multistart Levenberg–Marquardt with a central finite-difference Jacobian, adaptive damping, and a bounded backtracking line search. Log densities are bounded to finite positive ranges; compositions use log-ratio/softmax coordinates. Seeds span vapor and liquid densities and five deterministic volatility patterns; no measured pressure or opposite-phase composition is supplied. A solution requires maximum dimensionless chemical-potential and relative-pressure residuals below `2e-7`, liquid density greater than 1.02 times vapor density, and a distinct composition. Non-positive pressure, non-finite output, or a non-positive minimum eigenvalue of the total Helmholtz partial-density Hessian is returned as structured thermodynamic failure. All C entry points validate pointers, lengths, component uniqueness, positivity and exact composition closure, catch all C++ exceptions, and never throw across the ABI.

The existing density root enumerator scans 900 points on a logarithmic molar-density grid, brackets every pressure residual sign change and bisects each bracket; it does not choose the first root. The VLE solve works directly in paired phase partial densities. Local stability uses the minimum eigenvalue of the total Helmholtz Hessian, including ideal diagonal `R*T/rhoi` terms. Mechanical stability alone is not treated as compositional stability.

## Ottøy results

Machine-readable row results are in `Ottoy2020TernaryVLEPredictions.json`. Bubble: 21/31 locally stable distinct solutions (67.742%); pressure AARD 0.542199%, signed bias −0.446304%, RMS 0.649702%, worst absolute relative deviation 1.268690%. Predicted vapor-composition errors for CO₂/N₂/CH₄ respectively were MAE 0.003419/0.002377/0.001830, bias −0.000967/+0.001856/−0.000875, RMS 0.004287/0.002976/0.002542, and worst 0.010255/0.005966/0.005983 mole fraction.

Dew: 23/31 locally stable distinct solutions (74.194%); pressure AARD 1.504217%, signed bias −1.177069%, RMS 2.620868%, worst absolute relative deviation 10.279512%. Predicted liquid-composition errors for CO₂/N₂/CH₄ respectively were MAE 0.005410/0.003053/0.002523, bias +0.003420/−0.002409/−0.001011, RMS 0.010531/0.006048/0.004609, and worst 0.040394/0.022992/0.017401 mole fraction.

The equality solver found additional stationary phase pairs that failed local stability; these remain explicit failures and are excluded only from error aggregates, never from convergence percentages. Failures cluster at lower temperatures and denser/near-critical or highly asymmetric states. Phase-density/composition coalescence is rejected as `noDistinctPhaseSplit`; non-positive Hessian eigenvalues or pressure are `thermodynamicFailure`. This separates EOS/stability limitations from numerical residual convergence.

## Decisions and limitations

No production VLE gate is promoted. Although the stable bubble subset has low pressure error, only 21/31 rows pass and the measured compositions vary, so a contiguous composition domain or defensible interpolation gate is not established. Dew has lower convergence and a 10.28% worst pressure error. The generic capability is retained as research-only infrastructure; Advanced phase classification, phase margin, TP flash, phase envelope and Phase Map remain unsupported for CO₂/N₂/CH₄.

A global tangent-plane-distance minimizer was investigated but not promoted: the required chemical-potential primitive now exists, yet robust fixed-T/P trial-phase density-root selection and deterministic global composition minimization need separate validation. The Hessian test is explicitly local, not TPD. TP flash and Rachford–Rice were not implemented because bubble/dew did not establish a product gate. Envelope continuation can use prior predicted states in future work, but this milestone's independent validation used deterministic per-row initialization. No hidden global cache or mutable solver state is used; identical inputs follow identical multistarts.

Additional VLE searches after the Ottøy campaign checked ThermoML/NIST, journal supplements and CCS/EOS-CG literature for CO₂/N₂/CH₄, CO₂/N₂/O₂, CO₂/N₂/Ar, CO₂/CH₄/H₂ and higher mixtures. No additional lawful row-level high-CO₂ dataset was encoded and tested in this milestone. Razmjoo density gates were not reinterpreted as VLE validation. Porthos, Aramis, Northern Lights and Brevik do not match a validated ternary VLE gate; Celsio remains information-only.

## Performance

Across the 62 independent calls on an iPhone 17 simulator, ordinary execution was median 471.327 ms, mean 457.664 ms and worst 1299.481 ms per bubble/dew calculation. The solver is deterministic and thread-safe because each call constructs local model and solver state; there is no cross-call continuation cache.
