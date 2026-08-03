#!/usr/bin/env bash
set -euo pipefail

mode="${1:-fast}"
case "${mode}" in
    fast|standard|release) ;;
    *)
        echo "Usage: bash Scripts/validate-phase-xpert.sh [fast|standard|release]" >&2
        exit 2
        ;;
esac

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
derived_data="${PHASEXPERT_DERIVED_DATA:-/tmp/PhaseXpertDerivedData}"
test_destination="${PHASEXPERT_TEST_DESTINATION:-platform=iOS Simulator,name=iPhone 17,OS=latest}"

cd "${project_root}"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
if [[ -d /opt/homebrew/bin ]]; then
    export PATH="/opt/homebrew/bin:${PATH}"
fi

run_core_tests() {
    swift test --package-path PhaseXpertCore --disable-sandbox
}

run_diff_check() {
    git diff --check
}

if [[ "${mode}" == fast ]]; then
    run_core_tests
    run_diff_check
    echo "PhaseXpert fast validation passed."
    exit 0
fi

bash Scripts/ensure-coolprop-xcframework.sh
if [[ "${PHASEXPERT_REQUIRE_THERMOPACK:-0}" == 1 \
    || -d Vendor/ThermoPack/PhaseXpertThermoPackBridge.xcframework ]]; then
    bash Scripts/ensure-thermopack-xcframework.sh
else
    echo "ThermoPack native validation skipped; set PHASEXPERT_REQUIRE_THERMOPACK=1 to require it."
fi
run_core_tests

xcodebuild     -project PhaseXpert.xcodeproj     -scheme PhaseXpert     -destination "generic/platform=iOS Simulator"     -derivedDataPath "${derived_data}"     CODE_SIGNING_ALLOWED=NO     build

xcodebuild     -project PhaseXpert.xcodeproj     -scheme PhaseXpert     -destination "${test_destination}"     -derivedDataPath "${derived_data}"     -parallel-testing-enabled NO     -maximum-parallel-testing-workers 1     CODE_SIGNING_ALLOWED=NO     -only-testing:PhaseXpertTests     test

if [[ "${mode}" == release ]]; then
    xcodebuild         -project PhaseXpert.xcodeproj         -scheme PhaseXpert         -destination "${test_destination}"         -derivedDataPath "${derived_data}"         -parallel-testing-enabled NO         -maximum-parallel-testing-workers 1         CODE_SIGNING_ALLOWED=NO         -only-testing:PhaseXpertUITests         test
fi

run_diff_check
echo "PhaseXpert ${mode} validation passed."
