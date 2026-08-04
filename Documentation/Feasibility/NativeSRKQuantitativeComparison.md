# Native SRK Quantitative Comparison

Status: current prototype does not pass the quantitative acceptance gate.

Reference dataset: `Documentation/Feasibility/LocalPhaseDiagramNeqSimReferenceDataset.json`

Reference model: NeqSim 3.16.0 `SystemSrkEos`, `classic` mixing rule, source commit `3af7b560525b57f2d3da2c803a08e2b41a8d7f5a`.

Local model: `phasexpert-native-srk-prototype`.

Comparison command:

```text
swiftc PhaseXpertCore/Sources/PhaseXpertCore/Domain/Component.swift PhaseXpertCore/Sources/PhaseXpertCore/Numerics/NativeSRKPhaseEnvelope.swift Scripts/generate-native-srk-comparison-report.swift -o /tmp/NativeSRKComparisonReport
/tmp/NativeSRKComparisonReport > Documentation/Feasibility/NativeSRKComparisonResults.json
```

Comparison rule: match by branch and nearest local temperature within 1.0 K. No extrapolation is used. The current report does not interpolate between local points, so coverage is intentionally conservative.

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
| pure-co2 | bubble | 186.774-304.192 | 186.000-303.200 | 31 | 32 | 16 | 45.2% | 4,516,316 | 7,208,832 | 7,329,514 | 7,330,182 | 64.9% | 99.3% |
| pure-co2 | dew | 186.774-296.988 | 186.000-303.200 | 21 | 32 | 16 | 28.6% | 825,582 | 14,275 | 4,909,280 | 4,909,280 | 19.1% | 99.0% |
| co2-97-n2-3 | bubble | 59.063-300.615 | 186.000-301.967 | 39 | 32 | 16 | 10.3% | 319,771 | 235,772 | 941,880 | 941,880 | 6.6% | 13.3% |
| co2-97-n2-3 | dew | 186.265-302.227 | 186.000-301.967 | 25 | 32 | 16 | 36.0% | 411,874 | 7,487 | 3,606,660 | 3,606,660 | 7.0% | 46.4% |
| co2-90-n2-10 | bubble | 54.670-296.498 | 186.000-301.967 | 83 | 32 | 16 | 7.2% | 3,207,308 | 5,124,091 | 5,423,928 | 5,423,928 | 42.0% | 71.6% |
| co2-90-n2-10 | dew | 149.799-297.454 | 186.000-301.967 | 26 | 32 | 16 | 26.9% | 14,388 | 6,894 | 33,478 | 33,478 | 2.9% | 6.2% |

## Interpretation

The bounded Newton/stability prototype remains entirely local and deterministic, but it does not yet meet the acceptance gate. The largest limitations are low coverage across the full NeqSim reference temperature domain and large pure-CO2 and 90/10 bubble pressure deviations.

Likely contributors:

- temperature-domain mismatch: the initial prototype traces from 186 K upward, while mixture reference bubble branches include substantially colder points;
- root selection and phase-stability classification are still preliminary;
- the pressure solve uses safeguarded scalar Newton updates around successive fugacity-ratio updates, not a full simultaneous Newton flash formulation;
- critical-region behavior is not resolved and branches are not forced to close.

This is software parity evidence only. It is not validation against experimental data and must not be used for engineering, safety, commercial or regulatory decisions.

## Next Numerical Step

Replace the current scalar pressure update with a full bounded flash/stability formulation that solves pressure and composition variables together, adds branch-specific continuation from known reference-side endpoints, and reports critical-region termination explicitly.
