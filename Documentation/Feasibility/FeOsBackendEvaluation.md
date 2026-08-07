# FeOs Backend Feasibility Evaluation

This milestone evaluates whether FeOs can provide a fully local, offline phase-boundary backend for PhaseXpert through its native Rust API. It does not modify the production CoolProp provider, the Swift UI, the Xcode project, PR #28, PR #29, or PR #30.

## Repository Reconciliation

The accepted `main` head verified from `origin` for this branch is `f75052489baf8efb798fffcb77137b730d4ceaa4`. The branch for this work is `agent/feos-backend-feasibility`.

The prior draft feasibility PRs were confirmed and left untouched:

| PR | Branch | Confirmed head | State |
| --- | --- | --- | --- |
| #28 | `agent/native-srk-phase-envelope-prototype` | `6537f82a5d894dc172270ff5d1cb153d405c30e1` | open draft |
| #29 | `agent/coolprop8-backend-feasibility` | `1b0c39131e9a63ea05983b14532ce553e0f98467` | open draft |
| #30 | `agent/teqp-backend-feasibility` | `e303c9d2b6e636727edaef92b1e867e4c5a77976` | open draft |

Protected unrelated local artifacts were preserved: `PhaseXpert.xcodeproj/project.pbxproj`, `Services/`, `Vendor/ThermoPack/`, existing ignored CoolProp artifacts, and ignored Xcode, SwiftPM, Rust, Cargo, Python, dependency, and cache artifacts.

## Pinned FeOs Source

The official repository is `https://github.com/feos-org/feos`; releases are at `https://github.com/feos-org/feos/releases`; generated Rust documentation is available through `https://docs.rs/feos` and `https://docs.rs/feos-core`.

The newest official release tag observed for this milestone is `v0.10.1`. The annotated tag peels to immutable commit `c658aeab484f7a7096bfbf5425e40effd60da167`.

FeOs is licensed `MIT OR Apache-2.0`. The workspace uses Rust edition 2024. The root workspace dependency list includes `quantity`, `num-dual`, `ndarray`, `nalgebra`, `thiserror`, `conv`, `num-traits`, `serde`, `serde_json`, `indexmap`, `itertools`, `rayon`, `petgraph`, `rustdct`, `rustfft`, `libm`, `gauss-quad`, `approx`, `criterion`, `paste`, `rusqlite`, and `csv`. A complete resolved Cargo dependency tree and lockfile could not be generated because `cargo` is not installed in this validation environment.

## Native Rust API Findings

The pinned source exposes high-level Rust APIs relevant to the requested architecture:

| Capability | Finding |
| --- | --- |
| Pure saturation | `PhaseDiagram::pure` and `PhaseEquilibrium::pure` exist. |
| Bubble-point solve | `PhaseEquilibrium::bubble_point` exists for generic composition dimensions. |
| Dew-point solve | `PhaseEquilibrium::dew_point` exists for generic composition dimensions. |
| Fixed-composition bubble/dew lines | `PhaseDiagram::bubble_point_line` and `PhaseDiagram::dew_point_line` exist and iterate high-level solves from prior accepted states. |
| Binary diagrams | `PhaseDiagram::binary_vle` exists for binary diagrams. |
| TP flash and stability | `PhaseEquilibrium::tp_flash`, `State::tp_flash`, and `State::stability_analysis` exist. |
| Critical points | `State::critical_point_pure`, `critical_point_binary`, and `critical_point` exist. |
| Phase compositions | `PhaseEquilibrium` exposes liquid and vapor states with mole fractions. |
| Residuals | `State::chemical_potential`, `residual_chemical_potential`, and `ln_phi` exist. |
| Solver limits | `SolverOptions` exposes `max_iter` and `tol`. |

These APIs are more directly aligned with PhaseXpert's target than the teqp API because fixed-composition bubble and dew point lines are present. However, the scientific gate still requires a single immutable model and parameter set for the required compositions.

## PC-SAFT Parameter Findings

The primary model selected for inspection was PC-SAFT using FeOs's recommended Esper 2023 pure parameters and Rehner 2023 binary parameters where available.

The pinned `parameters/pcsaft/esper2023.json` file includes pure parameters for CO2, N2, O2, Ar, CH4, CO, H2S, and H2O. Hydrogen is not in Esper 2023 but is present in `parameters/pcsaft/eller2022.json`; mixing that with Esper 2023 would be a parameter-set change and cannot be treated as a single validated model without further evidence.

The pinned `parameters/pcsaft/rehner2023_binary.json` file contains CO2/CH4 and CO2/CO binary interaction parameters, but inspection found no CO2/N2 entry, no CO2/O2 entry, no CO2/Ar entry, no CO2/H2 entry, no CO2/H2S entry, and no CO2/H2O entry. In particular, the required core matrix is blocked because CO2/N2 binary interaction data are missing.

Do not treat missing FeOs PC-SAFT binary interaction parameters as zero. The milestone did not tune, estimate, or substitute binary interaction parameters.

## CO2/N2 Parameter Search

The CO2/N2 parameter search checked:

| Source | Result |
| --- | --- |
| FeOs v0.10.1 `parameters/pcsaft/rehner2023_binary.json` | No nitrogen entries and no CO2/N2 entry found. |
| FeOs current `main` `parameters/pcsaft/rehner2023_binary.json` | No nitrogen entries and no CO2/N2 entry found. |
| FeOs historical commits `b946c0ef`, `0129c5a3`, and `d7d99fdd` for `rehner2023_binary.json` | Historical database sizes were 7860, 7860, and 7848 records; no nitrogen or CO2/N2 record was found. |
| FeOs `parameters/pcsaft/README.md` and `literature.bib` | Esper 2023 pure-parameter and Rehner 2023 binary-parameter provenance was identified, but no directly packaged CO2/N2 BIP. |
| Rehner, Bardow, Gross, International Journal of Thermophysics 44, 179 (2023), DOI `10.1007/s10765-023-03290-3` | Relevant source for the FeOs Rehner 2023 parameter database, but no redistributable CO2/N2 entry was found in the FeOs dataset derived from it. |
| Nikolaidis, Privat, Jaubert, Economou, Journal of Chemical & Engineering Data 69, 320-337 (2024), DOI `10.1021/acs.jced.2c00781` | Relevant PC-SAFT BIP benchmark publication; redistribution terms and direct compatibility with the FeOs Esper/Rehner parameter set remain unproven from accessible authoritative metadata. |
| CO2 impurity and CCS PC-SAFT literature search | Papers discuss CO2/N2 and PC-SAFT, including cases using fitted values or `kij = 0`, but no directly compatible, pinned, openly redistributable FeOs PC-SAFT CO2/N2 parameter was established. |

This is not proof that no CO2/N2 PC-SAFT parameter exists anywhere. It is proof that this milestone did not find one that is simultaneously pinned, openly redistributable, sign-convention-clear, and directly compatible with the selected FeOs PC-SAFT implementation and pure-component parameter set.

## Benchmark Outcome

The actual native Rust scientific benchmark did not run. Two independent stop conditions remain before numerical boundary calculations:

1. The required CO2/N2 PC-SAFT binary interaction parameter was not found in the pinned FeOs parameter files.
2. `cargo` is not installed in the validation environment, so the pinned native Rust feasibility crate could not be built or run and no `Cargo.lock` could be generated.

The deterministic JSON report records pure CO2, 97/3 CO2/N2, 90/10 CO2/N2, near-pure CO2/N2, ppm N2 in CO2, and the requested multicomponent cases. Every branch reports zero attempted, zero converged, and zero accepted points. Pressure-error statistics, phase compositions, phase distinctions, residuals, critical-region behaviour, continuous coverage, lowest 90/10 bubble temperature, and pure-CO2 endpoint improvement are unavailable because no FeOs-calculated accepted boundary interval exists.

Invalid empty, negative, duplicate, unsupported, non-finite, and non-normalized inputs are rejected before FeOs invocation.

## Gate Decision

Scientific gate result: failed before numerical benchmarking.

Required classification: FeOs lacks the required parameters or component coverage.

Phase 4 was not reached. No iOS static library build, C ABI proof, XCFramework packaging, production provider work, Xcode project change, UI change, simulator acceptance, or physical-device validation is justified by this milestone.
