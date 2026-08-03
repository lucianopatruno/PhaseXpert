# Generated ThermoPack dependency

`PhaseXpertThermoPackBridge.xcframework` is generated locally and ignored by Git.

Pinned source:

- release: `v2.2.4`
- commit: `ca75d8e095e8b951616897efe1bca9b8c3badda7`
- licence: Apache License 2.0
- EOS: Peng–Robinson
- alpha: Classic
- mixing: Classic van der Waals one-fluid
- interaction record: `binaries/PR_kij.json`, `vdW-18`, CO₂/N₂, `ref=Default`
- bridge capability version: `1.0.0`

Build with `Scripts/build-thermopack-xcframework.sh`. The build requires an
LLVM Flang toolchain capable of Apple iOS targets and explicitly supplied static
Fortran runtime archives. It creates `ios-arm64` and
`ios-arm64_x86_64-simulator` slices and rejects identified dynamic
Fortran/OpenMP runtime dependencies.

The build workflow changes build mechanics only. It must never change
ThermoPack equations, component records, interaction data, or solver algorithms.
Successful compilation and numerical smoke tests are pending Xcode validation.