# Native SRK Phase-Envelope Prototype

Branch: `agent/native-srk-phase-envelope-prototype`

Base: post-merge `main` after PR27 merge commit `f75052489baf8efb798fffcb77137b730d4ceaa4`

Status: draft runtime feasibility prototype. This is not a production provider and is not scientific validation.

## Objective

Evaluate whether PhaseXpert can calculate local, offline bubble and dew boundaries without NeqSim, CoolProp phase-envelope calls, Python, Java, a server or network access at runtime.

The prototype is intentionally isolated in `PhaseXpertCore/Numerics` and is not registered in `ProviderRegistry`, exposed in the model picker or used as a production default.

## Model

- EOS: Soave-Redlich-Kwong.
- Alpha function: standard Soave alpha.
- Mixing rule: classical van der Waals one-fluid quadratic mixing.
- Components: CO2 and N2.
- Units: SI internally.
- Provider identity: `phasexpert-native-srk-prototype`.

This is PhaseXpert's native SRK prototype. It must not be labelled NeqSim.

## Parameter Provenance

Primary source inspected: NeqSim 3.16.0 source commit `3af7b560525b57f2d3da2c803a08e2b41a8d7f5a`.

Component parameters are taken from `src/main/resources/data/COMP.csv`:

| Component | Row | Tc | Pc | Acentric factor |
| --- | --- | --- | --- | --- |
| CO2 | `10,CO2,...` | `31.04 C` = `304.19 K` | `73.815 bar` = `7,381,500 Pa` | `0.2276` |
| nitrogen | `16,nitrogen,...` | `-147.05 C` = `126.10 K` | `33.944 bar` = `3,394,400 Pa` | `0.0403` |

Binary interaction data are taken from `src/main/resources/data/INTER.csv` row `7452,CO2,nitrogen,Classic,...`:

| Interaction | Column | Value |
| --- | --- | --- |
| CO2/nitrogen SRK Classic | `KIJSRK` | `-0.0171` |

The molar gas constant is `8.31446261815324 J mol^-1 K^-1`.

The inspected NeqSim source is Apache-2.0 licensed. Production use of copied data must retain required notices and should receive explicit licensing review before this prototype is promoted.

## Algorithm

The implementation includes:

- cubic SRK compressibility-root solving;
- physical root selection for liquid and vapour fugacity calculations;
- component fugacity coefficients;
- pure-CO2 saturation by fugacity-equality bisection;
- mixture bubble-pressure solving at fixed temperature;
- mixture dew-pressure solving at fixed temperature;
- Wilson-seeded tangent-plane-distance screening for preliminary stability classification;
- safeguarded finite-difference Newton updates on `ln(P)` with bounded successive-substitution fallback;
- independent bubble and dew tracing over a bounded temperature grid;
- explicit iteration limits, tolerances, pressure bounds and consecutive-failure limits;
- finite-value checks and explicit gap reporting;
- cancellation checks before every solve and inside every iterative loop.

The implementation does not call CoolProp, NeqSim, Python, Java, a server or the network.

## Acceptance Gate

The prototype is accepted only if it later demonstrates all of the following:

- local offline operation on iPhone 17 simulator and physical iPhone;
- deterministic termination with no UI blocking;
- prompt cancellation;
- finite calculated bubble and dew points for pure CO2, 97/3 CO2/N2 and 90/10 CO2/N2;
- honest gaps for non-converged regions;
- scientifically reasonable software parity against `LocalPhaseDiagramNeqSimReferenceDataset.json` under tolerances defined before comparison;
- no fallback to CoolProp or NeqSim.

The initial parity tolerances from PR27 remain the screening criteria:

| Metric | Initial Gate Tolerance |
| --- | --- |
| Bubble pressure mean absolute relative error | <= 10% |
| Dew pressure mean absolute relative error | <= 10% |
| Bubble pressure 95th-percentile relative error | <= 20% |
| Dew pressure 95th-percentile relative error | <= 20% |
| Maximum pressure relative error outside critical region | <= 35% |
| Temperature matching window | nearest point within 1.0 K |
| Branch convergence coverage | >= 80% of reference branch points per composition |
| Cancellation response | <= 100 ms after cancellation flag is set |

These are software-parity tolerances only. They are not experimental validation or engineering accuracy limits.

## Current Limitations

- The prototype is not integrated into the UI or provider registry.
- Critical-region handling is conservative and reports failures rather than forcing branch closure.
- The current pressure solve is a scalar safeguarded Newton formulation around fugacity-ratio residuals; a full simultaneous flash/stability formulation may still be required for higher coverage.
- Simulator and physical-iPhone execution, app-size delta, peak memory and UI responsiveness measurements remain pending.
- Independent published-data comparisons remain pending.

## Recommended Next Step

Run the focused `NativeSRKPhaseEnvelopeTests`, inspect the reference-comparison metrics, then improve the mixture solver if coverage or parity fails. The next numerical improvement should be a full flash/stability formulation with stronger critical-region handling, not parameter tuning to force visual agreement.
