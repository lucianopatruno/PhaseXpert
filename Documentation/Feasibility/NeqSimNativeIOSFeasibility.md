# NeqSim Native iOS Feasibility Spike

Branch: `agent/neqsim-native-ios-feasibility-clean`

Starting PhaseXpert commit: `237d2286f10462a4014c64931db59bce23173a2f`

Status: stopped at feasibility gate. No iOS NeqSim binary was produced or linked.

## Pinned Sources

| Source | Version or Ref | Commit | Notes |
| --- | --- | --- | --- |
| NeqSim | `v3.16.0` | `3af7b560525b57f2d3da2c803a08e2b41a8d7f5a` | Baseline used by the current remote NeqSim provider work. |
| NeqSim | `master` | `13a6f31ee4ce3d5394291edc2179ffb6993eb130` | Current repository head inspected for provenance. |
| neqsim-native | `v3.0.0` / `main` | `38bcbb043e51f731c89744e566cba122fcc2d00c` | Latest official native wrapper release inspected. |
| neqsim-native Maven dependency | `com.equinor.neqsim:neqsim:3.14.0` | Not source-pinned in `pom.xml` | Official native wrapper does not currently pin the same NeqSim release as the remote provider work. |

Official repositories inspected:

- https://github.com/equinor/neqsim
- https://github.com/equinor/neqsim-native
- https://www.graalvm.org/jdk25/reference-manual/native-image/

## Gate Findings

| Requirement | Finding | Result |
| --- | --- | --- |
| GraalVM Native Image must target `ios-arm64` and simulator architectures | Official GraalVM Native Image documentation lists Linux, macOS, and Windows as available platforms. It does not document iOS or iOS simulator targets. | Blocked |
| neqsim-native must provide an iOS build path | Official `neqsim-native` release assets are Linux x64, Windows x64, Windows x86 stub, and macOS arm64. Build profiles are Linux, Windows, and macOS only. | Blocked |
| App Store compatible XCFramework must be produced from official supported inputs | No official iOS native-image target, iOS build profile, simulator slice, or static iOS runtime path was found. A macOS dylib cannot be treated as an iOS binary. | Blocked |
| Minimal pure-CO2 C entry points | `neqsim-native` exposes C entry points for its current water-dew-point API. A minimal pure-CO2 TP flash and density entry point would require native-wrapper source work after an iOS toolchain exists. | Not attempted after gate |
| No unsupported JVM, JIT, subprocess, dynamic-code-loading, Python, or network dependency | No iOS binary was generated, so dependency inspection could not be performed. | Pending upstream iOS toolchain |
| iPhone 17 simulator and physical-iPhone execution | No iOS binary was generated, so runtime tests could not be performed. | Not attempted after gate |
| Size, first-call latency, subsequent-call latency, and peak memory | No app integration was created. | Not measured |

## Technical Blocker

The feasibility gate is blocked because the official GraalVM Native Image and `neqsim-native` documentation, release artifacts, Maven profiles, and CI workflows do not provide a verified iOS or iOS-simulator build target. Without an official Apple-iOS-targeting Native Image toolchain and platform-specific static runtime support, PhaseXpert cannot produce a correct App Store-compatible NeqSim XCFramework for `ios-arm64` plus simulator slices.

This is a technical packaging/toolchain blocker, not a scientific conclusion about NeqSim.

## Work Not Performed

No Swift/C bridge was added, no provider code was changed, no NeqSim equations were ported or reimplemented in Swift, and the existing remote NeqSim provider work was not removed or weakened. No generated NeqSim binaries were committed.

## Licences

NeqSim and `neqsim-native` are published by Equinor under Apache-2.0 licensing in the inspected official repositories. If a future iOS-native binary becomes feasible, PhaseXpert must preserve the required Apache-2.0 notices and re-check bundled transitive dependencies before distribution.

## Proposed Second Milestone If Upstream iOS Support Appears

1. Pin an official NeqSim and `neqsim-native` release that explicitly supports iOS and iOS simulator builds.
2. Add minimal C entry points for pure-CO2 TP flash and density, preferably upstream or in a clearly documented fork.
3. Build static or App Store-compatible dynamic device and simulator slices and package them as an XCFramework.
4. Inspect every slice and linked product for JVM, JIT, dynamic-code-loading, subprocess, Python, network, and unsupported dynamic runtime dependencies.
5. Add a minimal Swift bridge and run pure-CO2 TP flash at 150 bar(a), 20 C on both iPhone 17 simulator and physical iPhone.
6. Compare integration results and provenance against the NeqSim 3.16.0 remote provider work without claiming scientific validation.
7. Measure XCFramework size, final app-size increase, first-call latency, subsequent-call latency, and peak memory.
8. Only after the pure-CO2 gate passes, evaluate CO2/N2 state properties and phase envelopes with explicit parity tolerances against a reference service.
