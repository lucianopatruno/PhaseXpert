# Native SRK Quantitative Comparison

Status: current prototype does not pass the quantitative acceptance gate.

Reference dataset: `Documentation/Feasibility/LocalPhaseDiagramNeqSimReferenceDataset.json`

Reference model: NeqSim 3.16.0 `SystemSrkEos`, `classic` mixing rule, source commit `3af7b560525b57f2d3da2c803a08e2b41a8d7f5a`.

Local model: `phasexpert-native-srk-prototype`.

Comparison command:

```text
swiftc -parse-as-library PhaseXpertCore/Sources/PhaseXpertCore/Domain/Component.swift PhaseXpertCore/Sources/PhaseXpertCore/Numerics/NativeSRKPhaseEnvelope.swift Scripts/generate-native-srk-comparison-report.swift -o /tmp/NativeSRKComparisonReport
/tmp/NativeSRKComparisonReport > Documentation/Feasibility/NativeSRKComparisonResults.json
```

Comparison rule: interpolate pressure linearly by temperature inside continuous converged local intervals on the same branch. No extrapolation is used, and interpolation is rejected across recorded local gaps.

Acceptance tolerances defined before the run:

| Metric | Tolerance |
| --- | --- |
| Mean relative pressure error | <= 10% |
| 95th-percentile relative pressure error | <= 20% |
| Maximum relative pressure error | <= 35% |
| Branch coverage | >= 80% |

## Results

| Case | Branch | Reference T range K | Local T range K | Reference points | Local attempted | Local converged | Coverage | Mean abs error Pa | Median abs error Pa | 95th abs error Pa | Max abs error Pa | Mean rel error | Max rel error |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| pure-co2 | bubble | 186.774-304.192 | 174.875-290.096 | 31 | 263 | 25 | 64.5% | 4,423 | 2,554 | 13,482 | 16,481 | 0.5% | 1.0% |
| pure-co2 | dew | 186.774-296.988 | 174.875-290.096 | 21 | 263 | 25 | 95.2% | 4,423 | 2,554 | 13,482 | 16,481 | 0.5% | 1.0% |
| co2-97-n2-3 | bubble | 59.063-300.615 | 79.875-298.597 | 39 | 87 | 41 | 84.6% | 10,529 | 1,298 | 9,416 | 270,585 | 0.2% | 3.8% |
| co2-97-n2-3 | dew | 186.265-302.227 | 174.375-301.097 | 25 | 265 | 29 | 84.0% | 3,774 | 1,328 | 10,232 | 17,745 | 0.3% | 0.7% |
| co2-90-n2-10 | bubble | 54.670-296.498 | 139.875-294.597 | 83 | 200 | 33 | 60.2% | 21,095 | 15,776 | 42,825 | 209,087 | 0.2% | 2.3% |
| co2-90-n2-10 | dew | 149.799-297.454 | 173.375-296.097 | 26 | 263 | 29 | 92.3% | 10,482 | 3,322 | 35,972 | 106,605 | 0.4% | 1.5% |

## Interpretation

The coupled Newton/stability prototype remains entirely local and deterministic, but it does not yet meet the acceptance gate. The latest run adds bounded multi-start Michelsen TPD minimization for stability diagnostics and bubble-solve seeding while preserving the continuity-oriented dew path. Where converged branches overlap the reference, pressure parity remains within the predefined relative-error tolerances. The remaining acceptance failure is coverage: pure-CO2 bubble coverage terminates before the reference critical-region endpoint, and the 90/10 CO2/N2 bubble branch still does not cover the colder part of the reference domain.

Likely contributors:

- the current TPD minimizer is bounded and multi-start, but it is still a one-dimensional binary-composition minimization and not yet coupled into an arc-length branch corrector;
- the 90/10 bubble branch still cannot be initialized robustly below about 140 K without collapsing the incipient phase to a composition boundary;
- pure-CO2 saturation deliberately rejects coalesced single-root states near the critical region, so it reports a gap rather than fabricating a critical endpoint;
- branch continuation still uses temperature stepping plus bounded reseeding, without an arc-length or pressure-oriented continuation mode.

This is software parity evidence only. It is not validation against experimental data and must not be used for engineering, safety, commercial or regulatory decisions.

## Timing And Determinism

The JSON comparison output is deterministic across repeated generation because timing fields are excluded from `NativeSRKComparisonResults.json`.

Measured on the local Mac validation run:

| Case | Elapsed s | Attempted points | Converged points | Gaps | Seconds per attempted point |
| --- | ---: | ---: | ---: | ---: | ---: |
| pure-co2 | 0.237 | 526 | 50 | 476 | 0.000451 |
| co2-97-n2-3 | 10.854 | 352 | 70 | 282 | 0.030836 |
| co2-90-n2-10 | 16.574 | 463 | 62 | 401 | 0.035798 |

Repeated full comparison report generation produced byte-for-byte identical JSON and measured `33.44 s` and `29.88 s` on consecutive runs. A synthetic cancellation check returned in `0.000010 s` before any point was emitted.

## Next Numerical Step

Add pseudo-arc-length continuation with a pressure/composition corrector seeded from the minimized TPD results, then investigate whether the remaining 90/10 cold-bubble gap is a branch-following problem or an inherent SRK/parameter mismatch against the NeqSim reference.
