# teqp Backend Feasibility Evaluation

This milestone evaluates whether teqp can provide a fully local, offline phase-boundary backend for PhaseXpert. It does not modify the production CoolProp provider, the app UI, the existing XCFramework, PR #28, or PR #29.

## Repository Reconciliation

The accepted `main` head verified from `origin` for this branch is `f75052489baf8efb798fffcb77137b730d4ceaa4`. The branch for this work is `agent/teqp-backend-feasibility`.

The prior draft feasibility PRs were inspected for context and left untouched:

| PR | Branch | Confirmed head | Result |
| --- | --- | --- | --- |
| #28 | `agent/native-srk-phase-envelope-prototype` | `6537f82a5d894dc172270ff5d1cb153d405c30e1` | Custom native SRK failed the numerical acceptance gate. |
| #29 | `agent/coolprop8-backend-feasibility` | `1b0c39131e9a63ea05983b14532ce553e0f98467` | CoolProp 8 HEOS, SRK, and PR phase-envelope implementations failed the macOS scientific gate. |

Protected unrelated local artifacts were preserved: `PhaseXpert.xcodeproj/project.pbxproj`, `Services/`, `Vendor/ThermoPack/`, existing ignored CoolProp artifacts, and ignored Xcode, SwiftPM, pytest, `.DS_Store`, dependency, and cache artifacts.

## Pinned teqp Source

The official upstream repository is `https://github.com/usnistgov/teqp` and the documentation is published at `https://teqp.readthedocs.io/`. The newest official release tag observed for this milestone was `v0.23.2`, pinned to immutable commit `5f62a6f515d517e39c3fb035c11a03524ffa3ad6`.

The source carries a NIST public-domain-style notice and disclaimer in `LICENSE.md`. The source checkout used for inspection included these submodules:

| Dependency | Commit |
| --- | --- |
| Catch2 | `4e8d92bf02f7d1c8006a0e7a5ecabd8e62d98502` |
| Eigen | `da19f7a9105374958cad7f9ee17c4596a54be51c` |
| REFPROP-interop | `07562a51241431ea6cccbaffb3dd5274364ae99e` |
| autodiff | `cb2d6e867b105cd0090ebcce8bddf05a4592b6ab` |
| json-schema-validator | `920bddd7c0aeb26fa02f45f56743aef750cfcc89` |
| mcx | `bc5f996f090a93e7e4e9358c4ee20bf06db57afc` |
| pybind11 | `8862cd4ef96b16d17a66a81ecd3b6e1604362fd7` |

The milestone did not use REFPROP files and did not add proprietary data.

## Native C++ API Findings

The public native C++ interface exposes pure-fluid and mixture building blocks that could be called from an embedding layer:

| Required capability | Finding |
| --- | --- |
| Pure-fluid saturation boundary | `pure_VLE_T` and `solve_pure_critical` are exposed. |
| Mixture bubble-point calculation | `mix_VLE_Tx`, `mix_VLE_Tp`, and `mixture_VLE_px` are exposed, but require caller-supplied starting liquid and vapor density vectors. |
| Mixture dew-point calculation | Same mixture APIs apply, with caller-owned initialization and phase/root selection. |
| Binary VLE continuation | `trace_VLE_isotherm_binary` and `trace_VLE_isobar_binary` are exposed for binary systems. |
| Multicomponent VLE continuation | No turnkey public native multicomponent envelope tracer was found. |
| Critical-point or critical-locus calculation | `solve_pure_critical`, `trace_critical_arclength_binary`, and criticality condition helpers are exposed; a complete general multicomponent locus path was not established. |
| Stability or phase identification support | Fugacity coefficients, chemical-potential VLE residuals, and Hessian helpers are exposed; PhaseXpert would still own stability classification and branch/root tracking. |
| Narrow C boundary | teqp can build an optional `teqpc` shared-library target, but this milestone did not establish a stable static C ABI suitable for Swift and iOS packaging. |

The available API is therefore not a drop-in phase-envelope backend. Successful use for PhaseXpert would require bounded initialization, continuation, retry policy, root tracking, phase identification, stability rejection, branch classification, detached-segment rejection, and cancellation isolation around teqp calls.

## macOS Compile Probe

A no-integration macOS CMake build probe was run against the pinned source with Python disabled:

`cmake -DTEQP_NO_PYTHON=ON -DTEQP_NO_TESTS=ON -DTEQP_NO_TEQPCPP=OFF -DTEQP_TEQPC=OFF`

Result:

| Item | Value |
| --- | --- |
| Compiler | AppleClang 21.0.0.21000101 |
| Language standard | C++20 |
| Configure time | 73.25 s |
| Build time | 404.01 s |
| Source checkout size | 238M |
| Build tree size | 424M |
| Library form | `libteqpcpp.a` |
| Static library size | 62M |
| Result | Passed on macOS |

This proves a native macOS static C++ build is possible in the current environment. It does not prove iOS cross-compilation, symbol isolation, Swift ABI shape, thread safety, or acceptable mobile footprint.

## Model Selection Matrix

| Model | Component coverage | Data provenance | Phase-equilibrium applicability | Finding |
| --- | --- | --- | --- | --- |
| teqp GERG-2008 residual model | Covers the required named components CO2, N2, O2, Ar, H2, CH4, CO, H2S, and H2O through teqp names such as `carbondioxide`, `nitrogen`, and `hydrogensulfide`. | Hard-coded in teqp source under the teqp license notice. | Exposes mixture state solves and binary tracing, but no turnkey public native multicomponent envelope tracer was found. | Component coverage is promising, but PhaseXpert would need substantial caller-owned continuation and classification. |
| teqp multifluid using CoolProp-format data | Depends on a separately pinned CoolProp-format fluid and mixture data tree. | Not bundled with teqp; plausible open redistribution through MIT CoolProp data must be pinned and packaged separately. | Same native mixture solve APIs, with caller-owned initialization and continuation. | Model data packaging and exact component/departure coverage remain unproven. |
| teqp SRK | Requires pure critical data, acentric factors, alpha-function choices, and a complete binary interaction matrix. | Not present on accepted `main` for the full PhaseXpert impurity set. | Cubic construction and VLE solve APIs exist. | Blocked because inventing or zeroing BIPs would violate PhaseXpert scientific safeguards. |
| teqp Peng-Robinson | Requires pure critical data, acentric factors, alpha-function choices, and a complete binary interaction matrix. | Not present on accepted `main` for the full PhaseXpert impurity set. | Cubic construction and VLE solve APIs exist. | Blocked for the same parameter-provenance reason as SRK. |

No model was accepted for a numerical PhaseXpert phase-boundary benchmark. The GERG-2008 path has the strongest component coverage, but it still requires PhaseXpert to build another substantial equilibrium and continuation layer around the EOS library.

## Benchmark Outcome

The deterministic JSON report records all required primary and additional cases, including pure CO2, 97/3 CO2/N2, 90/10 CO2/N2, near-pure CO2/N2, ppm N2 in CO2, and three multicomponent CO2-rich mixtures. Because the public native API and model-data review reached a stop condition before a scientifically valid benchmark could be implemented, every valid composition and branch reports:

| Metric | Value |
| --- | --- |
| Attempted points | 0 |
| Converged points | 0 |
| Accepted points | 0 |
| Continuous coverage | none |
| Pressure-error statistics | unavailable because there is no genuine continuous accepted boundary interval |
| Lowest continuous 90/10 bubble temperature | unavailable |
| Pure-CO2 endpoint gap improvement | unavailable |
| Equilibrium residuals | not evaluated |
| Critical-region behaviour | not evaluated |
| Detached segments | none reported because no boundary segments were accepted |

Invalid, duplicate, unsupported, negative, non-finite, non-normalized, empty, and boundary-pinned inputs are rejected before teqp invocation. Safely normalizable input is explicitly marked as requiring caller normalization and is not silently normalized.

## Gate Decision

The desktop scientific gate fails before numerical benchmarking because no single teqp model was shown to provide complete open PhaseXpert model data plus a bounded, public native, multicomponent bubble/dew envelope path without substantial PhaseXpert-owned solver development. The macOS native C++ build is architecturally encouraging, but the full native/offline architecture remains unproven for iOS because a stable narrow C bridge, binary footprint, thread-safety contract, symbol-isolation plan, and cross-compilation result were not established.

Required classification: teqp requires excessive PhaseXpert-owned solver development.

No iOS XCFramework packaging, production provider work, UI work, simulator validation, or physical-device validation is justified by this milestone.
