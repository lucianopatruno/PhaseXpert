# CO₂/H₂O validation expansion and water-dropout temperature

## Independent data

Meyer and Harvey, “Dew-Point Measurements for Water in Compressed Carbon Dioxide,” *AIChE Journal* 61 (2015) 2913–2925, DOI `10.1002/aic.14818`, Table 2, is the new primary source. The NIST author manuscript is a US Government work. It reports gravimetric saturated-water mole fractions with expanded relative uncertainty (k = 2) averaging 0.3%. The machine-readable artifact preserves 50 exact rows at 294.83–353.15 K and 0.4999–5.0055 MPa. The 283.15 K isotherm was not encoded because it lies below the Spycher–Pruess–Ennis-King 2003 published 12 °C limit.

The existing Sánchez-Vicente and Trusler 2022 Table 6 artifact remains the independent 373 K source: seven CO₂-rich H₂O rows and six H₂O-rich CO₂ rows at 4.70–15.09 MPa. The IUPAC-NIST compilation of Zawisza and Malesinska 1981 provides broader water-rich-phase rows, but those historical measurements belong to the evidence base assessed by Spycher et al.; they were therefore not relabeled as independent validation or used to widen the water-rich-phase production gate.

## Results and product domains

Across all 50 Meyer–Harvey rows, including the 21.7 °C research-only isotherm, H₂O-in-CO₂ AARD is 3.297874%, signed bias −3.288853%, RMS relative deviation 4.456269%, and worst absolute deviation 12.487875% at 294.84 K and 4.9854 MPa. The independently gated 30–80 °C block contains 40/40 converged rows with AARD 2.494200%, bias −2.482924%, RMS 3.303999%, and worst 7.708346%. By nominal isotherm: 30 °C: 10 rows, AARD 4.681136%, bias −4.681136%, RMS 5.218666%, worst 7.708346%; 40 °C: 10, 3.274244%, −3.274244%, 3.744114%, 6.120840%; 60 °C: 10, 1.208817%, −1.208817%, 1.240626%, 1.706998%; 80 °C: 10, 0.812603%, −0.767496%, 0.934681%, 1.510374%. Relative to the reported 0.3% expanded uncertainty, mean absolute normalized residual is 8.314 and the worst is 25.694, so results are limited-production model predictions rather than measurement-grade values.

The H₂O-in-CO₂ and aqueous-phase-detection gate is the union of two explicit rectangles: 303.14–353.15 K at 0.4999–5.0055 MPa, and 373.15–373.30 K at 4.70–15.09 MPa. The existing 373 K H₂O-in-CO₂ validation remains 7/7, AARD 4.710285%, bias +0.514212%, RMS 5.308226%, worst 9.270172%. CO₂-in-water remains limited only to 373.15–373.30 K and 4.70–15.09 MPa: 6/6, AARD 1.165421%, bias −0.189465%, RMS 1.358951%, worst 2.256479%; no independent broader modern numerical table was lawfully obtained.

## Dropout solvers

Water-dropout temperature uses deterministic bounded bisection only inside 303.14–353.15 K and 0.4999–5.0055 MPa. Direct inversion of 30 Meyer–Harvey saturation rows at 30, 40 and 60 °C converged 30/30 with mean absolute error 0.610548 K, bias +0.610548 K, RMS 0.749815 K, and worst absolute error 1.520787 K at 303.14 K and 4.5020 MPa. The 80 °C boundary rows cannot bracket roots without extrapolation and are excluded from the direct root metric. Dropout temperature is limited production only in that bounded region. Dropout pressure remains preliminary / validation pending: composition rows validate saturation values but no independent fixed-composition saturation-pressure series was identified.

At 100 bar(a), only 100 °C lies in an independently validated region, with predicted saturation 17,914.315 ppm mole. The requested 40, 60 and 80 °C states are outside the validated pressure range; 120 °C is outside the model and validated temperature ranges. No values are presented for those states.

## Impurities and architecture

Binary equilibrium is never silently applied to wet multicomponent streams. Published experiments show that N₂, CH₄ and O₂ can reduce CO₂ water-carrying capacity: Ahmad and Gersen 2014 (Energy Procedia 63, 2402–2411) reported material reductions with 2.5 mol% impurities, Cavalcanti Filho et al. 2020 (DOI `10.1016/j.jngse.2020.103654`) found significant reductions for CO₂-rich mixtures, and Loring et al. 2017 (DOI `10.1021/acs.jced.6b00999`) measured composition-dependent CO₂/CH₄/H₂O saturation. Therefore even low impurity levels are not accepted as a validated binary approximation; N₂/CH₄/O₂ wet equilibrium remains research-only pending a multicomponent association/equilibrium model and independent validation. The separate future aqueous-chemistry interface remains aqueous-phase presence, dissolved CO₂, pressure, temperature, water composition, salinity/ionic strength and alkalinity; pH is not implemented.
