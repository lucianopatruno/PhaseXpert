# CO₂-N₂ density validation

## Status

This milestone establishes the evidence and evaluation pipeline. It does **not**
claim that CoolProp 8.0.0 is validated for CO₂-N₂ density. No experimental
numeric value has been copied into the repository yet.

The executable provider remains preliminary, limited to density and provider
phase for binary mixtures with at most 10 mol% N₂. Dynamic viscosity and a
mixture phase envelope remain unavailable.

## Primary reference and lawful data route

The first selected publication is:

- Mazzoccoli, M.; Bosio, B.; Arato, E. (2012),
  *Pressure-Density-Temperature Measurements of Binary Mixtures Rich in CO₂ for
  Pipeline Transportation in the CCS Process*, Journal of Chemical &
  Engineering Data 57, 2774–2783,
  [doi:10.1021/je300590v](https://doi.org/10.1021/je300590v).

The publisher reports measurements for CO₂ with N₂, O₂, or Ar from 273.15 K to
293.15 K and 1 MPa to 20 MPa, with CO₂ above 85 mol%. Only CO₂-N₂ points with
N₂ at or below PhaseXpert's temporary 10 mol% cap are eligible for this
milestone.

The preferred machine-readable route is the public NIST ThermoML/Data Archive:

- NIST ThermoML/Data Archive,
  [doi:10.18434/mds2-2422](https://doi.org/10.18434/mds2-2422);
- archive snapshot: `ThermoML.v2020-09-30.tgz`;
- archive terms: NIST open-data terms, while the underlying article must still
  be cited.

NIST states that its personnel checked archive data for completeness and
accuracy of representation, but did not critically evaluate the experimental
values. Therefore, the ThermoML record is an ingestion source, not an
independent scientific endorsement. Every imported point must be checked
against the article or another authoritative rendering.

A second source for broader temperature and pressure coverage is:

- Brugge, H. B.; Holste, J. C.; Hall, K. R.; Gammon, B. E.; Marsh, K. N.
  (1997), *Densities of Carbon Dioxide + Nitrogen from 225 K to 450 K at
  Pressures up to 70 MPa*, Journal of Chemical & Engineering Data 42, 903–907,
  [doi:10.1021/je970044w](https://doi.org/10.1021/je970044w).

Its publisher abstract reports five gravimetrically prepared mixtures and
density accuracy better than ±0.1%. That statement must not be transferred to
the Mazzoccoli dataset or treated as a PhaseXpert accuracy claim.

## Evidence gate

The implementation in
`ExperimentalDensityValidation.swift` enforces the following order:

1. obtain a lawful table or ThermoML record;
2. retain the original file and compute its checksum outside the app repository;
3. convert pressure, temperature, composition, density and uncertainty to SI;
4. record a table/row locator for every point;
5. have a second reviewer check values, units and composition independently;
6. mark the versioned dataset `approved`;
7. approve and version an acceptance policy **before** generating or inspecting
   CoolProp deviations;
8. generate provider predictions and preserve provider/library versions;
9. evaluate without changing the locked policy;
10. report all points, including failures and outliers.

The evaluator rejects unapproved datasets, missing review provenance, absent or
invalid acceptance policies, duplicate identifiers, non-finite values,
unsupported compositions and missing predictions.

## Acceptance policy

No numerical pass tolerance is approved yet. It must be derived from:

- the source's point or dataset uncertainty and its stated meaning;
- conversion and composition uncertainty;
- the model claim IFE intends to make;
- additional allowance justified before CoolProp results are inspected.

The policy must contain a version, maximum absolute relative deviation,
rationale, approver and approval timestamp. It must not be widened after seeing
a failure merely to obtain a passing result.

## Initial coverage matrix

Subject to available eligible reference points, select cases covering:

| Use case | Intended coverage |
| --- | --- |
| Dense pipeline | 70–200 bar abs, 0–20 °C, several N₂ levels up to 10 mol% |
| Compression/capture | 10–200 bar abs, 0–20 °C within the selected paper |
| Critical-region sensitivity | points below, near and above the mixture transition region |
| Composition boundary | low N₂, an intermediate value, and exactly 10 mol% when available |

Mazzoccoli does not cover refrigerated ship conditions below 0 °C. Those require
a separate approved dataset; they must not be inferred by extrapolating the
pipeline dataset.

## Required deliverables before changing the app status

- reviewed machine-readable dataset committed with redistribution permission;
- checksum and archive/paper provenance;
- preapproved tolerance policy;
- automated native-provider reference tests;
- maximum and mean absolute relative deviation report;
- plots or tables showing error versus pressure, temperature and composition;
- documented outliers and model failures;
- IFE scientific review record.

Until all deliverables are complete, every CO₂-N₂ result remains labelled
preliminary and unsuitable for engineering, safety, commercial or regulatory
decisions.
