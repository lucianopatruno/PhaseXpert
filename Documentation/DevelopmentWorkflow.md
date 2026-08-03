# Development validation workflow

PhaseXpert uses staged validation so compiler fixes do not repeatedly trigger the slowest UI and physical-device checks.

## Prerequisites

- macOS with Xcode 26 selected through `xcode-select`
- Homebrew CMake available at `/opt/homebrew/bin/cmake` or on `PATH`
- an installed iPhone 17 simulator, or an explicit destination override
- Git and the locally generated CoolProp source cache used by the existing build script
- for NeqSim service work: Python 3.12 and Docker; the iOS app remains usable
  without a NeqSim endpoint, but the remote provider is unavailable

Run these commands in a normal macOS Terminal. A restricted agent shell may be unable to write SwiftPM diagnostics under `~/Library/Caches`; that is a sandbox limitation and should not be worked around by changing permissions.

## Validation tiers

Fast checks core logic and whitespace only:

```sh
bash Scripts/validate-phase-xpert.sh fast
```

Standard ensures the CoolProp binary matches the tracked bridge, runs core tests, builds the simulator app and runs app unit tests serially:

```sh
bash Scripts/validate-phase-xpert.sh standard
```

Release adds serial UI tests:

```sh
bash Scripts/validate-phase-xpert.sh release
```

The default simulator is iPhone 17 on the latest installed iOS runtime. Override it when needed:

```sh
PHASEXPERT_TEST_DESTINATION="platform=iOS Simulator,name=iPhone 17 Pro,OS=latest" \
  bash Scripts/validate-phase-xpert.sh release
```

## CoolProp rebuild detection

`Scripts/ensure-coolprop-xcframework.sh` fingerprints the bridge header, bridge implementation, build script and pinned CoolProp version. It skips a current binary and rebuilds only when the binary is absent or the fingerprint changes. A stale XCFramework is moved to a timestamped backup under `/tmp` before rebuilding.

The generated XCFramework, licence, revision and fingerprint remain ignored by Git. Binary generation does not scientifically validate CoolProp results.

## NeqSim service validation

The NeqSim service is intentionally outside the iOS app in
`Services/NeqSimProvider`. Use its README for local unit tests, smoke matrix
and Docker build. Set `PHASEXPERT_NEQSIM_ENDPOINT` only for development or a
production HTTPS deployment. Do not commit endpoints or credentials.

## Manual checks

Physical-iPhone installation, accessibility inspection, visual review, PNG/PDF inspection and scientific acceptance remain manual release gates. Automated success must never be reported as scientific validation.
