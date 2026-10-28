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

# teqp stays in the repository for future work but is not part of the
# distributed app. Fail loudly if it gets linked or registered by accident.
check_teqp_not_linked() {
    if grep -qi teqp PhaseXpert.xcodeproj/project.pbxproj; then
        echo "teqp is referenced by the app project; it must not be shipped." >&2
        exit 1
    fi
    if grep -qi teqp PhaseXpertCore/Package.swift; then
        echo "teqp is referenced by PhaseXpertCore/Package.swift; it must not be shipped." >&2
        exit 1
    fi
}

check_teqp_not_in_product() {
    local app
    app="$(find "${derived_data}/Build/Products" -maxdepth 2 -name PhaseXpert.app -type d | head -1)"
    if [[ -z "${app}" ]]; then
        echo "Built PhaseXpert.app not found for the teqp check." >&2
        exit 1
    fi
    if find "${app}" -iname '*teqp*' | grep -q .; then
        echo "A teqp file was found inside the built app bundle." >&2
        exit 1
    fi
    # Scan every file: the native code lives in the PhaseXpertCore package framework.
    if find "${app}" -type f -print0 | xargs -0 grep -la 'px_teqp_' >/dev/null 2>&1; then
        echo "teqp bridge symbols were found in the built app." >&2
        exit 1
    fi
    # Positive control: if CoolProp symbols are not visible either, this scan is blind.
    if ! find "${app}" -type f -print0 | xargs -0 grep -la 'px_coolprop_' >/dev/null 2>&1; then
        echo "The teqp check could not see the CoolProp symbols, so its result is not trustworthy." >&2
        exit 1
    fi
}

check_teqp_not_linked

if [[ "${mode}" == fast ]]; then
    run_core_tests
    run_diff_check
    echo "PhaseXpert fast validation passed."
    exit 0
fi

bash Scripts/ensure-coolprop-xcframework.sh
run_core_tests

xcodebuild     -project PhaseXpert.xcodeproj     -scheme PhaseXpert     -destination "generic/platform=iOS Simulator"     -derivedDataPath "${derived_data}"     CODE_SIGNING_ALLOWED=NO     build

check_teqp_not_in_product

xcodebuild     -project PhaseXpert.xcodeproj     -scheme PhaseXpert     -destination "${test_destination}"     -derivedDataPath "${derived_data}"     -parallel-testing-enabled NO     -maximum-parallel-testing-workers 1     CODE_SIGNING_ALLOWED=NO     -only-testing:PhaseXpertTests     test

if [[ "${mode}" == release ]]; then
    xcodebuild         -project PhaseXpert.xcodeproj         -scheme PhaseXpert         -destination "${test_destination}"         -derivedDataPath "${derived_data}"         -parallel-testing-enabled NO         -maximum-parallel-testing-workers 1         CODE_SIGNING_ALLOWED=NO         -only-testing:PhaseXpertUITests         test
fi

run_diff_check
echo "PhaseXpert ${mode} validation passed."
