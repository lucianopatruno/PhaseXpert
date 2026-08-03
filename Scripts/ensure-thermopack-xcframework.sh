#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
framework="${project_root}/Vendor/ThermoPack/PhaseXpertThermoPackBridge.xcframework"
stamp="${project_root}/Vendor/ThermoPack/BRIDGE-SOURCE-SHA256.txt"
expected="$({
    printf 'ThermoPack=%s@%s\n' \
        "v2.2.4" "ca75d8e095e8b951616897efe1bca9b8c3badda7"
    shasum -a 256 \
        "${project_root}/Native/ThermoPackBridge/include/PhaseXpertThermoPackBridge.h" \
        "${project_root}/Native/ThermoPackBridge/src/PhaseXpertThermoPackBridge.cpp" \
        "${project_root}/Native/ThermoPackBridge/smoke/thermopack_smoke.cpp" \
        "${project_root}/Native/ThermoPackBridge/patches/prepare_ios_static_build.py" \
        "${project_root}/Scripts/build-thermopack-xcframework.sh"
} | shasum -a 256 | awk '{print $1}')"

if [[ -d "${framework}" && -f "${stamp}" && "$(cat "${stamp}")" == "${expected}" ]]; then
    touch "${project_root}/PhaseXpertCore/Package.swift"
    echo "ThermoPack XCFramework is current; rebuild skipped."
    exit 0
fi

"${project_root}/Scripts/build-thermopack-xcframework.sh"