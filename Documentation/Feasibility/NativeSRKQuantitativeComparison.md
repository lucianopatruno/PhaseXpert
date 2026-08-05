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
| co2-97-n2-3 | bubble | 59.063-300.615 | 61.591-302.179 | 39 | 60 | 47 | 97.4% | 2,503 | 1,277 | 7,039 | 12,182 | 0.1% | 0.3% |
| co2-97-n2-3 | dew | 186.265-302.227 | 174.375-301.548 | 25 | 278 | 40 | 96.0% | 3,619 | 1,328 | 10,232 | 17,745 | 0.3% | 0.7% |
| co2-90-n2-10 | bubble | 54.670-296.498 | 139.987-294.708 | 83 | 198 | 33 | 60.2% | 20,840 | 16,081 | 72,510 | 85,899 | 0.4% | 2.2% |
| co2-90-n2-10 | dew | 149.799-297.454 | 173.375-296.097 | 26 | 265 | 29 | 92.3% | 10,482 | 3,322 | 35,972 | 106,605 | 0.4% | 1.5% |

## Interpretation

The coupled Newton/stability prototype remains entirely local and deterministic, but it does not yet meet the acceptance gate. The latest run preserves bidirectional pseudo-arc search from the selected continuous segment and adds bounded pressure-parameterized and two-phase-flash diagnostics at the 90/10 CO2/N2 bubble endpoint. The 97/3 CO2/N2 bubble branch remains extended to `61.591 K`. The accepted 90/10 CO2/N2 bubble boundary remains unchanged at the cold end: maximum relative pressure error stays controlled at 2.2%, but continuous bubble-boundary coverage remains 60.2% and still does not extend below 139.987 K.

## Failure Diagnostics

- Pure CO2: the last accepted saturation point remains `T = 290.096 K`; the reference bubble branch extends to `304.192 K`, leaving an endpoint gap of about `14.096 K`. The next attempted points terminate as coalesced-root critical-region gaps rather than fabricated endpoints.
- 90/10 CO2/N2 bubble: the detached diagnostic cold seed at `T = 61.875 K` still converges independently to `P = 287,466.655 Pa` with `vapor xCO2 = 1.10e-12`, residual `1.36e-12`, and minimum TPD `-3.199`, but the production tracer now rejects that low-temperature segment from accepted coverage because it is not connected to the selected continuous branch. The accepted branch still starts near `139.987 K`.
- Bidirectional search: the backward tangent from the selected 90/10 main branch was explored, but the first accepted cold-side state remains `139.987 K`. No fold connecting the main branch to the detached 61.875 K segment was found under the current bounded step, pressure-jump, residual, and continuity checks.
- Cold-side stability/root diagnostic at the accepted 90/10 endpoint: deterministic multi-start vapor-like TPD minimization found `13` deduplicated stationary points and no negative continuous TPD minimum near the accepted branch. The best continuity-neighborhood stationary point has composition `[0.0608755, 0.9391245]`, TPD `6.69e-16`, residual `4.30e-12`, is not feed-trivial and is not boundary-pinned. Root diagnostics report a single admissible root per phase calculation, root separation `0.186764`, density separation `5,400.49 mol m^-3`, and phase-composition distance `13.784`.
- Controlled initialization experiment: existing production initialization, multi-start TPD initialization, root-continuity-aware diagnostics, and combined TPD/root-continuity screening all fail to advance the same continuous branch below `139.987 K`. The bounded production retry at the next cold step fails by line-search residuals from all candidate seeds, while the TPD search finds no valid negative-TPD minimum inside the accepted-branch continuity neighborhood.
- Pressure-parameterized saturation diagnostic: fixed-pressure bubble solving from the accepted endpoint advances only to `139.983638 K`, so it confirms local regularity over a tiny step but does not recover the missing cold branch.
- Full two-phase flash diagnostic: the bounded `ln(K1)`, `ln(K2)` and vapour-fraction-logit formulation found `92` converged finite-beta states from `200` deterministic neighborhood attempts, including `84` continuity-compatible flash states down to `123.986665 K`. These states remain diagnostic because finite-beta flash solutions are not bubble-boundary points and have not yet been continued back to a verified `beta -> 0` boundary below the prior endpoint.
- Pseudo-arc diagnostic: a bounded 97/3 CO2/N2 bubble continuation step from `220 K` and `228 K` predicts `232.002 K` and corrects to `232.003 K` with residual `1.81e-13`. A forced 90/10 CO2/N2 jump from the main branch near `139.987 K` toward the detached `61.875 K` point is rejected as non-continuous with an incipient-composition-boundary failure.
- 90/10 CO2/N2 bubble gap examples below 140 K: `54.000 K` fails with singular Jacobian residual norm about `5.85`; `61.375 K` fails with singular Jacobian residual norm about `0.246`; points from roughly `66.908 K` upward fail mainly by bounded line-search failure before the main branch resumes near `139.987 K`.

Likely contributors:

- bidirectional pseudo-arc search now participates in mixture tracing after initialization, but it has not found a continuous route from the 90/10 main branch below `139.987 K`;
- the focused cold-side pressure/flash diagnostic indicates a bubble-point parameterization limitation that can be entered through finite-beta flash-boundary tracking, but the actual bubble boundary below `139.987 K` has not yet been recovered or counted;
- the 90/10 bubble branch can still produce TPD-backed near-boundary cold seed points, but they are disconnected from the main branch and are excluded from parity statistics;
- pure-CO2 saturation deliberately rejects coalesced single-root states near the critical region, so it reports a gap rather than fabricating a critical endpoint;
- production mixture continuation uses the bounded pseudo-arc corrector after initialization, but the cold-side endpoint still fails under the deterministic continuity, residual, root and TPD bounds.

This is software parity evidence only. It is not validation against experimental data and must not be used for engineering, safety, commercial or regulatory decisions.

## Timing And Determinism

The JSON comparison output is deterministic across repeated generation because timing fields are excluded from `NativeSRKComparisonResults.json`.

Measured on the local Mac validation run:

| Case | Elapsed s | Attempted points | Converged points | Gaps | Seconds per attempted point |
| --- | ---: | ---: | ---: | ---: | ---: |
| pure-co2 | 0.243 | 528 | 50 | 478 | 0.000460 |
| co2-97-n2-3 | 7.273 | 338 | 87 | 251 | 0.021517 |
| co2-90-n2-10 | 10.039 | 463 | 62 | 401 | 0.021682 |

The focused cold-side pressure/flash diagnostic measured `0.172 s` for `200` flash attempts, `92` converged flashes and `84` continuity-compatible flash states. Repeated full comparison report generation including that diagnostic produced byte-for-byte identical JSON and measured `26.38 s` and `26.84 s` on consecutive runs. A synthetic cancellation check returned in `0.000004 s` before any point was emitted.

## Next Numerical Step

Promote the diagnostic finite-beta flash-boundary tracking into a bounded continuation toward the `beta -> 0` bubble limit below `139.987 K`, and accept points only if the flash path converges back to a genuine continuous bubble boundary with preserved pressure parity.
