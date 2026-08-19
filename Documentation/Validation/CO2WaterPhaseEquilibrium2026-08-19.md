# CO₂/pure-H₂O phase equilibrium — 2026-08-19

## Selected model and implementation provenance

PhaseXpert implements the binary pure-water model of Spycher, Pruess & Ennis-King, *Geochimica et Cosmochimica Acta* 67 (2003) 3015–3031, DOI `10.1016/S0016-7037(03)00273-4`. The implementation is an original transcription of primary-paper equations 11–14 and Appendix B equations B1–B10. Table 1 supplies the modified Redlich–Kwong constants `aCO2 = 7.54e7 - 4.13e4 T`, `bCO2 = 27.80 cm3/mol`, `bH2O = 18.18 cm3/mol`, and `aH2O-CO2 = 7.89e7 bar cm6 K^0.5 mol^-2`. Table 2 supplies partial molar volumes `VH2O = 18.1 cm3/mol`, `VCO2 = 32.6 cm3/mol` and the base-10 equilibrium-constant polynomials: `log K0H2O = -2.209 + 3.097e-2 t - 1.098e-4 t2 + 2.048e-7 t3` and `log K0CO2(g) = 1.189 + 1.304e-2 t - 5.446e-5 t2`, with `t` in °C. Fugacities use the paper's modified Redlich–Kwong gas treatment and infinite-dilution mixing simplification; pure water activity and the paper's mole-fraction/molality conversion are used for the aqueous phase.

The implementation does not copy TOUGH/ECO2N or DuMux source. DuMux was inspected only as an independent equation-order cross-check; its GPL-3.0 code is not incorporated. Published equations, parameter values and experimental facts were transcribed and independently implemented. The paper's stated model scope is approximately 12–100 °C and up to 600 bar, but PhaseXpert does not expose that entire fitted scope as validated production capability.

## Candidate comparison

- **Spycher, Pruess & Ennis-King 2003:** mutual H₂O/CO₂ phase compositions for binary CO₂ + pure H₂O, efficient non-iterative composition equations coupled to a modified Redlich–Kwong fugacity calculation. It directly supplies both outputs required for this milestone and was selected.
- **Spycher & Pruess 2005**, DOI `10.1016/j.gca.2005.01.015`: extends the 2003 formulation to chloride brines from 12–100 °C and up to 600 bar using water and aqueous-CO₂ activity corrections, principally Rumpf and Duan–Sun treatments. It requires explicit salt/molality inputs absent from the current product and was not used for pure-water calculations.
- **Duan & Sun 2003**, DOI `10.1016/S0009-2541(02)00263-2`: Pitzer-type aqueous treatment plus a high-order CO₂ fugacity EOS for CO₂ solubility in pure water/NaCl from 273–533 K and 0–2000 bar, with reported accuracy near experimental uncertainty (about 7%). It does not directly provide the CO₂-rich water content required for mutual-solubility/dropout output and was not selected.
- **Duan et al. 2006**, DOI `10.1016/j.marchem.2005.09.001`: extends aqueous CO₂ solubility to mixed Na/K/Ca/Mg/Cl/SO₄ brines up to ionic strength 4.5 molal. It requires ionic composition inputs and remains a future brine candidate.

## Independent validation and capability gates

The independent source is Sanchez-Vicente & Trusler, *Energies* 15 (2022) 3936, DOI `10.3390/en15113936`, Table 6. The open-access numerical table contains separately sampled CO₂-rich and H₂O-rich phase compositions at nominal 373 K. Exact rows and standard uncertainties are preserved in `SanchezVicenteTrusler2022CO2WaterVLE.json`.

| Quantity | Rows | Converged | AARD | Mean signed relative deviation | RMS relative deviation | Worst |
|---|---:|---:|---:|---:|---:|---:|
| H₂O in CO₂-rich phase | 7 | 7 | 4.710285% | +0.514212% | 5.308226% | 9.270172% at 373.27 K, 15.09 MPa |
| CO₂ in H₂O-rich phase | 6 | 6 | 1.165421% | -0.189465% | 1.358951% | 2.256479% at 373.28 K, 15.09 MPa, Table 6 L6 |

The independently supported domain is binary CO₂ + pure H₂O, 373.15–373.30 K and 4.70–15.09 MPa(a). Within that narrow domain, both phase-composition outputs are **limited production** with the accuracy summary above. Aqueous-phase detection is **limited production** and uses the largest observed absolute H₂O-composition discrepancy (`0.0014924977` mole fraction) as an uncertainty-aware saturation band. This band is evidence-derived and is not a fitted parameter.

Water-dropout pressure at fixed temperature is **preliminary / validation pending**. It is solved only when the specified water content brackets a root inside the validated pressure interval; the bounded bisection never extrapolates. No independent saturation-pressure rows were available beyond the phase-composition measurements, so this derived root is not promoted. Water-dropout temperature is **unsupported** because the independent validation covers only one nominal isotherm.

## Product behavior and boundaries

For an existing binary General Properties wet-CO₂ calculation that lies inside the equilibrium gate, the calculation response separately presents water status, equilibrium H₂O saturation in the CO₂-rich phase, current H₂O, margin to saturation, CO₂ in the water-rich phase and, only when bracketed, a preliminary water-dropout pressure. The homogeneous CoolProp density remains preliminary and does not override the phase-equilibrium result. Outside the equilibrium gate no equilibrium result is attached.

The model is binary-only. CO₂/N₂/H₂O, CO₂/CH₄/H₂O and CO₂/N₂/CH₄/H₂O remain diagnostic/research-only; applying the binary result would silently omit impurity effects and is prohibited. Extension requires an independently validated multicomponent fugacity/activity model.

No pH is calculated. A later aqueous-chemistry provider should consume equilibrium P, T, aqueous-phase presence, and dissolved CO₂, then additionally require salinity/ionic strength and alkalinity; H₂S requires its own dissolved inventory and speciation reactions.
