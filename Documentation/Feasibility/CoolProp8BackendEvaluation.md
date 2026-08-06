# CoolProp 8 Backend Evaluation

Branch: `agent/coolprop8-backend-feasibility`

Base commit: `f75052489baf8efb798fffcb77137b730d4ceaa4`

Status: macOS scientific gate failed. Do not build an iOS XCFramework or modify the production provider from this milestone.

## Repository Reconciliation

PR #28 was left untouched. Its branch and remote HEAD were confirmed as `agent/native-srk-phase-envelope-prototype` at `6537f82a5d894dc172270ff5d1cb153d405c30e1`, with draft PR `https://github.com/lucianopatruno/PhaseXpert/pull/28`.

The accepted `main` used for this branch is `origin/main` at `f75052489baf8efb798fffcb77137b730d4ceaa4`.

Protected unrelated local artifacts observed before this work:

- unstaged `PhaseXpert.xcodeproj/project.pbxproj` deployment/signing/version diff;
- untracked `Services/`;
- untracked `Vendor/ThermoPack/`;
- ignored `.DS_Store`, `.pytest_cache/`, Xcode user data, SwiftPM build/cache state and `Vendor/CoolProp/*` generated artifacts.

Those artifacts were not staged, deleted, cleaned or intentionally modified.

## Existing CoolProp Baseline

Repository documentation and build scripts pin CoolProp tag `v8.0.0`. The ignored local file `Vendor/CoolProp/COOLPROP-REVISION.txt` records `ae81610e7d23efc57f9d051c8e70a4d66e87537f`. `git ls-remote --tags https://github.com/CoolProp/CoolProp.git refs/tags/v8.0.0 refs/tags/v8.0.0^{}` resolved tag object `f39e663f5573f6a142c50d425f2a46b4c9dc5dcd` and peeled commit `ae81610e7d23efc57f9d051c8e70a4d66e87537f`, so the current XCFramework source revision is proven by local metadata and upstream tag resolution.

The local XCFramework contains `ios-arm64` and `ios-arm64_x86_64-simulator` static-library slices. It does not contain a macOS slice. The bridge source fingerprint file records `53d4d14e8853e87da67e3f1918b4221595f6aae85903a6c2452d59858617edae`, and `Scripts/ensure-coolprop-xcframework.sh` reported the XCFramework current, so this milestone did not rebuild it.

The production Swift package links `PhaseXpertCoolPropBridge.xcframework` only for iOS when the ignored artifact exists. The macOS Swift package tests therefore exercise the provider through mock engines, not through the native CoolProp binary.

Production operation routing:

- pure CO2 state: HEOS `AbstractState("HEOS", "CarbonDioxide")` with `PT_INPUTS`;
- pure CO2 saturation boundary: HEOS `PropsSI("P", "T", temperatureK, "Q", 0, "HEOS::CarbonDioxide")`;
- dry CO2-rich state: HEOS `PropsSI("Dmass", "P", pressurePa, "T", temperatureK, fluidString)`;
- dry mixture phase envelope: HEOS `AbstractState::build_phase_envelope("none")` after `set_mole_fractions`;
- cubic SRK/PR are not used by the production provider.

The prior hang risk is inside the monolithic native `build_phase_envelope()` call. PhaseXpert currently mitigates that only in the generated CoolProp source by applying `Native/CoolPropBridge/patches/apply_phase_envelope_iteration_cap.py`, which caps provider continuation at 256 successful steps. Swift launches the native call in a detached task and checks cancellation before and after the call, but cannot interrupt the C++ routine while it is running. No evidence points to wrapper conversion, PhaseXpert post-processing or repeated main-actor work as the source of the mixture continuation hang.

Supported production dry components are CO2, N2, O2, Ar, CH4 and H2 with total impurity in `(0, 10]` mol%. PhaseXpert does not call `apply_simple_mixing_rule`, does not overwrite binary interaction parameters and uses only interaction data shipped by the pinned CoolProp release. Other app components such as H2O, CO, H2S, He, ethane and propane remain unsupported by the CoolProp provider.

## Benchmark Harness

The benchmark source is `Scripts/CoolProp8BackendBenchmark.cpp`; the deterministic runner is `Scripts/coolprop8_benchmark.py`; the shell entry point is `Scripts/run-coolprop8-backend-benchmark.sh`. The runner clones official CoolProp `v8.0.0`, verifies commit `ae81610e7d23efc57f9d051c8e70a4d66e87537f`, builds a macOS static library under `/tmp/phasexpert-coolprop8-benchmark`, compiles the C++ harness and runs one backend/case/API operation per subprocess.

Each subprocess is bounded by a 12.0 second process deadline. This is the documented no-hang strategy for non-interruptible CoolProp calls in the benchmark. It is suitable as a feasibility isolation strategy, but it is not cooperative cancellation inside CoolProp. The C++ API exposes no cancellation hook inside `build_phase_envelope()`, PT flash or `all_critical_points()`.

The benchmark evaluates:

- HEOS, SRK and PR `build_phase_envelope()`;
- HEOS, SRK and PR blind `PT_INPUTS` flashes using CoolProp's default `MIXTURE_STABILITY_ALGORITHM`, documented in the pinned source as Michelsen by default;
- HEOS, SRK and PR `all_critical_points()`;
- invalid, non-normalized, negative, non-finite, unsupported-component and current out-of-domain impurity inputs, all rejected before CoolProp.

Reference comparison uses only `Documentation/Feasibility/LocalPhaseDiagramNeqSimReferenceDataset.json`, which contains parity data for pure CO2, 97/3 CO2/N2 and 90/10 CO2/N2. The multicomponent, ppm and near-pure cases therefore have completeness diagnostics but no repository reference parity metrics.

## Results

The normalized result file is `Documentation/Feasibility/CoolProp8ComparisonResults.json`. It was generated twice and compared byte-for-byte with `cmp`; the normalized JSON matched exactly. Timing is stored outside the deterministic report in `/tmp/phasexpert-coolprop8-timing-results.json`.

Full benchmark timing on the final run: 117 subprocess operations, 44.865 seconds summed subprocess elapsed time, 0 timeouts. Build-envelope operations summed 5.129 seconds with maximum 0.542 seconds; PT-flash operations summed 8.500 seconds with maximum 1.728 seconds; critical-point operations summed 31.237 seconds with maximum 6.449 seconds. `/usr/bin/time -l` could not report peak RSS in this sandbox because `sysctl kern.clockrate` was denied, so peak memory is unavailable.

Main phase-envelope findings:

| Backend | Case | Status | Points | Complete | Closed | Bubble K Range | Bubble Gaps | Bubble Max Error | Dew K Range | Dew Gaps | Dew Max Error |
| --- | --- | --- | ---: | --- | --- | --- | ---: | ---: | --- | ---: | ---: |
| HEOS | pure CO2 | returned | 80 | false | false | 216.592-304.127 | 0 | 3.918% | 216.592-304.127 | 0 | 3.918% |
| HEOS | 97/3 CO2/N2 | returned | 51 | false | false | 292.081-302.007 | 1 | 2.570% | 120.149-302.169 | 16 | 19.882% |
| HEOS | 90/10 CO2/N2 | returned | 106 | false | false | 161.021-295.088 | 8 | 3830.956% | 119.729-296.423 | 10 | 8068028.749% |
| SRK | pure CO2 | returned | 69 | false | false | 7.798-304.127 | 34 | 3.904% | 77.981-296.329 | 28 | 3.904% |
| SRK | 97/3 CO2/N2 | threw | 0 | n/a | n/a | n/a | 0 | n/a | n/a | 0 | n/a |
| SRK | 90/10 CO2/N2 | returned | 74 | false | false | 134.301-296.657 | 11 | 62.898% | 118.058-297.455 | 14 | 2.033% |
| PR | pure CO2 | returned | 68 | false | false | 15.596-304.127 | 34 | 5.568% | 77.981-296.329 | 28 | 5.568% |
| PR | 97/3 CO2/N2 | threw | 0 | n/a | n/a | n/a | 0 | n/a | n/a | 0 | n/a |
| PR | 90/10 CO2/N2 | returned | 70 | false | false | 128.745-296.490 | 13 | 7.429% | 116.896-297.152 | 15 | 3.313% |

Pure-CO2 endpoint gap against explicit stable critical-point output was approximately 0.001 K for all three backends, so that isolated criterion improved the previous approximately 14.096 K gap. The lowest continuous 90/10 bubble temperatures were HEOS 161.021 K, SRK 134.301 K and PR 128.745 K; SRK and PR reach below 139.987 K, but with discontinuous branches and pressure errors above the gate.

Representative multicomponent cases returned points for all backends, but every returned envelope was incomplete/open and had many branch gaps. HEOS dew branches also ran to very high temperatures for multicomponent cases, up to 648.502 K, 671.134 K and 714.094 K, outside PhaseXpert's intended transport domain. No multicomponent parity errors were computed because the repository has no NeqSim multicomponent envelope reference fixture.

Trace and near-pure impurity envelope cases (`99.9999/0.0001` and `99.9/0.1` mol% CO2/N2) threw for HEOS, SRK and PR with `Unable to calculate at least 4 points in phase envelope; quitting`.

PT flash completed without timeout. For the three reference compositions, HEOS converged 20/20 mixture samples and 16/20 pure-CO2 samples; SRK and PR converged 20/20 for all three. These are interior state classifications, not boundary points, and the runner does not relabel them as bubble or dew data.

Critical-point output was mixed. HEOS returned stable critical points for pure CO2 and 97/3 CO2/N2 and one stable plus one unstable point for 90/10 CO2/N2. SRK returned pure CO2 and 90/10 CO2/N2 critical points, but zero for 97/3 CO2/N2. PR returned only pure CO2 among the three reference cases.

## Gate Decision

No backend passes the macOS scientific gate. HEOS fails pressure parity and branch continuity for the CO2/N2 mixtures and does not improve the 90/10 low-temperature bubble limitation. SRK and PR improve the 90/10 low-temperature reach but fail continuity, 97/3 envelope construction and pressure parity. PT flash is useful diagnostic evidence for CoolProp 8's local state classification path, but it does not produce genuine continuous bubble/dew boundaries and is not accepted as a phase-envelope substitute.

Because no backend passes, iOS packaging and production integration are not justified in this milestone.
