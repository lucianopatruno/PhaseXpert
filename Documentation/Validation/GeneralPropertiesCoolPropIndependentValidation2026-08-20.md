# General Properties CoolProp independent validation milestone

## Baseline

- Original contaminated local HEAD: `28cbb17d126475657cab14a924a22c2e87f37f48`; it was not pushed and the original Xcode checkout was not modified during recovery.
- Recovery clone base main SHA: `17ca0bfe2b18473bd19b4f5814634e182e606819`.
- PR #56 approved HEAD `f52b7396bd901a1931cda2df8deb1e23c5873a12` is contained in main.
- Pinned CoolProp source selection remains `v8.0.0`; the audited Python CoolProp 8.0.0 package reported git revision `ae81610e7d23efc57f9d051c8e70a4d66e87537f`.
- Protected `PhaseXpert.xcodeproj/project.pbxproj`, `Services/`, `Vendor/ThermoPack/`, local signing state and ignored Vendor artifacts were not copied into the recovery commit.

## Current General Properties component list

The source-advertised component list is CO2, N2, O2, Ar, CH4, H2, CO, H2S and H2O. Dry mixtures are calculable only for CO2-rich states with N2, O2, Ar, CH4, H2, CO and H2S at total impurity no greater than 10 mol%. Binary CO2/H2O homogeneous gas is calculable only at xH2O = 1e-6...0.001, 350...423.15 K and 0.5...5 MPa.

## CoolProp provenance audit

PhaseXpert uses the bridge-backed CoolProp 8.0.0 HEOS path. Pure CO2 uses `AbstractState(HEOS, CO2)` with Span-Wagner CO2 EOS provenance. Dry mixtures use the pinned CoolProp HEOS/multifluid route and shipped interaction entries only; PhaseXpert does not estimate binary parameters. CO2/H2O homogeneous gas uses the shipped CO2/Water pair with an imposed gas phase and never uses unsafe high-level mixture PT flash. The Phase Map continues to use the PR #49 legacy-stability phase classifier and does not request density as a phase-map property.

## Independent density results

The row-level CoolProp 8.0.0 density scoring artifact is `Documentation/Validation/GeneralPropertiesCoolPropDensityValidation2026-08-20.json`.

- CO2+N2: Mazzoccoli, Bosio and Arato 2012, DOI `10.1021/je300590v`, density. Current calculable rows scored 64/64 converged, 22.422515% AARD, +10.418083% signed bias, 130.112874% RMS, worst +1032.554248% at 283.15 K, 2.0 MPa, xN2 = 0.0127. Final status: preliminary / validation pending; no density, derived-volumetric or VLE gate promoted.
- CO2+CH4: Al Ghafri, Rowland, Hughes, May and coauthors 2016, DOI `10.1016/j.fluid.2015.08.029`, density; Liu et al. 2017, DOI `10.1016/j.jct.2016.11.009`, audited outside the current CO2-rich 10 mol% calculability guardrail. Ghafri all rows scored 180/180 converged, 1.400013% AARD, +1.400013% bias, 1.690919% RMS, worst +5.155629%. Promoted limited-production density-derived domain: xCH4 = 0.05 exactly, 301.133...301.153 K and 1.99046...6.976 MPa gas rows, plus 308.137...313.182 K and 7.9718...11.966 MPa high-temperature supercritical rows. Subset metrics: gas 6/6, 0.204388% AARD, +0.204388% bias, 0.244953% RMS, worst +0.414904%; high-temperature supercritical 65/65, 1.127350% AARD, +1.127350% bias, 1.204793% RMS, worst +1.995566%. Phase/VLE, caloric, acoustic and transport remain unsupported.
- CO2+O2: Lozano-Martin, Mondejar and Segovia 2020, DOI `10.1016/j.jct.2020.106210`, density; Mazzoccoli 2012, DOI `10.1021/je300590v`, diagnostic density; Ahamada et al. 2020, DOI `10.1021/acs.jced.0c00484`, higher-O2 diagnostic density. Lozano all rows scored 92/92 converged, 4.674756% AARD, +4.538886% bias, 43.763370% RMS, worst +419.759049%. Promoted limited-production density-derived domain: xO2 = 0.05032089 exactly, homogeneous gas rows at 275.001...374.925 K and 0.997...7.897 MPa. Subset metrics: 45/45, 0.079176% AARD, +0.004750% bias, 0.113558% RMS, worst -0.392570%. Phase/VLE, caloric, acoustic and transport remain unsupported.
- CO2+Ar: Mazzoccoli 2012, DOI `10.1021/je300590v`, density; Lovseth et al. 2018, DOI `10.1016/j.fluid.2018.03.006`, VLE/density lead; Mantovani et al. 2012, DOI `10.1016/j.supflu.2011.09.001`, density lead not row-encoded. Current calculable Mazzoccoli rows scored 122/122 converged, 4.104151% AARD, -3.871436% bias, 11.683013% RMS, worst -51.419473%. Final status: preliminary / validation pending; no gate promoted.
- CO2+H2: Souissi, Kleinrahm, Yang and Richter 2017, DOI `10.1021/acs.jced.7b00213`, density; Cheng et al. 2019, DOI `10.1021/acs.jced.8b01206`, audited as H2-rich and outside current CO2-rich calculability. Promoted limited-production density-derived domain: xH2 = 0.05362 exactly at 273.15 K and 0.51352...3.03596 MPa, 293.15 K and 0.50316...4.98489 MPa, and 323.15 K and 0.54921...5.99737 MPa. Metrics: 19/19, 0.097349% AARD, +0.093717% bias, 0.149409% RMS, worst +0.409137%. Phase/VLE, caloric, acoustic and transport remain unsupported.
- CO2+CO: Chapoy et al. 2020, DOI `10.1016/j.fluid.2020.112733`, VLE lead only. No lawfully committed density rows were encoded. Final status: preliminary / validation pending.
- CO2+H2S: no lawfully committed primary row-level density dataset was added. GERG-2008 provenance is model provenance only, not independent validation. Final status: preliminary / validation pending.
- CO2+H2O homogeneous: existing Meyer-Harvey 2015 and Sanchez-Vicente-Trusler 2022 evidence remains assigned to the separate water-equilibrium provider. No homogeneous low-water CO2-rich density rows were committed. The homogeneous General Properties gate stays preliminary: binary only, xH2O = 1e-6...0.001, 350...423.15 K, 0.5...5 MPa, density and derived volumetric properties only.

## Multicomponent dry mixtures, built-ins and Phase Map

No independent dry multicomponent density dataset was committed. The Zhang 2022 ternary acquisition note remains zero-row, and the Ottoy 2020 ternary data are VLE rather than point-property density validation. Northern Lights, Brevik, Porthos and Aramis remain calculable under the General Properties product guardrail for density, molar mass, specific volume and Z, but dry-mixture density and Phase Map status remain preliminary / validation pending. Celsio remains information-only because no authoritative exact composition/P/T preset is encoded. Phase Map validation remains separate from point-property validation; no dry-mixture VLE production gate is promoted, and the PR #49 safe phase-map architecture is preserved.

## Implementation outcome

`GeneralPropertiesCapabilityMatrix` is the single source of truth for General Properties validation status. It distinguishes calculable from validated, records component/property/composition/T/P/phase scope, promotes only density and density-derived volumetric status for the CH4, O2 and H2 domains above, and keeps caloric, acoustic, transport, VLE and dry multicomponent states preliminary or unsupported. The Calculator now keeps water functionality visible outside both water domains with a nonfatal message based on `SpycherPruess2003WaterEquilibrium.validatedRangeSummary`.
