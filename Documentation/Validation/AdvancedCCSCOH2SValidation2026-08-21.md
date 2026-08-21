# Advanced CCS CO and H2S validation — 2026-08-21

## Decision

CO₂+H₂S density is promoted to **VALIDATED / LIMITED PRODUCTION** only for the complete Nazeri et al. 2016 homogeneous-gas block at exact `xCO2 = 0.9505`, `xH2S = 0.0495`, `T = 272.54...272.56 K`, and absolute `P = 0.301...3.196 MPa`. Supported properties are density and the directly density-derived molar mass, specific volume and compressibility factor. CO₂+CO density, all CO₂+CO VLE, all CO₂+H₂S VLE, caloric/acoustic/transport properties, phase envelopes and phase classification remain research-only or unsupported. No CoolProp fallback, component dropping, parameter fitting or composition normalization is used.

## Pinned formulations audited

The native route is teqp `0.23.1`, commit `a68eb9cabf47af2c4aba0d272ac10fbca4c10eca`. CO₂ uses Span-JPCRD-1996. Both CO and H₂S use the Lemmon-JCED-2006 short fundamental pure-fluid equations in the pinned teqp data. The CO₂+CO binary record is Gernert-Thesis-2013 (`betaT=0.993245`, `gammaT=1.068392`, `betaV=1.030855`, `gammaV=1.245499`, `F=0`). The CO₂+H₂S record is Kunz-JCED-2012 (`betaT=1.016034583`, `gammaT=0.92601888`, `betaV=0.906630564`, `gammaV=1.024085837`, `F=0`). Neither pair activates a departure function. These are model-provenance facts, not validation claims; no coefficients were changed.

## Acquisition and provenance

The machine-readable acquisition audit is `AdvancedCCSCOH2SAcquisitionAudit2026-08-21.json`. Routes included repository inventory, direct DOI requests to NIST TRC ThermoML, Crossref, publisher/SI discovery, institutional accepted manuscripts, author/group repositories, NIST and university repositories, DataCite/Zenodo/Figshare/Mendeley discovery, theses, and backward/forward citation chains.

The requested DOI `10.1016/j.fluid.2020.112733` is not a Chapoy CO₂+CO paper: Crossref identifies it as Ariel Chialvo's corrigendum concerning the Krichevskii parameter. It was rejected as a metadata mismatch. Exact public ThermoML data were instead recovered for Westman et al. 2018 (`10.1016/j.fluid.2018.05.006`), Souza, Al Ghafri and Trusler 2018 (`10.1016/j.jct.2018.06.022`), Chapoy et al. 2020 (`10.1016/j.jct.2020.106180`), Chapoy et al. 2013 CO₂+H₂S (`10.1016/j.fluid.2013.07.050`), and Nazeri et al. 2016 density (`10.1016/j.fluid.2016.04.024`). The Souza et al. 2019 Applied Energy CO density paper (`10.1016/j.apenergy.2019.113398`) was verified as four mixtures, 283–373 K and up to 48 MPa, but its exact density table was not recovered lawfully from the publisher, ThermoML, institutional or thesis routes and was not transcribed or digitized.

## CO₂+CO VLE

Every recovered non-pure paired TPxy row was evaluated using the existing predictive native N-component bubble and dew solver. Measured pressure was an output comparator, never a solver input. The artifact `AdvancedCCSCOH2SVLEValidation.json` stores all predicted pressures, opposite-phase compositions, convergence/status and stability diagnostics.

| Primary source | Rows | Bubble convergence; pressure AARD / bias / RMS / worst | Bubble opposite-phase MAE / RMS / worst | Dew convergence; pressure AARD / bias / RMS / worst | Dew opposite-phase MAE / RMS / worst |
|---|---:|---|---|---|---|
| Westman 2018 | 31 | 24/31; 205.072927% / +199.839903% / 710.264002% / +2818.667900% | 0.064195 / 0.175167 / 0.670765 | 24/31; 15.066674% / -12.477415% / 23.955448% / -62.484036% | 0.064440 / 0.108191 / 0.306052 |
| Souza 2018 | 102 | 67/102; 110.722946% / +105.921800% / 577.481809% / +3335.190911% | 0.032616 / 0.112997 / 0.732611 | 78/102; 329.475254% / +309.866738% / 758.467599% / +3152.731099% | 0.075661 / 0.125289 / 0.377618 |
| Chapoy 2020 | 34 | 25/34; 3.407633% / -3.407633% / 3.961972% / -6.501678% | 0.010241 / 0.014968 / 0.041379 | 24/34; 7.394778% / -6.726524% / 11.915862% / -36.399604% | 0.021722 / 0.041853 / 0.152989 |

The strongest isolated candidate was the complete Chapoy 298.1 K bubble isotherm: 5/5 converged, pressure AARD `0.914448%`, bias `-0.914448%`, RMS `0.992324%`, worst `-1.349380%`, opposite-phase MAE `0.002888`, RMS `0.004257`, worst `0.009059`. It was not promoted because independent Westman measurements at 298.2 K gave only 7/9 bubble convergence (two stability rejections), and the other two broad primary matrices show severe branch/stability failures. Westman reports maximum standard uncertainties of 9 mK, 3 kPa and mole fraction 0.001 near critical/0.0003 otherwise; Chapoy 2020 reports 0.1 K, 0.005 MPa and composition below 1.1%. The model discrepancies and nonconvergence exceed those uncertainty levels. No CO VLE gate is scientifically robust across independent neighboring evidence.

No exact CO density rows were obtained, so density, molar mass, specific volume and Z for CO remain research-only. Aramis contains CO but therefore does not acquire an Advanced production capability.

## CO₂+H₂S density

Nazeri et al. 2016 accepted-manuscript Tables 3–7 and NIST ThermoML MD5 `486a1b58bdcf853469edca32630200af` agree on absolute pressure, mass-density basis, exact composition and phase labels. ThermoML contains 450 density rows: 109 gas, 222 liquid and 119 supercritical/subcritical-fluid rows. All 450 current teqp calculations converged when the source phase label supplied the accepted phase-domain root-selection hint. Overall metrics are AARD `1.117617%`, bias `+0.111910%`, RMS `1.420696%`, worst `+5.727337%` at `nazeri2016-d3-052`.

| Nominal isotherm | Rows | Converged | AARD | Bias | RMS | Worst |
|---:|---:|---:|---:|---:|---:|---:|
| 273 K | 94 | 94 | 0.961554% | +0.883965% | 1.098781% | +2.441519% |
| 283 K | 96 | 96 | 1.316779% | -1.287412% | 1.511968% | -4.321669% |
| 298 K | 101 | 101 | 0.939760% | -0.908538% | 1.023895% | -2.852181% |
| 323 K | 76 | 76 | 1.001164% | +0.933453% | 1.513769% | +5.727337% |
| 353 K | 83 | 83 | 1.387068% | +1.345521% | 1.886168% | +4.131840% |

The promoted 273 K gas block contains every one of its 19 contiguous source rows: 19/19 converged, pressure span 0.301–3.196 MPa, measured-temperature span 272.54–272.56 K, density AARD `0.616767%`, bias `+0.232906%`, RMS `0.767045%`, and worst `+1.595572%`. Mean absolute density error is `0.308658 kg/m³`; 12/19 predictions are within the row-level ThermoML expanded density uncertainty, whose mean is `0.284211 kg/m³` and maximum is `0.4 kg/m³`. The source's Table 8 reports the 273 K gas uncertainty as average `0.6%` and maximum `1.8%`. Thus average model error is close to reported measurement uncertainty and the worst model deviation remains below the source maximum uncertainty, while the complete block supplies 19 neighboring measurements. This is a defensible narrow density gate, not a broad H₂S validation claim.

The adjacent 273 K liquid block is not included (75 rows, AARD `1.048900%`, worst `2.441519%`), nor are later isotherms; several have materially larger local errors. Exact composition tolerance is only the existing canonical numerical tolerance. The provider uses the generic N-component density route with `.homogeneousGas`, which selects the stable low-density root exactly as required by the source phase domain.

## CO₂+H₂S VLE

Chapoy et al. 2013 supplied 19 non-pure paired TPxy rows after endpoints were excluded. Bubble: 7/19 converged, pressure AARD `0.966566%`, bias `-0.804022%`, RMS `1.438754%`, worst `-3.495734%`, opposite-phase MAE `0.092276`, RMS `0.102643`, worst `0.177605`; 12 rows were stability-rejected. Dew: 7/19 converged, pressure AARD `10.598127%`, bias `+8.856876%`, RMS `14.591517%`, worst `+32.003405%`, opposite-phase MAE `0.111109`, RMS `0.162700`, worst `0.350863`; 12 rows were stability-rejected. Reported uncertainties are ±0.02 K, ±0.002 MPa and 0.006 mole fraction. Composition errors and convergence failures decisively exceed that evidence. H₂S bubble/dew remain research-only.

## Product and safety scope

The capability matrix adds an exact CO₂+H₂S property-specific density entry. The provider routes it through the existing native N-component multifluid solver and returns structured failure if the validated gas root is unavailable; there is no fallback. Capability-driven guidance exposes exact composition, measured T/P block and supported properties. The scientific shield can activate from that validated decision. H₂S support is thermodynamic density only: it implies no toxicity, corrosion, pH, water, salinity or transport prediction. Generic phase classification, phase envelopes, bubble/dew and TP flash remain unavailable or research-only.

## Low-Ar fallback and built-ins

The targeted fallback found Souissi et al. 2017 (`10.1021/acs.jced.6b00687`) only at about 24.9–50.0 mol% Ar, not the requested 0.1–5 mol% CCS range. The earlier low-Ar evidence was not rerun and Ar remains research-only. No built-in exactly matches the new binary H₂S composition and state. Aramis is unchanged and unsupported because no CO production gate was established.
