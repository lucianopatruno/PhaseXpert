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
| pure-co2 | bubble | 186.774-304.192 | 174.875-290.096 | 31 | 264 | 25 | 64.5% | 4,423 | 2,554 | 13,482 | 16,481 | 0.5% | 1.0% |
| pure-co2 | dew | 186.774-296.988 | 174.875-290.096 | 21 | 264 | 25 | 95.2% | 4,423 | 2,554 | 13,482 | 16,481 | 0.5% | 1.0% |
| co2-97-n2-3 | bubble | 59.063-300.615 | 61.875-296.597 | 39 | 54 | 43 | 94.9% | 2,457 | 1,277 | 6,897 | 12,182 | 0.1% | 0.3% |
| co2-97-n2-3 | dew | 186.265-302.227 | 174.375-301.097 | 25 | 265 | 29 | 84.0% | 3,774 | 1,328 | 10,232 | 17,745 | 0.3% | 0.7% |
| co2-90-n2-10 | bubble | 54.670-296.498 | 61.875-294.708 | 83 | 196 | 39 | 69.9% | 68,060 | 16,081 | 78,900 | 2,401,464 | 2.8% | 87.4% |
| co2-90-n2-10 | dew | 149.799-297.454 | 173.375-296.097 | 26 | 263 | 29 | 92.3% | 10,482 | 3,322 | 35,972 | 106,605 | 0.4% | 1.5% |

## Interpretation

The coupled Newton/stability prototype remains entirely local and deterministic, but it does not yet meet the acceptance gate. The latest run adds diagnostic pseudo-arc-length machinery with a finite-difference null-space tangent and bounded bordered corrector for `[T, ln(P), incipient-composition logit]` states, while preserving the existing temperature-oriented production trace. The 97/3 CO2/N2 bubble branch still extends lower with acceptable pressure parity. The 90/10 CO2/N2 bubble branch still recovers a detached cold segment down to 61.875 K, but diagnostic pseudo-arc checks reject a forced jump between the main branch and that segment; the detached segment degrades maximum relative pressure error to 87.4%, so it cannot be counted as a passing recovery.

## Failure Diagnostics

- Pure CO2: the last accepted saturation point remains `T = 290.096 K`; the reference bubble branch extends to `304.192 K`, leaving an endpoint gap of about `14.096 K`. The next attempted points terminate as coalesced-root critical-region gaps rather than fabricated endpoints.
- 90/10 CO2/N2 bubble: the previous cold failure at `T = 61.875 K` now converges to `P = 287,466.655 Pa` with `vapor xCO2 = 1.10e-12`, residual `1.36e-12`, and minimum TPD `-3.199`. The low-temperature segment runs only to `65.752 K`, then leaves a large gap until `139.987 K`, so it is not a continuous accepted branch.
- Pseudo-arc diagnostic: a bounded 97/3 CO2/N2 bubble continuation step from `220 K` and `228 K` predicts `232.002 K` and corrects to `232.003 K` with residual `1.81e-13`. A forced 90/10 CO2/N2 jump from the main branch near `139.987 K` toward the detached `61.875 K` point is rejected as non-continuous with an incipient-composition-boundary failure.
- 90/10 CO2/N2 bubble gap examples below 140 K: `54.000 K` fails with singular Jacobian residual norm about `5.85`; `61.375 K` fails with singular Jacobian residual norm about `0.246`; points from roughly `66.908 K` upward fail mainly by bounded line-search failure before the main branch resumes near `139.987 K`.

Likely contributors:

- the current TPD minimizer is bounded and multi-start, but the pseudo-arc-length corrector is still diagnostic and has not replaced the temperature-oriented branch tracer;
- the 90/10 bubble branch can now produce TPD-backed near-boundary cold points, but they are disconnected from the main branch and fail pressure parity;
- pure-CO2 saturation deliberately rejects coalesced single-root states near the critical region, so it reports a gap rather than fabricating a critical endpoint;
- branch continuation still uses temperature stepping plus bounded reseeding, without an arc-length or pressure-oriented continuation mode.

This is software parity evidence only. It is not validation against experimental data and must not be used for engineering, safety, commercial or regulatory decisions.

## Timing And Determinism

The JSON comparison output is deterministic across repeated generation because timing fields are excluded from `NativeSRKComparisonResults.json`.

Measured on the local Mac validation run:

| Case | Elapsed s | Attempted points | Converged points | Gaps | Seconds per attempted point |
| --- | ---: | ---: | ---: | ---: | ---: |
| pure-co2 | 0.204 | 528 | 50 | 478 | 0.000386 |
| co2-97-n2-3 | 7.041 | 319 | 72 | 247 | 0.022072 |
| co2-90-n2-10 | 9.920 | 459 | 68 | 391 | 0.021613 |

Repeated full comparison report generation produced byte-for-byte identical JSON and measured `17.60 s` and `17.33 s` on consecutive runs. A synthetic cancellation check returned in `0.000005 s` before any point was emitted.

## Next Numerical Step

Promote the diagnostic pseudo-arc-length corrector into the actual branch tracer with continuity bookkeeping, then investigate whether the remaining 90/10 cold-bubble gap is a branch-following problem or an inherent SRK/parameter mismatch against the NeqSim reference.
