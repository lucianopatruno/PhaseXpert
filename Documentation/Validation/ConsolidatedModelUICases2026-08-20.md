# Consolidated model, UI and CCS project-case milestone

## Starting state

Work started from merged `main` at `eefaf505005ea1205db2816bd00a8885e441ee0e`, which contains PR #54. The local Xcode checkout retained the protected deployment-only `PhaseXpert.xcodeproj/project.pbxproj` diff and the untracked `Services/` and `Vendor/ThermoPack/` directories.

## UI and traceability changes

The main calculator no longer shows the large preliminary-model banner above the controls. Normal selectable model rows no longer use an orange preliminary badge as a selection affordance; unavailable providers still show an unavailable badge and local execution remains visible. The header now shows `PhaseXpert`, the subtitle `Phase behavior and properties of CO₂ mixtures`, and the existing bundled official English IFE SVG logo asset (`PhaseXpert/Resources/Assets.xcassets/IFELogoEnglish.imageset/IFELogoEnglish.svg`) at an understated size. Reset moved from the top-left toolbar to a secondary button beside the calculation action and continues to restore General Properties, pure CO₂, 50 bar(a), 20 °C, and clear loaded-case, result, warning and transient state.

The shield remains the concise scientific-status entry point. It now includes selected model identity, library/coefficient version, availability, broad pressure/temperature domain, available declared properties, limitations, calculation provenance and principal references. Calculation-specific warnings remain attached to results.

The About page now explicitly separates General Properties / CoolProp, Advanced CCS / teqp / EOS-CG, CO₂/H₂O water equilibrium, references, FALCON / IFE and contact. The contact action constructs `mailto:firmapost@ife.no?subject=PhaseXpert` directly and is covered by a focused unit test.

## Built-in CCS project cases

Northern Lights and Heidelberg Materials - Brevik CCS retain their existing representative thermodynamic presets because no primary source in this milestone required changing the encoded compositions. CCS Norway confirms the Northern Lights transport facts used in the app: four transport ships, approximately 700 km transport distance for Norwegian projects, liquefied CO₂ at about 15 barg and -26 °C, an Øygarden terminal with buffer storage, pump and heater, Phase 1 capacity about 1.5 million tonnes CO₂/year, 680 m³ tanks over 30 m tall, and a 110 km, 12 inch pipeline with about 5 million tonnes CO₂/year capacity. Sources: CCS Norway chain summary (`https://ccsnorway.com/full-scale-capture-transport-and-storage/`) and the Northern Lights project report linked by Northern Lights (`https://norlights.com/reports-2/`).

Northern Lights phase investigation found no defensible basis for changing the encoded representative preset. CCS Norway states the transport condition as approximately 15 barg and -26 °C; gauge conversion gives about 16 bar(a), encoded as 1.600 MPa(a) and 247.15 K. The pinned CoolProp 8.0.0 diagnostic gives pure CO₂ saturation pressure of 1.629264 MPa at 247.15 K. For the encoded Northern Lights specification-limit composition, CO₂ 99.9831 mol%, CO 0.0100 mol%, H₂ 0.0050 mol%, O₂ 0.0010 mol%, H₂S 0.0009 mol%, the same diagnostic places the dew/bubble pressures at approximately 1.629569-1.643887 MPa. Therefore the exact rounded app preset is just below the model saturation band and can report gas while still being consistent with the published approximate liquefied transport description. The app preserves the published rounded source state, records the boundary limitation in the case details, and does not hard-code a liquid phase or move the point without a primary source.

The Brevik name is corrected to `Heidelberg Materials - Brevik CCS` in the user-facing built-in case. CCS Norway and Heidelberg Materials confirm approximately 400,000 tonnes CO₂/year, amine post-combustion capture, CO₂ cleaning/liquefaction/buffer storage, delivery to Northern Lights at quayside, and capture/liquefaction/pipe transfer/storage-on-quay scope. Sources: CCS Norway chain summary and Heidelberg Materials Brevik CCS Facts and FAQ (`https://www.brevikccs.com/en/facts-and-faq`).

Hafslund Celsio - Oslo CCS was added as an information-only built-in project entry. CCS Norway confirms approximately 350,000 tonnes CO₂/year, amine technology, CO₂ cleaning, liquefaction, four days buffer storage and delivery to Northern Lights at the quay in the Oslo port area. Hafslund's 27 January 2025 release confirms the resumed Klemetsrud project, CO₂ terminal at the Port of Oslo, 350,000 metric tonnes CO₂/year and planned operation in Q3 2029. No public authoritative exact stream composition, impurity composition or representative loading/transport P/T was identified, so no thermodynamic preset is encoded.

Information-only built-in entries are not loadable into the calculator and cannot be duplicated to My Cases. Existing Northern Lights, Brevik, Porthos and Aramis presets, user saved cases, saved-case loading and reset behavior are preserved.

## Homogeneous CO₂/H₂O properties

The current preliminary CoolProp homogeneous wet-gas gate remains unchanged: binary CO₂ + H₂O, xH₂O = 1-1000 ppm mole basis, 350-423.15 K, 0.5-5 MPa, gas phase imposed, density calculated and molar mass/specific volume/Z derived. Density and derived volumetric properties were prioritized for possible expansion. No lawfully accessible primary low-water, CO₂-rich homogeneous-gas density table was obtained that supports extending the existing PhaseXpert gate to 60 °C / 40 bar or 100 °C / 100 bar. Existing independent water-equilibrium validation does not validate homogeneous CoolProp density, Cp, Cv, speed of sound, viscosity, thermal conductivity, enthalpy, internal energy or entropy. Therefore no homogeneous wet-property domain was broadened and no additional wet homogeneous properties were enabled.

## Dropout pressure

Dropout temperature remains limited production in the existing PR #54 validated Meyer-Harvey 2015 inversion domain. Dropout pressure remains preliminary / validation pending. The existing Meyer-Harvey rows validate saturated water content at fixed T/P, but this milestone did not identify a separate independent fixed-composition dropout-pressure series with lawfully accessible tabulated numerical data. No coefficients or thresholds were tuned.

## Wet multicomponent equilibrium

CO₂ + N₂ + H₂O, CO₂ + CH₄ + H₂O and CO₂ + O₂ + H₂O were reviewed against the existing PhaseXpert evidence base. Published work already cited in PR #54 shows impurities can materially change CO₂ water carrying capacity, including Ahmad and Gersen 2014, Cavalcanti Filho et al. 2020 (`10.1016/j.jngse.2020.103654`) and Loring et al. 2017 (`10.1021/acs.jced.6b00999`). PhaseXpert therefore continues to reject wet multicomponent equilibrium rather than silently applying binary CO₂/H₂O saturation or dropping impurities. No impurity-aware model with complete coefficients and independent validation matrix was promoted in this milestone.

## pH / aqueous speciation

pH remains research-only and separate from thermodynamic EOS/equilibrium providers. A future implementation should use a distinct aqueous chemistry provider driven by an aqueous phase basis, dissolved CO₂, T, P, water composition, salinity or ionic strength, alkalinity, and later H₂S speciation. A narrow pure-water CO₂ solver may be useful only after pressure/temperature-dependent equilibrium constants, activity assumptions and independent validation data are encoded. This milestone did not implement pH from total CO₂ or from a homogeneous EOS state.

## FALCON

The dedicated FALCON page remains in place. It still links to IFE's official FALCON CO₂ flow-loop page (`https://ife.no/en/laboratory/falcon-co2-flow-loop/`) and uses IFE's official remote photograph URL (`https://ife.no/wp-content/uploads/2018/12/picture1.jpg`) with a fallback rather than bundling the photograph. The displayed operating context remains up to 150 bar(a), -30 to +50 °C, 44 mm internal diameter, 13 m test section, -90° to +90° inclination and ECCSEL context.
