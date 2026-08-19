# CO₂ + O₂ density validation (Lozano-Martín et al. 2020)

- Primary source: D. Lozano-Martín, M. E. Mondéjar and J. J. Segovia, *Journal of Chemical Thermodynamics* 150 (2020) 106210, DOI `10.1016/j.jct.2020.106210`.
- Numerical source: author manuscript deposited by Universidad de Valladolid, Tables 2 and 5–7 (`http://uvadoc.uva.es/handle/10324/43192`). No plotted values were digitized.
- Artifact: `LozanoMartin2020CO2O2Density.csv`; 162 experimental gaseous rows, with temperature, pressure, density, expanded density uncertainty (`k = 2`), exact normalized binary composition, current native result and relative deviation.
- Composition provenance: Table 2 normalized values are xO₂ = 0.05032089, 0.09985604 and 0.19990709; expanded composition uncertainties are 0.00001800, 0.00001632 and 0.00001538 mole fraction, respectively.
- Model identity: the pinned teqp Gernert-Thesis-2013 record and EOS-CG-2021 target record are identical for CO₂+O₂: betaT = 1, gammaT = 1.031986, betaV = 1, gammaV = 1.08446 and F = 0 (no departure function). Thus the current generic EOS-CG-2021 construction is the same binary formulation previously tested against Mantovani 2012, not a second-generation replacement.
- Calculation: teqp v0.23.1 (`a68eb9cabf47af2c4aba0d272ac10fbca4c10eca`), current PhaseXpert embedded pure-fluid records and EOS-CG target pair, selecting the lowest-density root because every primary-source row is explicitly classified as gaseous.

| xO₂ | Rows / converged | AARD | Bias (calculated − experimental) | RMS | Worst absolute deviation |
|---:|---:|---:|---:|---:|---:|
| 0.05032089 | 45 / 45 | 0.079069% | +0.004184% | 0.113610% | 0.393366% at 275.001 K, 3.940 MPa (109.732 experimental; 109.300351603473 kg/m³ calculated) |
| 0.09985604 | 47 / 47 | 0.150828% | −0.058490% | 0.263784% | 1.211991% at 293.070 K, 6.067 MPa |
| 0.19990709 | 70 / 70 | 0.226054% | +0.057037% | 0.513056% | 3.313709% at 299.946 K, 12.259 MPa |

Only the exact xO₂ = 0.05032089 homogeneous-gas dataset is production-enabled. Its worst model deviation is below the EOS-CG 1% claimed mixture uncertainty and is of the same order as the experimental expanded density uncertainty at the worst point (0.034%). No composition interpolation, isotherm interpolation, VLE, caloric, acoustic or dense-phase capability is inferred. The 0.10 and 0.20 datasets remain validation evidence only; their localized worst points prevent promotion in this milestone.
