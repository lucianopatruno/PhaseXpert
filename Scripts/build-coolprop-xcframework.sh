#!/usr/bin/env bash
set -euo pipefail

coolprop_version="${COOLPROP_VERSION:-v8.0.0}"
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_root="${PROJECT_TEMP_DIR:-${TMPDIR:-/tmp}/phasexpert-coolprop}"
source_root="${work_root}/CoolProp"
device_build="${work_root}/build-iphoneos"
simulator_build="${work_root}/build-iphonesimulator"
output_root="${project_root}/Vendor/CoolProp"
bridge_source="${project_root}/Native/CoolPropBridge/src/PhaseXpertCoolPropBridge.cpp"
bridge_headers="${project_root}/Native/CoolPropBridge/include"
deployment_target="18.0"

for command_name in git cmake xcodebuild xcrun; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "Missing required command: ${command_name}" >&2
        exit 1
    fi
done

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "This script must run on macOS with Xcode installed." >&2
    exit 1
fi

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

resolve_sdk_identifier() {
    local requested_sdk="$1"
    local resolved_sdk

    if xcrun --sdk "${requested_sdk}" --show-sdk-path >/dev/null 2>&1; then
        printf '%s\n' "${requested_sdk}"
        return
    fi

    resolved_sdk="$(
        xcodebuild -showsdks 2>/dev/null |
            awk -v prefix="${requested_sdk}" '$0 ~ "-sdk " prefix { print $NF; found = 1 } END { exit found ? 0 : 1 }' |
            tail -n 1
    )"

    if [[ -z "${resolved_sdk}" ]]; then
        echo "Unable to locate an installed SDK matching ${requested_sdk}." >&2
        exit 1
    fi

    printf '%s\n' "${resolved_sdk}"
}

mkdir -p "${work_root}" "${output_root}"

if [[ ! -d "${source_root}/.git" ]]; then
    git clone \
        --branch "${coolprop_version}" \
        --depth 1 \
        --recurse-submodules \
        --shallow-submodules \
        https://github.com/CoolProp/CoolProp.git \
        "${source_root}"
fi

build_coolprop() {
    local sdk="$1"
    local architectures="$2"
    local build_directory="$3"
    local sdk_identifier
    local sdk_path

    sdk_identifier="$(resolve_sdk_identifier "${sdk}")"
    sdk_path="$(xcrun --sdk "${sdk_identifier}" --show-sdk-path)"

    cmake \
        -S "${source_root}" \
        -B "${build_directory}" \
        -G "Unix Makefiles" \
        -DCOOLPROP_STATIC_LIBRARY=ON \
        -DCOOLPROP_SHARED_LIBRARY=OFF \
        -DCOOLPROP_EXTERNC_LIBRARY=OFF \
        -DCOOLPROP_LIBRARY_NAME=CoolProp \
        -DFORCE_BITNESS_NATIVE=ON \
        -DBUILD_TESTING=OFF \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_SYSROOT="${sdk_path}" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="${deployment_target}" \
        -DCMAKE_OSX_ARCHITECTURES="${architectures}"

    cmake --build "${build_directory}" --config Release --target CoolProp
}

find_library() {
    local build_directory="$1"
    local library_path
    library_path="$(find "${build_directory}" -type f -name 'libCoolProp.a' -print -quit)"
    if [[ -z "${library_path}" ]]; then
        echo "CoolProp static library was not produced in ${build_directory}." >&2
        exit 1
    fi
    printf '%s\n' "${library_path}"
}

compile_bridge() {
    local sdk="$1"
    local build_directory="$2"
    shift 2
    local architecture_flags=("$@")
    local sdk_identifier
    local minimum_version_flag

    if [[ "${sdk}" == "iphoneos" ]]; then
        minimum_version_flag="-miphoneos-version-min=${deployment_target}"
    else
        minimum_version_flag="-mios-simulator-version-min=${deployment_target}"
    fi

    sdk_identifier="$(resolve_sdk_identifier "${sdk}")"

    xcrun --sdk "${sdk_identifier}" clang++ \
        -std=c++17 \
        -O2 \
        -fvisibility=hidden \
        -fvisibility-inlines-hidden \
        -isysroot "$(xcrun --sdk "${sdk_identifier}" --show-sdk-path)" \
        "${minimum_version_flag}" \
        "${architecture_flags[@]}" \
        -I"${bridge_headers}" \
        -I"${source_root}/include" \
        -I"${build_directory}/_deps/fmt-src/include" \
        -I"${build_directory}/_deps/eigen-src" \
        -I"${build_directory}/_deps/msgpack-c-src/include" \
        -I"${build_directory}/_deps/nlohmann_json-src/include" \
        -I"${build_directory}/_deps/valijson-src/include" \
        -I"${build_directory}/_deps/boost_headers-src" \
        -I"${build_directory}/_deps/multicomplex-src/multicomplex/include" \
        -c "${bridge_source}" \
        -o "${build_directory}/PhaseXpertCoolPropBridge.o"
}

combine_libraries() {
    local build_directory="$1"
    local coolprop_library="$2"
    local combined_library="$3"

    xcrun libtool -static \
        -o "${combined_library}" \
        "${build_directory}/PhaseXpertCoolPropBridge.o" \
        "${coolprop_library}"
}

build_coolprop iphoneos arm64 "${device_build}"
build_coolprop iphonesimulator "arm64;x86_64" "${simulator_build}"

device_library="$(find_library "${device_build}")"
simulator_library="$(find_library "${simulator_build}")"

compile_bridge iphoneos "${device_build}" -arch arm64
compile_bridge iphonesimulator "${simulator_build}" -arch arm64 -arch x86_64

device_combined="${device_build}/libPhaseXpertCoolPropBridge.a"
simulator_combined="${simulator_build}/libPhaseXpertCoolPropBridge.a"
combine_libraries "${device_build}" "${device_library}" "${device_combined}"
combine_libraries "${simulator_build}" "${simulator_library}" "${simulator_combined}"

framework_path="${output_root}/PhaseXpertCoolPropBridge.xcframework"
if [[ -e "${framework_path}" ]]; then
    echo "Remove the existing ${framework_path} before rebuilding." >&2
    exit 1
fi

xcodebuild -create-xcframework \
    -library "${device_combined}" \
    -headers "${bridge_headers}" \
    -library "${simulator_combined}" \
    -headers "${bridge_headers}" \
    -output "${framework_path}"

cp "${source_root}/LICENSE" "${output_root}/COOLPROP-LICENSE.txt"
git -C "${source_root}" rev-parse HEAD > "${output_root}/COOLPROP-REVISION.txt"

echo "Created ${framework_path}"
echo "Recorded upstream revision in ${output_root}/COOLPROP-REVISION.txt"
echo "CoolProp remains validation-pending; building the binary does not validate results."
