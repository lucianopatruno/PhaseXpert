# H₂O thermodynamics milestone — 2026-08-19

## User-visible General Properties capability

PhaseXpert enables a deliberately narrow **preliminary / validation-pending** binary CO₂/H₂O homogeneous-gas calculation through pinned CoolProp 8.0.0 (`ae81610e7d23efc57f9d051c8e70a4d66e87537f`). The pure-fluid records are Span–Wagner CO₂ and Wagner–Pruß/IAPWS-95 water. The binary record is the Gernert-Thesis-2013 `CarbonDioxide-Water` multifluid pair: `betaT=1.030538`, `gammaT=0.828472`, `betaV=1.021392`, `gammaV=0.895156`, `F=1`, with its eight-term exponential departure function.

The exposed domain is binary CO₂/H₂O, xH₂O = 0.000001–0.001 (1–1000 ppm, mole basis), 350–423.15 K and 0.5–5 MPa. The bridge uses `AbstractState`, explicitly imposes the gas phase, and never calls the unsafe high-level mixture `PhaseSI`/PT-flash path. It returns homogeneous density; PhaseXpert transparently derives mixture molar mass, specific volume and compressibility factor. Cp, Cv, sound speed, transport, phase maps, dew/dropout, mutual solubility, aqueous phase behavior and pH are explicitly unavailable. Three boundary/representative iOS states converged. This is numerical-safety evidence, not independent accuracy validation; no experimental rows are encoded and no production accuracy claim is made.

## Advanced CCS / EOS-CG audit

Pinned teqp v0.23.1 uses the same Gernert-Thesis-2013 CO₂/H₂O reducing parameters and `CarbonDioxide-Water` departure function, with Span–Wagner CO₂ and Wagner–Pruß water pure EOS records. EOS-CG was designed for humid and CCS gases, but homogeneous construction is not mutual-solubility validation. No suitable independent, composition-resolved homogeneous CO₂-rich density table was encoded in this milestone; therefore the Advanced density validation count is 0 rows and AARD/bias/RMS/worst are unavailable. Advanced CO₂/H₂O remains diagnostic/research-only.

The existing generic native diagnostic converges representative CO₂/H₂O and CO₂/N₂/H₂O states. This milestone also exercises CO₂/CH₄/H₂O and CO₂/N₂/CH₄/H₂O at homogeneous diagnostic states. These are architecture and numerical-execution checks only; no multicomponent wet production gate is inferred.

## Mutual-solubility model review

| Candidate | Basis and outputs | Published scope | Implementation/licensing decision |
|---|---|---|---|
| Spycher, Pruess & Ennis-King 2003, DOI `10.1016/S0016-7037(03)00273-4` | Modified Redlich–Kwong gas fugacity plus aqueous equilibrium constants/activity treatment; yields H₂O in the CO₂-rich phase and CO₂ in pure water | Approximately 12–100 °C and up to 600 bar for CO₂/H₂O | Best conceptual fit for a first pure-water CCS mutual-solubility provider. Equations are published, but a production port still needs a complete coefficient transcription audit and row-level reproduction of the paper’s validation tables. No source code was copied in this PR. |
| Spycher & Pruess 2005, DOI `10.1016/j.gca.2005.01.015` | Extends the phase-partitioning treatment to chloride brines with salinity/activity corrections | CCS reservoir temperatures/pressures, pure water through chloride brines | Appropriate second step after the pure-water implementation; requires explicit salt composition/molality inputs and brine validation, which the current product model does not yet collect. |
| Duan & Sun 2003, DOI `10.1016/S0009-2541(02)00263-2` | Aqueous chemical-potential/activity model for CO₂ solubility in pure water and NaCl solutions | 273–533 K, 0–2000 bar; published standard error about 4.5% for NaCl-solution data | Wider range but primarily CO₂-in-aqueous-phase output; the legacy program’s redistribution terms and a faithful coefficient/code audit are not established here. Not selected for integration. |
| Duan et al. 2006, DOI `10.1016/j.marchem.2005.09.001` | Non-iterative extension for mixed-ion brines; CO₂ solubility in aqueous phase | 273–533 K, 0–2000 bar, ionic strength up to about 4.5 molal | Valuable for later brine work, but needs Na/K/Ca/Mg/Cl/SO₄ inputs absent from PhaseXpert and does not by itself provide the CO₂-rich water content. |

This was the PR #52 checkpoint. The subsequent phase-equilibrium milestone independently implements and validates the binary pure-water Spycher 2003 model; see `CO2WaterPhaseEquilibrium2026-08-19.md`. EOS-CG/CoolProp homogeneous execution remains deliberately separate from aqueous equilibrium.

## Later pH/speciation provider

pH remains separate from the EOS and phase-partitioning providers. A useful request needs confirmation that an aqueous phase exists, T, P, dissolved CO₂ from the phase-equilibrium provider, salinity/ionic strength, alkalinity, and later dissolved H₂S. Minimum species are CO₂(aq), H⁺, OH⁻, HCO₃⁻ and CO₃²⁻; later H₂S(aq), HS⁻ and S²⁻. PHREEQC/IPhreeqc remains a candidate because it is a mature USGS geochemical solver, but iOS compilation, database selection/size and licensing, isolation/thread safety, and CCS benchmark validation must be audited before adding it. A narrow native carbonate-speciation solver may be smaller, but would require equally traceable equilibrium constants, activity corrections and pressure dependence.
