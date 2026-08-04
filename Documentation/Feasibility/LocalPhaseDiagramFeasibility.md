# Local Phase-Diagram Feasibility Investigation

Branch: `agent/local-phase-diagram-feasibility`

Base commit: `cc0fa511bfea97e37d9f0f2e30593e61edfc65c7`

Status: research and decision record. No production provider default was changed and no experimental runtime code was merged.

## Scope

PhaseXpert needs a local, offline phase-diagram route for pure CO2 and CO2/N2 mixtures that can run on physical iPhones without Python, Java, localhost, or a remote service at runtime. This document compares credible routes after PR25 established only that the current GraalVM/neqsim-native path has no verified iOS target.

The first scientific gate remains:

- pure CO2;
- 97/3 mol% CO2/N2;
- 90/10 mol% CO2/N2;
- bubble and dew boundaries over the useful PhaseXpert pressure/temperature domain;
- explicit endpoint, critical-region, failed-convergence and single-phase handling;
- deterministic termination with bounded iteration and elapsed time;
- no fabricated points across unconverged regions.

Successful numerical execution is software evidence only. It is not experimental validation.

## Sources and Versions Inspected

| Source | Version or Commit | Licence Finding | Relevant Finding |
| --- | --- | --- | --- |
| PhaseXpert merged main | `cc0fa511bfea97e37d9f0f2e30593e61edfc65c7` | Project licence unchanged | Existing CoolProp bridge is already packaged for `ios-arm64` and `ios-arm64_x86_64-simulator`. |
| CoolProp | generated revision `ae81610e7d23efc57f9d051c8e70a4d66e87537f`; upstream `v6.8.0` tag `442e8bd29867b11b9a5d8b6bbba7b7dcf35d2a03`; upstream `master` `e8fff5694e8fba11d7cbd9a80789a3b194ebbe59` | MIT-style flexible licensing documented upstream | Official API exposes `AbstractState::build_phase_envelope()` for mixtures, but PhaseXpert has observed and patched unbounded continuation risk. |
| ThermoPack | upstream `main` `d68c794c7342bfc6938eb424a1fbb88b7780b738`; `v2.2.1` tag `c018592e64cdb16aa21119f4a7e2625cfed9fb99` | Apache-2.0 in inspected source | ThermoPack has cubic EOS, CO2/N2 examples, phase-envelope APIs and critical solvers, but the Fortran/iOS toolchain is not currently established. |
| NeqSim reference service | `neqsim_version=3.16.0`, source commit `3af7b560525b57f2d3da2c803a08e2b41a8d7f5a`, `SystemSrkEos`, `classic`, `INTER.csv:7452:CO2-nitrogen:Classic` | Remote-service PR provenance | Health endpoint was reachable locally, but state/envelope calls failed because the running development service could not import the NeqSim Python bridge. |
| GraalVM / neqsim-native | See `NeqSimNativeIOSFeasibility.md` | NeqSim Apache-2.0, neqsim-native MIT in inspected source | No verified iOS Native Image target or iOS XCFramework build path. |

## Candidate Ranking

| Rank | Route | Scientific Suitability | iOS Feasibility | Offline | Licence/Redistribution | Reliability Risk | Size/Runtime Risk | Maintenance Cost | Decision |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Repair/replace CoolProp envelope with bounded local bubble/dew tracing | Medium-high for HEOS-backed CO2-rich mixtures, subject to parity tests | High: current bridge already builds and links on iOS | Yes | Favorable | Medium: must avoid monolithic unbounded calls and validate branch identity | Low-medium | Medium | Recommended first prototype |
| 2 | ThermoPack static iOS library | High if Fortran build and parameters are pinned | Unknown/blocking today: no iOS-capable Fortran runtime path confirmed | Yes | Apache-2.0, but dependency redistribution must be audited | Medium once built | Medium-high because Fortran runtime/BLAS/OpenMP may enlarge app | High | Continue as toolchain spike, not first implementation |
| 3 | Small native cubic EOS engine | Medium if parameter provenance and VLE algorithms are pinned; risky near critical regions | High if implemented in Swift/C/C++/Rust | Yes | Depends on copied parameters/algorithm sources | High until stability, fugacity and continuation are proven | Low | High | Viable only after a separate scientific-model specification |
| 4 | Port minimum open-source phase-equilibrium algorithm | Potentially high if model is preserved | Medium | Yes | Must resolve source-specific attribution and derivative-work obligations | Medium-high | Medium | High | Investigate after choosing source/model; do not call it NeqSim unless model is preserved |
| 5 | Precomputed tables or surrogates | Low as sole solution for arbitrary compositions | High | Yes | Depends on generator and data | High outside tabulated domain | Low-medium storage/runtime | Medium | Optional acceleration only, not core solver |
| 6 | NeqSim Native via GraalVM | High if feasible | Blocked by missing verified iOS target | Yes in theory | Apache-2.0/MIT combination | Unknown | Unknown | High | Closed by PR25 until upstream iOS support exists |

## ThermoPack Static iOS Feasibility

ThermoPack is technically attractive because it includes cubic EOS models, CO2/N2 examples, phase-envelope APIs and critical-point solvers. The inspected source documents GNU Fortran or Intel Fortran plus LAPACK and BLAS dependencies, and the CMake file is Fortran-first. On Apple, the upstream CMake sets `/opt/homebrew/bin/gfortran`, macOS arm64 architecture flags, `-fPIC`, and `-fopenmp`.

A minimal local cross-compile probe was attempted with Homebrew GCC 14.1.0_2:

```text
/opt/homebrew/bin/gfortran -c probe.f90 -arch arm64 -isysroot <iPhoneOS.sdk> -miphoneos-version-min=17.0
gfortran: error: unrecognized command-line option '-miphoneos-version-min=17.0'
Target: aarch64-apple-darwin23

/opt/homebrew/bin/gfortran -c probe.f90 -arch x86_64 -isysroot <iPhoneSimulator.sdk> -mios-simulator-version-min=17.0
gfortran: warning: this compiler does not support x86 ('-arch' option ignored)
gfortran: error: unrecognized command-line option '-mios-simulator-version-min=17.0'
```

This establishes that the available Homebrew `gfortran` is not an iOS cross-compiler. It does not prove ThermoPack is impossible on iOS. A second ThermoPack milestone would need an Apple-targeting Fortran compiler plus platform-specific static Fortran runtime archives for device arm64 and simulator arm64/x86_64, with `libgfortran`, `libquadmath`, OpenMP and BLAS/LAPACK either eliminated or statically and lawfully linked.

## CoolProp Envelope Repair Route

The existing CoolProp bridge is already native, offline and packaged for iOS. State-property calls are fast and reliable because they are direct bounded state updates. Mixture phase-envelope generation is less reliable because it currently calls CoolProp's monolithic `AbstractState::build_phase_envelope("none")`. PhaseXpert added a downstream patch to CoolProp's continuation loop so the native call cannot iterate indefinitely, starts at 0.8 bar(a), retains only finite provider points, and reports `is_complete`/`is_closed` separately.

The remaining risk is that a monolithic provider continuation still owns the native control flow until it returns. The best first local prototype is therefore a PhaseXpert-owned bounded bubble/dew tracer that calls only smaller CoolProp equilibrium operations per step, checks cancellation between steps, enforces point/iteration/time limits, and records each failed step as an explicit gap. The prototype must preserve provider-returned finite points only and must not infer branch identity from chart shape alone.

Required prototype checks:

- pure CO2 saturation remains calculated from HEOS saturation calls;
- 97/3 and 90/10 CO2/N2 return at least two finite bubble and dew points or explicit unavailable status;
- no single native call can block UI progress indefinitely;
- timeout/cancellation happens between bounded provider calls;
- parity against NeqSim 3.16.0 is measured before acceptance;
- max, mean and percentile pressure and temperature deviations are reported separately.

## Native Cubic EOS Route

A small native EOS engine could be implemented in Swift, C, C++ or Rust and packaged cleanly for iOS. The scientific gate is harder than the build gate. A credible implementation must pin:

- exact EOS, initially PR76, PR78 or SRK;
- alpha function;
- mixing rule;
- pure-component critical properties and acentric factors;
- CO2/N2 binary interaction parameter source;
- fugacity coefficient formulation;
- stability analysis method;
- bubble/dew solver and continuation method;
- critical-region and failed-convergence behavior.

This route must not use generic estimated binary interaction parameters without recording that they are estimates and without bounding their domain. It should not become the first implementation milestone unless CoolProp tracing fails and ThermoPack remains blocked.

## Ported Algorithm Route

Porting a minimum phase-equilibrium algorithm is viable only after choosing an authoritative model and resolving licence obligations. CoolProp code is MIT-compatible, ThermoPack is Apache-2.0, NeqSim is Apache-2.0, and neqsim-native is MIT in the inspected source. Copying code from any project would require preserving notices and clearly naming the resulting model. A partial port must not be marketed as NeqSim unless it preserves NeqSim's model configuration, parameter provenance and numerical behavior.

## Precomputed or Hybrid Route

Local cached tables or surrogates can reduce latency after a trusted solver exists, but they are not acceptable as the sole arbitrary-composition phase-diagram solution. Any table must store domain bounds, generator version, source provider, interpolation method, error estimates and out-of-domain rejection behavior. Silent extrapolation is not allowed.

## Reference Dataset Attempt

The intended primary parity reference is the NeqSim 3.16.0 service. On this branch, a local development service was reachable at `http://127.0.0.1:8080/v1/health` and reported:

- provider ID: `neqsim-remote-srk-classic`;
- NeqSim version: `3.16.0`;
- source commit: `3af7b560525b57f2d3da2c803a08e2b41a8d7f5a`;
- EOS: `SystemSrkEos`;
- mixing rule: `classic`;
- interaction data: `neqsim-v3.16.0:src/main/resources/data/INTER.csv:7452:CO2-nitrogen:Classic`.

State and phase-envelope calls for pure CO2, 97/3 CO2/N2 and 90/10 CO2/N2 all returned structured HTTP 422 responses with `message: "NeqSim Python bridge is not importable"`. Therefore a numeric reference dataset was not generated in this pass. The machine-readable attempt is stored in `LocalPhaseDiagramReferenceDatasetAttempt.json` so future work can distinguish missing reference data from accepted parity data.

## Recommended Local Architecture

The next implementation milestone should prototype a local CoolProp bounded bubble/dew tracer in a separate experimental provider or hidden validation mode, not as a production default. It should keep the existing remote NeqSim provider as a reference source when configured. It must not fall back between providers, interpolate missing scientific points, or change production defaults.

The ThermoPack static-iOS route should continue in parallel only if an iOS-capable Fortran compiler/runtime stack can be established and redistributed. A native cubic EOS should be treated as a separate scientific-model project with formal parameter provenance and independently reviewed numerical algorithms.

## Pending Validation

- Generate a successful NeqSim 3.16.0 numeric reference dataset once the local service imports the NeqSim Python bridge.
- Define parity tolerances before evaluating any local prototype.
- Run any accepted prototype on iPhone 17 simulator and physical iPhone.
- Measure binary size, app-size increase, first-call latency, subsequent-call latency and peak memory.
- Cross-check selected cases against a second authoritative implementation or published data.
- Keep visual comparison secondary to numerical pressure/temperature error metrics.
