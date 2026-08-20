# Wet CO₂ engineering milestone

## Starting point

This milestone starts from merged `main` after PR #55. The accepted baseline already includes preliminary homogeneous CO₂/H₂O density, limited-production binary CO₂/pure-H₂O equilibrium and dropout temperature, explicit rejection of wet multicomponent equilibrium, and research-only pH/speciation.

## Dropout pressure

Dropout pressure remains **preliminary / validation pending**. The current code can solve pressure at fixed temperature and water content by inverting the validated binary CO₂/pure-H₂O saturation equation, but numerical inversion is not independent validation.

The existing lawfully encoded Meyer & Harvey (2015) dew-point rows were used as a diagnostic inversion check only. They are not independent of the saturation validation already used for binary water content and dropout-temperature checks. Diagnostic inversion over the existing 30–80 °C validated region gives:

- source: Meyer & Harvey 2015 CO₂/H₂O dew-point rows already encoded in `Documentation/Validation/MeyerHarvey2015CO2WaterDewPoint.json`
- rows in region: 40
- converged inversion rows: 35
- MAE: 0.153352 MPa, 1.53352 bar
- signed bias: -0.153352 MPa
- RMS: 0.254876 MPa
- AARD: 4.208242 %
- relative bias: -4.208242 %
- relative RMS: 5.952205 %
- worst absolute and relative deviation: 0.812114 MPa / 16.224430 % at 303.15 K and 5.0055 MPa

No production gate is promoted from this diagnostic because the rows are not independent and the pressure residuals are materially broader than the directly validated dropout-temperature residuals. No coefficients or thresholds were tuned.

## Wet multicomponent equilibrium

Wet multicomponent equilibrium remains **unsupported / research-only**. PhaseXpert continues to reject CO₂ + N₂ + H₂O, CO₂ + CH₄ + H₂O and CO₂ + O₂ + H₂O before calculation rather than applying binary CO₂/H₂O equilibrium while silently dropping impurities.

Candidate literature and model families reviewed for future implementation include:

- Song, Fadaei and Sinton (2014), direct dew pressure / water content for CO₂-rich mixtures with N₂/O₂ impurities, DOI `10.1021/es404618y`
- Qin, Rosenbauer and Duan (2008), CO₂/CH₄/H₂O VLE at high pressure and temperature, DOI `10.1016/j.gca.2008.07.017`
- impurity-aware water-content and water-carrying-capacity work already cited by PR #54 / PR #55, including Ahmad and Gersen (2014), Cavalcanti Filho et al. (2020), DOI `10.1016/j.jngse.2020.103654`, and Loring et al. (2017), DOI `10.1021/acs.jced.6b00999`

No ternary model is promoted in this milestone because the implementation would require either unavailable tabulated validation rows, an explicitly sourced impurity-aware model not yet encoded, or coefficients/corrections that PhaseXpert must not invent. The next defensible route is to obtain machine-readable primary ternary data and implement a published impurity-aware model with complete coefficient provenance.

## Homogeneous wet CO₂ properties

The preliminary homogeneous CoolProp wet-gas domain remains unchanged:

- binary CO₂ + H₂O only
- H₂O = 1–1000 ppm mole basis
- 350–423.15 K
- 0.5–5 MPa
- imposed homogeneous gas state
- density calculated; molar mass, specific volume and compressibility factor derived

No homogeneous property gate is broadened. Water-equilibrium states at 60 °C / 40 bar / 500 ppm and 100 °C / 100 bar / 500 ppm remain intentionally independent: equilibrium can be available while homogeneous properties are unavailable. No independent primary low-water, CO₂-rich homogeneous-property dataset was encoded for density, Cp, Cv, speed of sound, viscosity, thermal conductivity, enthalpy, internal energy or entropy.

## Aqueous pH / speciation

pH remains **research-only** and separate from thermodynamic EOS/equilibrium providers. A production path should use a distinct aqueous chemistry provider that receives an aqueous-phase state from the thermodynamic layer.

Minimum future pure-water chemistry:

- CO₂(aq), with an explicit convention for hydrated CO₂/H₂CO₃
- H⁺
- OH⁻
- HCO₃⁻
- CO₃²⁻
- temperature-dependent equilibrium constants
- pressure and activity treatment appropriate to the validated domain

Potential future implementation paths are a narrow native carbonate speciation solver with published constants and independent pH validation, or a PHREEQC-derived integration after license, iOS build, database footprint, thread-safety and validation review. No production pH value is exposed from total CO₂ or from a homogeneous EOS state.

## Performance

Existing binary pure-water equilibrium performance remains sub-millisecond in unit diagnostics. The new dropout-pressure diagnostic test records the inversion path only; no new production numerical path is enabled, so no new optimization was performed.
