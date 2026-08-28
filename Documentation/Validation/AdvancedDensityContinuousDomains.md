# Advanced CCS continuous density-domain audit

## Objective and model identity

This 2026-08-28 audit asks whether independent measurements support continuous production density domains for CO2+N2, CO2+CH4, CO2+H2, or dry CO2-rich multicomponent mixtures. The evaluated production model remains teqp v0.23.1 commit `a68eb9cabf47af2c4aba0d272ac10fbca4c10eca`, using the already-audited PhaseXpert EOS-CG/custom multifluid construction. Component ordering, identifiers, mole-fraction mapping, molar masses, SI conversions, reducing/departure data and generic N-component construction remain covered by `EOSCGStaticIdentityAudit.json`, `EOSCG2021TargetModelData.json`, and the native regression suite. No native source, ABI, EOS coefficient, or binary interaction parameter changed.

The acceptance question is predictive EOS performance over a connected region, not interpolation of measurements. Existing gates were retained unless independent row evidence spanned a broader region with acceptable local behavior and a defensible homogeneous-phase interpretation. Convergence alone was never treated as validation. Exact decisions and artifact links are machine-readable in `AdvancedDensityContinuousDomains2026-08-28.json`.

## Acquisition and independence

The audit re-inventoried every density artifact under `Documentation/Validation` and repeated searches through primary journal pages, NIST ThermoML, institutional repositories, and author/repository records through 2026-08-28. Primary row sources already encoded are Mazzoccoli 2012 (`10.1021/je300590v`), Ghafri 2016 (`10.1016/j.fluid.2015.08.029`), Souissi 2017 (`10.1021/acs.jced.7b00213`), Liu 2017 (`10.1016/j.jct.2016.11.009`), Cheng 2019 (`10.1021/acs.jced.8b01206`), and Razmjoo 2026 (`10.1016/j.fuel.2026.139184`, CC BY 4.0 workbook `10.5281/zenodo.15846367`). These are experimental sources independent of this PhaseXpert audit; no PhaseXpert fitting was performed. Where an experimental paper also participated in development or assessment of a related EOS, it was not elevated into independent holdout evidence by that fact.

Newly located primary evidence includes the institutional-repository manuscript of Owuna et al. 2025 (`10.1021/acs.jced.4c00666`). Its Table 11 contains 27 exact liquid-density rows for xH2=0.0623, 278.06-298.24 K, 11.14-34.58 MPa, with expanded density uncertainties of 1.76-5.17 kg/m3 and composition standard uncertainty 0.0006. This block is relevant but disjoint in pressure/phase from the Souissi production gas data and therefore cannot validate continuous interpolation between Souissi isotherms. The PDF is not redistributed. Sánchez-Vicente 2013 (`10.1016/j.ijggc.2012.12.002`) remains highly relevant at xH2 about 0.02, 0.075 and 0.10, but no lawful machine-readable primary table was found in the audited routes. Candidate CO2/N2/O2 (`10.1016/j.tca.2019.03.032`) and CO2/N2/CH4 (`10.1021/acs.jced.2c00020`) sources likewise did not yield a lawfully reusable exact row block. No values were digitized from figures.

## Error-map method

The existing row artifacts preserve source and row IDs, composition, T, P, experimental and calculated density, absolute/relative residual, uncertainty where reported, convergence, phase label and root information. `AdvancedCCSTeqpIndependentValidation2026-08-20.json` is the row map for the three binaries; `MethaneFullDensityValidationResults.csv` and `Liu2017MethaneDensityExpansionBakeoff.json` add CH4 stratification; `Razmjoo2026MulticomponentDensity.json` is the complete multicomponent map. Normalized error is recoverable as absolute deviation divided by the row's expanded density uncertainty. Statistics below use predicted-minus-experimental sign. Non-converged and multiple-root rows stay distinct and are never included silently in residual averages.

## CO2+N2

The 64 Mazzoccoli rows all returned numerical densities, but the full matrix has AARD 30.298704%, signed bias -29.797176%, RMS relative deviation 39.672169%, and worst deviation -87.067537% at xN2=0.0127, 273.15 K, 3.902 MPa, reported liquid. The 15 gas rows have AARD 1.655175%, bias +0.166935%, RMS 2.105955%, and worst -5.299781%. Only the five 283.15 K gas rows from 1.0 to 4.5 MPa form the accepted block: AARD 0.599354%, bias +0.022493%, RMS 0.765116%, worst -1.442151%.

Decision: **KEEP EXISTING EXACT/DISCRETE GATE.** Only xN2=0.0127 has row-level fixed-model results in the CO2-rich audit, while local error changes sharply with state and phase. Mantovani's adverse low-impurity evidence and the absence of a second independently encoded CO2-rich composition preclude a continuous composition claim. Production remains exact xN2=0.0127, nominal 283.15 K, 1.0-4.5 MPa, homogeneous gas, density plus M/v/Z.

## CO2+CH4

All 180 Ghafri xCH4=0.05 rows converged: AARD 1.398222%, bias +1.398222%, RMS 1.689068%, worst +5.152136% at 301.070 K and 7.97239 MPa. The accepted gas and high-temperature supercritical slices contain 71 rows; near-critical/dense rows remain diagnostic. Liu adds 271 converged rows at six other compositions. Its global AARD is 0.783879%, but the nearest CO2-rich composition, xCH4=0.1012, has AARD 1.767461% and a local worst deviation of 7.675087%; higher compositions are not representative low-impurity CCS streams.

Decision: **KEEP EXISTING EXACT/DISCRETE GATE.** The independent evidence does not span the gap between xCH4=0.05 and 0.1012 with acceptable local behavior. Production remains the exact xCH4=0.05 Ghafri gas and high-temperature supercritical slices already encoded in `TeqpFormulationCatalog`; no rectangle or continuous interval is inferred.

## CO2+H2

All 19 Souissi gas rows at xH2=0.05362 converged: AARD 0.096971%, bias +0.093072%, RMS 0.148968%, worst +0.408391% at 323.15 K and 5.99737 MPa. The measurements occur only at 273.15, 293.15 and 323.15 K. Cheng's exact rows are hydrogen-rich at 673 K and irrelevant to the target. Owuna Table 11 supplies a nearby composition but only a dense liquid block separated from the production gas pressure domain; it is not a confirmatory temperature-interpolation dataset for the existing gas gate.

Decision: **KEEP EXISTING EXACT/DISCRETE GATE.** Production remains exact xH2=0.05362 at the three Souissi isotherms and their separate measured pressure ranges. Smooth calculations at intermediate temperatures or the nearby dense-liquid dataset do not establish a connected homogeneous-gas validation domain.

## Dry multicomponent

Razmjoo contributes 330 exact rows over five mixtures. The fixed generic N-component route selected a unique stable density for 171/330 (51.8182%); 159 multiple-root/non-selected states remain non-converged. Across converged rows, AARD is 0.610303%, bias -0.108497%, RMS 0.844124%, and worst +4.372792% at PreComb I, 313.00 K, 10.500 MPa. By mixture: OxyComb I 20/46 converged, AARD 0.584120%, worst -1.702920%; OxyComb II 0/33; PreComb I 37/69, AARD 0.860621%, worst +4.372792%; PreComb II 37/69, AARD 0.608688%, worst -1.120183%; TransportSpec 77/113, AARD 0.497598%, worst -1.105702%. The existing accepted contiguous blocks total 145 rows.

Decision: **KEEP EXISTING EXACT/DISCRETE GATE.** Five compositions do not support independent component-wise variation, a convex-hull claim, or a scientifically calibrated distance neighborhood. The four existing exact-composition, piecewise T/P, single-root gates remain authoritative. OxyComb II and all unresolved phase/root regions remain rejected.

## Capability, product behavior, and limitations

No capability-matrix code changed because none of the four campaigns supports a scientifically defensible strict superset. Density-derived M/v/Z continue to follow density only. Exact composition matching, phase restrictions, stable-root checks, finite/positive checks, Calculator, Saved Case batch comparison, and both Property Sweep modes continue to consume the same matrix. Intermediate compositions and just-outside boundary states remain rejected; this is intentional, not a missing implementation. Northern Lights, Brevik, Porthos and Aramis definitions were not changed and none newly enters an Advanced production density gate.

The central limitation is evidence geometry: promising rows exist, but the available exact CO2-rich compositions and homogeneous phase blocks do not span connected composition-T-P regions with independent confirmation. The conclusion is therefore negative and conservative. It does not assert that the EOS is inaccurate everywhere between measurements; it states that the production validation claim is not established.

## Reproducibility

Validate artifact structure and unchanged production boundaries with `swift test --package-path PhaseXpertCore --filter AdvancedDensityContinuousDomainDecisionTests` and `swift test --package-path PhaseXpertCore --filter AdvancedCCSCapabilityMatrixTests`. Run the completed repository tier with `bash Scripts/validate-phase-xpert.sh standard`. Native row predictions remain reproducible through `TeqpNativeBridgeValidationTests` when the ignored teqp XCFramework is present. No teqp or CoolProp XCFramework rebuild is required for this documentation-and-decision milestone.
