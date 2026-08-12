#!/usr/bin/env bash
set -euo pipefail

teqp_version="${TEQP_VERSION:-v0.23.1}"
teqp_commit="a68eb9cabf47af2c4aba0d272ac10fbca4c10eca"
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_root="${PROJECT_TEMP_DIR:-${TMPDIR:-/tmp}/phasexpert-teqp}"
source_root="${work_root}/teqp"
build_root="${work_root}/build"
output_root="${project_root}/Vendor/teqp"
bridge_source="${project_root}/Native/TeqpBridge/src/PhaseXpertTeqpBridge.cpp"
bridge_headers="${project_root}/Native/TeqpBridge/include"
deployment_target="18.0"

for command_name in git cmake python3 xcodebuild xcrun; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "Missing required command: ${command_name}" >&2
        exit 1
    fi
done

mkdir -p "${work_root}" "${output_root}"

if [[ ! -d "${source_root}/.git" ]]; then
    git clone \
        --branch "${teqp_version}" \
        --depth 1 \
        --recurse-submodules \
        --shallow-submodules \
        https://github.com/usnistgov/teqp.git \
        "${source_root}"
fi

actual_commit="$(git -C "${source_root}" rev-parse HEAD)"
if [[ "${actual_commit}" != "${teqp_commit}" ]]; then
    echo "Expected teqp ${teqp_commit}, found ${actual_commit}." >&2
    exit 1
fi

cmake -S "${source_root}" -B "${build_root}" \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DTEQP_NO_PYTHON=ON \
    -DTEQP_NO_TESTS=ON \
    -DTEQP_NO_TEQPCPP=ON \
    -DTEQP_TEQPC=OFF \
    -DTEQP_DISABLED_FACTORIES="CPA,SAFTVRMIE,GENERICSAFT,SQUAREWELL,EXP6,2CLJF,MIE,MULTIFLUIDACTIVITY,PCSAFT,GERG200X,MULTIFLUIDASSOCIATION,LKP,ADVANCEDCUBIC,IDEALHELMHOLTZ,SOFTSAFT" \
    -DCMAKE_BUILD_TYPE=Release

generated_header="${build_root}/generated_headers/PhaseXpertTeqpCarbonDioxideData.hpp"
mkdir -p "$(dirname "${generated_header}")"
python3 - "${source_root}/teqp/fluiddata/dev/fluids/CarbonDioxide.json" "${generated_header}" <<'PY'
import pathlib
import sys

source = pathlib.Path(sys.argv[1])
target = pathlib.Path(sys.argv[2])
text = source.read_text()
target.write_text(
    "#pragma once\n"
    "inline constexpr const char *kPhaseXpertTeqpCarbonDioxideJson = R\"PXTEQPJSON("
    + text +
    ")PXTEQPJSON\";\n"
)
PY

compile_bridge() {
    local sdk="$1"
    local output="$2"
    shift 2
    local minimum_version_flag
    if [[ "${sdk}" == "iphoneos" ]]; then
        minimum_version_flag="-miphoneos-version-min=${deployment_target}"
    else
        minimum_version_flag="-mios-simulator-version-min=${deployment_target}"
    fi

    xcrun --sdk "${sdk}" clang++ \
        -std=c++20 \
        -DTEQP_COMPLEXSTEP_ENABLED \
        -O2 \
        -fvisibility=hidden \
        -fvisibility-inlines-hidden \
        -isysroot "$(xcrun --sdk "${sdk}" --show-sdk-path)" \
        "${minimum_version_flag}" \
        "$@" \
        -I"${bridge_headers}" \
        -I"${build_root}/generated_headers" \
        -I"${source_root}/include" \
        -I"${source_root}/externals/Eigen" \
        -I"${source_root}/externals/autodiff" \
        -I"${source_root}/externals/json-schema-validator/src" \
        -I"${build_root}/_deps/nlohmann_json-src/include" \
        -I"${source_root}/externals/mcx/multicomplex/include" \
        -I"${source_root}/boost_teqp" \
        -I"${source_root}/externals/REFPROP-interop/include" \
        -I"${source_root}/externals/stbrumme-hashing/include" \
        -c "${bridge_source}" \
        -o "${output}"
}

device_object="${build_root}/PhaseXpertTeqpBridge-iphoneos.o"
simulator_object="${build_root}/PhaseXpertTeqpBridge-iphonesimulator.o"
device_library="${build_root}/libPhaseXpertTeqpBridge-iphoneos.a"
simulator_library="${build_root}/libPhaseXpertTeqpBridge-iphonesimulator.a"

compile_bridge iphoneos "${device_object}" -arch arm64
compile_bridge iphonesimulator "${simulator_object}" -arch arm64 -arch x86_64
xcrun libtool -static -o "${device_library}" "${device_object}"
xcrun libtool -static -o "${simulator_library}" "${simulator_object}"

framework_path="${output_root}/PhaseXpertTeqpBridge.xcframework"
if [[ -e "${framework_path}" ]]; then
    echo "Remove the existing ${framework_path} before rebuilding." >&2
    exit 1
fi

xcodebuild -create-xcframework \
    -library "${device_library}" \
    -headers "${bridge_headers}" \
    -library "${simulator_library}" \
    -headers "${bridge_headers}" \
    -output "${framework_path}"

cp "${source_root}/LICENSE.md" "${output_root}/TEQP-LICENSE.txt"
git -C "${source_root}" rev-parse HEAD > "${output_root}/TEQP-REVISION.txt"
git -C "${source_root}" submodule status --recursive > "${output_root}/TEQP-SUBMODULES.txt"

echo "Created ${framework_path}"
echo "Recorded teqp revision ${teqp_commit}."
