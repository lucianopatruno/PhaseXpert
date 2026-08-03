#!/usr/bin/env python3
"""Apply PhaseXpert's deterministic CoolProp v8.0.0 envelope-loop guard."""

from pathlib import Path
import sys


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: apply_phase_envelope_iteration_cap.py <PhaseEnvelopeRoutines.cpp>", file=sys.stderr)
        return 2

    source_path = Path(sys.argv[1])
    source = source_path.read_text(encoding="utf-8")
    original = """        std::size_t iter = 0,  //< The iteration counter
          iter0 = 0;           //< A reference point for the counter, can be increased to go back to linear interpolation
        CoolPropDbl factor = 1.05;

        for (;;) {
        top_of_loop:;  // A goto label so that nested loops can break out to the top of this loop

            if (failure_count > 5) {
"""
    replacement = """        std::size_t iter = 0,  //< The iteration counter
          iter0 = 0;           //< A reference point for the counter, can be increased to go back to linear interpolation
        CoolPropDbl factor = 1.05;

        // PhaseXpert downstream safety guard. The upstream continuation loop
        // has no iteration limit and may never satisfy its pressure-closure or
        // near-pure-phase exit for some CO2-rich mixtures. Returning here keeps
        // PhaseEnvelope.built false and preserves every provider-calculated
        // point already stored without extrapolating or closing the trace.
        constexpr std::size_t kPhaseXpertMaximumEnvelopeIterations = 256;

        for (;;) {
        top_of_loop:;  // A goto label so that nested loops can break out to the top of this loop

            if (iter >= kPhaseXpertMaximumEnvelopeIterations) {
                return;
            }

            if (failure_count > 5) {
"""
    matches = source.count(original)
    if matches != 1:
        print(
            f"expected one CoolProp v8.0.0 envelope-loop match, found {matches}",
            file=sys.stderr,
        )
        return 1

    source_path.write_text(source.replace(original, replacement), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
