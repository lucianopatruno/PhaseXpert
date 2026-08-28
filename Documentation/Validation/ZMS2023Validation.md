# ZMS 2023 CO2/CH4/N2 acquisition and validation

## Decision

`RESEARCH-ONLY — EXACT FORMULATION NOT RECONSTRUCTABLE FROM PUBLIC MATERIAL`. No diagnostic or production model was implemented. The published article is openly available, but the exact author implementation needed to resolve contradictions and omissions was not found in any public lawful route. Implementing a model under the ZMS name would require assumptions prohibited by PhaseXpert's scientific safeguards.

## Primary source and acquisition

The primary source is Jia Zhang, Shide Mao and Zeming Shi, “A Helmholtz Free Energy Equation of State of CO2-CH4-N2 Fluid Mixtures (ZMS EOS) and Its Applications,” Applied Sciences 13 (2023) 3659, DOI `10.3390/app13063659`. The milestone request and the prior bake-off called the authors Xu, Mao and Zheng; that attribution belongs to another generalized Helmholtz paper and is corrected here. The ZMS article is CC BY 4.0. Crossref and OpenAlex confirm the version-of-record license. The article PDF is not committed.

The publisher article, PDF/XML/notes/supplement routes, MDPI special-issue reprint, Crossref, OpenAlex, DOAJ, GitHub, GitLab, Bitbucket, Zenodo, Figshare, OSF, author/institutional pages, correspondence-email searches, title/DOI searches, and Fortran/source/coefficient searches were audited. No source archive, code attachment, Origin project, repository, or source hash was found. The article states only that the Fortran codes and Origin projects can be obtained freely from the corresponding author. “Freely obtainable” does not establish a public download or a software license.

## Identity established and blockers

The article identifies Span–Wagner 1996 CO2, Setzmann–Wagner 1991 CH4 and Span et al. 2000 N2 pure-fluid EOSs. Its mixture residual is a pure-fluid sum plus a pairwise Lemmon–Jacobsen 1999 ten-term departure polynomial. It prints four parameters for each ordered pair CH4/CO2, CO2/N2 and CH4/N2: 12 numerical pair coefficients in total. There is no ternary-specific departure coefficient. Those 12 values are transcribed exactly in `ZMS2023ModelIdentity.json`.

Identity is nevertheless incomplete. Table 1 labels 90.6941 K, 216.592 K and 63.151 K as critical temperatures for CH4, CO2 and N2; these are their triple-point temperatures, while Equation 5 requires critical temperatures. The article references but does not print the 10 universal departure terms and their 30 N/d/t values. It also does not specify the pure-residual scaling/mapping sufficiently to prove an exact teqp representation. No published numerical reference-state table permits choosing between article-literal and presumed-corrected interpretations. The unavailable Fortran is therefore essential for exact reproduction. Neither substituting known critical temperatures nor importing a similarly named Lemmon–Jacobsen function was attempted.

## Fitting-data and holdout audit

The CH4/N2 pair used 433 selected PVTx rows and 270 selected VLE rows from the datasets enumerated in `ZMS2023ValidationResults.json`. The CO2/CH4 and CO2/N2 pair parameters came from the authors' 2016 and 2020 models, but the exact row-level fitting selections were not resolved from the ZMS article. The article's ternary evaluation totals 839 PVTx rows across five datasets; because ZMS adds no ternary coefficient these are not ternary fitting rows, but they remain author-selected evaluation rather than a PhaseXpert independent holdout. Exact Zhang 2022 ternary density rows remain lawfully unavailable in this repository.

Ottøy 2020 supplies 62 exact external ternary VLE rows and is a valid independent candidate because it is absent from the cited ZMS evaluation. Ghafri 2016, Liu 2017 and Mazzoccoli 2012 remain pair-level candidates, but their independence from the earlier pair regressions cannot all be established without the pair fitting manifests. No ZMS metric was computed because no identity-complete implementation exists. Reporting the article's approximately 0.40% aggregate AARD as an independent PhaseXpert result would be scientifically invalid.

## Implementation, performance and product impact

No teqp JSON, custom Helmholtz implementation, native bridge change, XCFramework rebuild, runtime benchmark, stability result, VLE result, capability gate, routing change or UI/localization change was made. EOS-CG remains the unchanged baseline. Northern Lights, Brevik, Porthos and Aramis are unchanged; Porthos would not become eligible merely by containing CO2/N2/CH4 because its additional components cannot be dropped.

## Reproducibility and integrity

Run `python3 Scripts/validate-zms-2023.py` and `swift test --package-path PhaseXpertCore --filter ZMS2023DecisionTests`. The checks lock the primary-source hash, all 12 published pair coefficients, the 30-value departure-term omission, the fitting-row inventory, null benchmark metrics, negative decision, and unchanged production posture. No coefficient or BIP was invented or fitted, no missing term was guessed, no validation value was invented, no figure was digitized, no software output was treated as experiment, no composition was normalized, no component was dropped, and no unstable state was accepted.
