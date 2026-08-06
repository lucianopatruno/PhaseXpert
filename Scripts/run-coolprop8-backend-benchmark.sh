#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${project_root}"

python3 Scripts/coolprop8_benchmark.py \
    --repo-root "${project_root}" \
    --output Documentation/Feasibility/CoolProp8ComparisonResults.json \
    --timing-output /tmp/phasexpert-coolprop8-timing-results.json
