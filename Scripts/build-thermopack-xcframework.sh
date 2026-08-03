#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
version="v2.2.4"
revision="ca75d8e095e8b951616897efe1bca9b8c3badda7"
deployment_target="18.0"
source_root="${project_root}/Vendor/ThermoPack/source"
work_root="${project_root}/Vendor/ThermoPack/build"
output_root="${project_root}/Vendor/ThermoPack"
framework="${output_root}/PhaseXpertThermoPackBridge.xcframework"
bridge_header="${project_root}/Native/ThermoPackBridge/include/PhaseXpertThermoPackBridge.h"
bridge_source="${project_root}/Native/ThermoPackBridge/src/PhaseXpertThermoPackBridge.cpp"
smoke_source="${project_root}/Native/ThermoPackBridge/smoke/thermopack_smoke.cpp"
patcher="${project_root}/Native/ThermoPackBridge/patches/prepare_ios_static_build.py"

for command_name in git cmake ninja python3 xcodebuild xcrun libtool lipo nm otool shasum file; do
    command -v "${command_name}" >/dev/null 2>&1 || {
        echo "Missing required command: ${command_name}" >&2
        exit 1
    }
done

fortran_compiler="${THERMOPACK_FORTRAN_COMPILER:-}"
if [[ -z "${fortran_compiler}" ]]; then
    for candidate in flang-new flang; do
        if command -v "${candidate}" >/dev/null 2>&1; then
            fortran_compiler="$(command -v "${candidate}")"
            break
        fi
    done
fi
if [[ -z "${fortran_compiler}" || ! -x "${fortran_compiler}" ]]; then
    echo "Set THERMOPACK_FORTRAN_COMPILER to an LLVM Flang compiler capable of Apple iOS targets." >&2
    exit 1
fi

mkdir -p "${output_root}"
if [[ ! -d "${source_root}/.git" ]]; then
    git clone --filter=blob:none --branch "${version}" \
        https://github.com/thermotools/thermopack.git "${source_root}"
fi
git -C "${source_root}" fetch --tags origin
git -C "${source_root}" checkout --detach "${revision}"
git -C "${source_root}" reset --hard "${revision}"
python3 "${patcher}" "${source_root}"

resolved_revision="$(git -C "${source_root}" rev-parse HEAD)"
[[ "${resolved_revision}" == "${revision}" ]] || {
    echo "Resolved ThermoPack revision does not match the pin." >&2
    exit 1
}

build_slice() {
    local sdk="$1"
    local arch="$2"
    local target="$3"
    local build_dir="${work_root}/${sdk}-${arch}"
    local sdk_path
    sdk_path="$(xcrun --sdk "${sdk}" --show-sdk-path)"

    local runtime_archives_raw
    if [[ "${sdk}" == "iphoneos" ]]; then
        runtime_archives_raw="${THERMOPACK_FORTRAN_RUNTIME_ARCHIVES_IPHONEOS:-}"
    else
        runtime_archives_raw="${THERMOPACK_FORTRAN_RUNTIME_ARCHIVES_IPHONESIMULATOR:-}"
    fi
    if [[ -z "${runtime_archives_raw}" ]]; then
        echo "Set platform-specific static Flang runtime archives for ${sdk}." >&2
        exit 1
    fi
    local runtime_archives=()
    IFS=':' read -r -a runtime_archives <<< "${runtime_archives_raw}"
    for archive in "${runtime_archives[@]}"; do
        [[ -f "${archive}" ]] || {
            echo "Missing static Fortran runtime archive: ${archive}" >&2
            exit 1
        }
        file "${archive}" | grep -q "archive" || {
            echo "Fortran runtime dependency is not a static archive: ${archive}" >&2
            exit 1
        }
    done
    rm -rf "${build_dir}"
    mkdir -p "${build_dir}"

    cmake -S "${source_root}" -B "${build_dir}" -G Ninja \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_SYSROOT="${sdk_path}" \
        -DCMAKE_OSX_ARCHITECTURES="${arch}" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="${deployment_target}" \
        -DCMAKE_Fortran_COMPILER="${fortran_compiler}" \
        -DCMAKE_Fortran_FLAGS="--target=${target} -isysroot ${sdk_path}" \
        -DCMAKE_BUILD_TYPE=Release
    cmake --build "${build_dir}" --config Release --target thermopack_static

    local thermopack_archive
    thermopack_archive="$(find "${build_dir}" -name 'libthermopack.a' -type f | head -1)"
    [[ -f "${thermopack_archive}" ]] || {
        echo "ThermoPack static archive not produced for ${sdk}/${arch}." >&2
        exit 1
    }

    local bridge_object="${build_dir}/PhaseXpertThermoPackBridge.o"
    xcrun --sdk "${sdk}" clang++ -std=c++17 -O2 -fvisibility=hidden \
        -target "${target}" -isysroot "${sdk_path}" \
        -I"${project_root}/Native/ThermoPackBridge/include" \
        -I"${source_root}/include" \
        -c "${bridge_source}" -o "${bridge_object}"

    libtool -static -o "${build_dir}/libPhaseXpertThermoPackBridge.a" \
        "${bridge_object}" "${thermopack_archive}" "${runtime_archives[@]}"

    local smoke_executable="${build_dir}/thermopack-smoke"
    xcrun --sdk "${sdk}" clang++ -std=c++17 -O2 \
        -target "${target}" -isysroot "${sdk_path}" \
        -I"${project_root}/Native/ThermoPackBridge/include" \
        "${smoke_source}" "${build_dir}/libPhaseXpertThermoPackBridge.a" \
        -framework Accelerate -o "${smoke_executable}"
    if otool -L "${smoke_executable}" \
        | grep -Ei 'gfortran|quadmath|libomp|libgomp'; then
        echo "Unsupported dynamic Fortran/OpenMP dependency for ${sdk}/${arch}." >&2
        exit 1
    fi
}

build_slice iphoneos arm64 "arm64-apple-ios${deployment_target}"
build_slice iphonesimulator arm64 "arm64-apple-ios${deployment_target}-simulator"
build_slice iphonesimulator x86_64 "x86_64-apple-ios${deployment_target}-simulator"

simulator_library="${work_root}/iphonesimulator-universal.a"
lipo -create \
    "${work_root}/iphonesimulator-arm64/libPhaseXpertThermoPackBridge.a" \
    "${work_root}/iphonesimulator-x86_64/libPhaseXpertThermoPackBridge.a" \
    -output "${simulator_library}"

headers_root="${work_root}/headers"
rm -rf "${headers_root}"
mkdir -p "${headers_root}"
cp "${bridge_header}" "${headers_root}/"
cp "${project_root}/Native/ThermoPackBridge/include/module.modulemap" "${headers_root}/"

rm -rf "${framework}"
xcodebuild -create-xcframework \
    -library "${work_root}/iphoneos-arm64/libPhaseXpertThermoPackBridge.a" \
    -headers "${headers_root}" \
    -library "${simulator_library}" \
    -headers "${headers_root}" \
    -output "${framework}"

find "${framework}" -type f -perm -111 -print0 | while IFS= read -r -d '' binary; do
    if otool -L "${binary}" 2>/dev/null | grep -Ei 'gfortran|quadmath|libomp|libgomp'; then
        echo "Unsupported dynamic Fortran/OpenMP dependency detected in ${binary}." >&2
        exit 1
    fi
done

printf '%s\n' "${revision}" > "${output_root}/THERMOPACK-REVISION.txt"
printf '%s\n' "${version}" > "${output_root}/THERMOPACK-VERSION.txt"
{
    printf 'ThermoPack=%s@%s\n' "${version}" "${revision}"
    shasum -a 256 "${bridge_header}" "${bridge_source}" "${smoke_source}" "${patcher}" "$0"
} | shasum -a 256 | awk '{print $1}' > "${output_root}/BRIDGE-SOURCE-SHA256.txt"
touch "${project_root}/PhaseXpertCore/Package.swift"

echo "Created ${framework}"
echo "Native calculations and simulator/device tests are still required before acceptance."