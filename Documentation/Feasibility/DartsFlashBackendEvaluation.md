# DARTS-flash Backend Feasibility

This milestone evaluates DARTS-flash as a local, offline, native phase-boundary candidate for PhaseXpert. It does not modify the production CoolProp provider, Swift UI, Xcode project, or any prior feasibility PR.

## Immutable Pin

- Repository: `https://gitlab.com/open-darts/darts-flash.git`
- Release: `v0.13.0`
- Commit: `acf1e12db4b82c779462a81d911ead0e254b963b`
- Licence: Apache-2.0
- Submodules inspected during the macOS compile probe:
  - Eigen: `e7248b26a1ed53fa030c5c459f7ea095dfd276ac`
  - pybind11: `f5fbe867d2d26e4a0a9177a51f6e568868ad3dc8`

The source tree is a C++17 CMake project with Python bindings. The upstream CMake configuration imports Eigen and pybind11 and calls `find_package(Python COMPONENTS Interpreter Development.Module REQUIRED)`, so Python development headers are a configure-time requirement in the unmodified build even when building the static `darts-flash` target.

## Native API Findings

DARTS-flash exposes native C++ PT flash, negative flash, PH/PS flash through `PXFlash`, stability and split routines, phase results, phase properties, fugacity-capable property calls, and cubic-EOS critical-point methods. `Flash::locate_phase_boundary` exists, but it requires two bracketing `FlashResults` states and is used by transition-temperature handling. I did not find a public turnkey fixed-composition PT bubble/dew envelope API that returns genuine consecutive bubble and dew boundaries.

Constructing PhaseXpert-quality PT bubble/dew curves from the available PT flash and phase-boundary primitives would require PhaseXpert to own bracketing, continuation, root and phase tracking, detached-segment rejection, branch classification, gap detection, timeout isolation, and acceptance logic. That is a stop condition for this milestone.

## Model And Parameter Findings

The relevant native model family found in the source is the Helmholtz-form cubic EOS implementation for PR and SRK using critical properties, acentric factors, and `kij` values. The bundled `dartsflash/components.py` table includes CO2, N2, H2, CH4 as `C1`, H2S, and H2O. It does not include O2, Ar, or CO, which are required PhaseXpert impurity candidates.

The table contains a CO2/N2 cubic-EOS `kij` value of `-0.0462`. The exact primary source, DOI, fitting dataset, temperature and pressure range, and sign-convention validation for that specific pair were not established from repository evidence. It therefore cannot be treated as a scientifically pinned PhaseXpert production parameter. Example mixtures also include manually supplied zero and nonzero `kij` values, but examples are not a sufficient provenance chain for PhaseXpert acceptance.

DARTS-flash therefore duplicates the already rejected cubic-EOS route unless a future task establishes a different validated model and a public envelope API.

## MacOS Compile Probe

A no-integration compile probe was run in `/tmp` against the pinned tag after initializing the Eigen and pybind11 submodules. It configured and built successfully with CMake 4.4.2 and AppleClang 21.0.0.21000101. Produced static archives were:

- `libdarts-flash.a`: 1.4 MB
- `libdarts-eos.a`: 2.1 MB
- `libglobal.a`: 368 KB

Warnings recorded:

- CMake policy CMP0152 warning in `thirdparty/thirdparty.cmake`.
- CMake author warning for the missing default `thirdparty/install` Eigen path before system Eigen was found.

This is macOS native-build evidence only. It does not prove iOS feasibility because the desktop scientific gate did not pass and Apple cross-compilation was not reached.

## Benchmark Outcome

The actual native scientific benchmark did not run. No boundary points were attempted, converged, accepted, interpolated, extrapolated, or fabricated. For pure CO2, 97/3 CO2/N2, and 90/10 CO2/N2, both bubble and dew branches have zero accepted points and no pressure-error statistics. No pure-CO2 endpoint gap improvement, no continuous 90/10 bubble extension below 139.987 K, no critical-region result, no equilibrium residual, and no multicomponent boundary result were produced.

The normalized JSON report is deterministic and records the blocked benchmark explicitly. Timing fields are limited to the macOS compile probe and are not used as scientific evidence.

## Classification

DARTS-flash requires excessive PhaseXpert-owned solver development.

The scientific gate fails. The minimal iOS compilation gate was not reached and is not justified by this milestone.
