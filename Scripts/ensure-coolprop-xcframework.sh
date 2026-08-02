#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
framework_path="${project_root}/Vendor/CoolProp/PhaseXpertCoolPropBridge.xcframework"
stamp_path="${project_root}/Vendor/CoolProp/BRIDGE-SOURCE-SHA256.txt"
bridge_header="${project_root}/Native/CoolPropBridge/include/PhaseXpertCoolPropBridge.h"
bridge_source="${project_root}/Native/CoolPropBridge/src/PhaseXpertCoolPropBridge.cpp"
build_script="${project_root}/Scripts/build-coolprop-xcframework.sh"
coolprop_patch_script="${project_root}/Native/CoolPropBridge/patches/apply_phase_envelope_iteration_cap.py"
coolprop_version="${COOLPROP_VERSION:-v8.0.0}"
package_manifest="${project_root}/PhaseXpertCore/Package.swift"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "CoolProp XCFramework generation requires macOS." >&2
    exit 1
fi

if ! command -v cmake >/dev/null 2>&1 && [[ -x /opt/homebrew/bin/cmake ]]; then
    export PATH="/opt/homebrew/bin:${PATH}"
fi

for command_name in shasum cmake xcodebuild xcrun; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "Missing required command: ${command_name}" >&2
        exit 1
    fi
done

source_fingerprint="$(
    {
        printf 'CoolProp=%s\n' "${coolprop_version}"
        shasum -a 256 "${bridge_header}" "${bridge_source}" "${build_script}" "${coolprop_patch_script}"
    } | shasum -a 256 | awk '{print $1}'
)"

framework_is_current=false
if [[ -d "${framework_path}" && -f "${stamp_path}" ]]; then
    recorded_fingerprint="$(tr -d '[:space:]' < "${stamp_path}")"
    if [[ "${recorded_fingerprint}" == "${source_fingerprint}" ]]; then
        framework_is_current=true
    fi
fi

if [[ "${framework_is_current}" == true ]]; then
    touch "${package_manifest}"
    echo "CoolProp XCFramework is current; rebuild skipped."
    echo "Refreshed the local Swift package manifest timestamp for Xcode."
    exit 0
fi

backup_root="/tmp/phasexpert-coolprop-backup-$(date +%Y%m%d-%H%M%S)"
backup_framework_path=""
restore_framework_after_failure() {
    local exit_status=$?
    if [[ "${exit_status}" -ne 0 ]]; then
        if [[ -n "${backup_framework_path}" && -e "${backup_framework_path}" ]]; then
            if [[ -e "${framework_path}" ]]; then
                mv "${framework_path}" "${backup_root}/failed-PhaseXpertCoolPropBridge.xcframework"
            fi
            mv "${backup_framework_path}" "${framework_path}"
            echo "Restored the previous XCFramework after rebuild failure." >&2
        fi
        touch "${package_manifest}"
    fi
    exit "${exit_status}"
}
trap restore_framework_after_failure EXIT

if [[ -e "${framework_path}" ]]; then
    mkdir -p "${backup_root}"
    backup_framework_path="${backup_root}/PhaseXpertCoolPropBridge.xcframework"
    mv "${framework_path}" "${backup_framework_path}"
    echo "Moved stale XCFramework to ${backup_root}."
fi

COOLPROP_VERSION="${coolprop_version}" bash "${build_script}"

info_plist="${framework_path}/Info.plist"
if [[ ! -f "${info_plist}" ]]; then
    echo "Rebuild did not produce an XCFramework Info.plist." >&2
    exit 1
fi
if ! grep -q "ios-arm64" "${info_plist}" ||
   ! grep -q "ios-arm64_x86_64-simulator" "${info_plist}"; then
    echo "Rebuilt XCFramework does not contain the required device and simulator slices." >&2
    exit 1
fi

header_count=0
while IFS= read -r generated_header; do
    header_count=$((header_count + 1))
    if ! cmp -s "${bridge_header}" "${generated_header}"; then
        echo "Generated bridge header does not match tracked source: ${generated_header}" >&2
        exit 1
    fi
done < <(find "${framework_path}" -type f -name PhaseXpertCoolPropBridge.h -print)

if [[ "${header_count}" -lt 2 ]]; then
    echo "Expected bridge headers in both XCFramework slices." >&2
    exit 1
fi

printf '%s\n' "${source_fingerprint}" > "${stamp_path}"
touch "${package_manifest}"
trap - EXIT
echo "CoolProp XCFramework rebuilt and fingerprinted successfully."
echo "Refreshed the local Swift package manifest timestamp for Xcode."
