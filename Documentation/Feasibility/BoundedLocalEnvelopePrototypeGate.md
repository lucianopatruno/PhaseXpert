# Bounded Local Phase-Envelope Prototype Gate

Branch: `agent/bounded-coolprop-envelope-prototype`

Base commit: `fb9e0f95659891f6e08035c0ce9147772c8de34a`

Status: CoolProp bounded-tracer implementation stopped at the primitive gate. A native cubic-EOS prototype design is proposed as the next scoped implementation route.

## Objective

Replace any potentially blocking local phase-envelope calculation with a fully local implementation that runs offline on iPhone, terminates deterministically, supports cancellation, reports gaps honestly and does not fall back to another provider.

Initial compositions:

- pure CO2;
- 97/3 mol% CO2/N2;
- 90/10 mol% CO2/N2.

## CoolProp API Inspection

PhaseXpert currently uses `px_coolprop_dry_co2_mixture_phase_envelope`, which wraps:

```text
CoolProp::AbstractState::factory("HEOS", fluids)
state->set_mole_fractions(active_fractions)
state->build_phase_envelope("none")
```

The existing PhaseXpert CoolProp source patch adds a deterministic continuation guard to CoolProp's phase-envelope loop at 256 provider steps. That prevents the historic unbounded envelope continuation from running forever, but it is still a monolithic native call: Swift cannot cancel it once the thread enters the native routine.

CoolProp v6.8.0 exposes mixture saturation inputs through:

- `QT_INPUTS`: molar quality plus temperature;
- `PQ_INPUTS`: pressure plus molar quality.

Those inputs route into `FlashRoutines::QT_flash` and `FlashRoutines::PQ_flash`, which use internal mixture VLE solvers including `newton_raphson_twophase`, `newton_raphson_saturation` and `PTflash_twophase`. The relevant option structs contain internal `Nstep_max` values, commonly defaulting to 30, but the public `AbstractState::update(QT_INPUTS/PQ_INPUTS, ...)` API does not expose a way for PhaseXpert to set per-call iteration limits, elapsed-time limits, retry limits, step-size policy or cancellation checks.

CoolProp also explicitly reports that `calc_saturation_ancillary` is not implemented for mixtures. Therefore PhaseXpert does not have a public, documented, externally bounded CoolProp primitive that can satisfy the prototype requirements.

## Gate Decision

Do not implement the requested bounded local tracer by wrapping `QT_INPUTS`, `PQ_INPUTS` or `build_phase_envelope`.

Reason: each option would still enter an internal native solver that cannot be interrupted by Swift cancellation and whose numerical controls are not externally configurable through the public API. A worker-thread timeout around such a call would only abandon the caller, not stop the native calculation.

This is a CoolProp primitive-control blocker, not evidence that local phase diagrams are impossible.

## Recommended Prototype Route

Implement a separate experimental native cubic-EOS solver for the first local prototype. Keep the existing CoolProp and NeqSim providers unchanged. The prototype should be hidden behind an experimental provider identifier until the scientific and iOS gates pass.

Recommended initial model for software-parity evaluation:

- EOS: SRK first, because the NeqSim reference dataset uses `SystemSrkEos`.
- Mixing rule: classical quadratic mixing.
- Components: CO2 and N2 only.
- Binary interaction parameter: do not proceed until the exact CO2/N2 SRK `Classic` value is pinned from NeqSim 3.16.0 `src/main/resources/data/INTER.csv`, row `7452`, or another redistributable authoritative source.
- Units: SI internally.

If SRK parity is inadequate or the parameter provenance is not acceptable, evaluate PR76/PR78 as a separate model with independently pinned parameters and binary interaction data.

## Minimum Native Solver Design

The prototype should expose a small C ABI from a native Swift/C++/Rust implementation:

```text
px_local_cubic_state(...)
px_local_cubic_bubble_point_at_temperature(...)
px_local_cubic_dew_point_at_temperature(...)
px_local_cubic_phase_envelope(...)
px_local_cubic_cancel(...)
```

Each solve must record:

- model identifier, EOS, alpha function, mixing rule and parameter provenance;
- input pressure, temperature, composition and units;
- iteration limit;
- absolute and relative tolerances;
- elapsed-time limit;
- attempted and converged iteration counts;
- failure reason;
- branch identity;
- no interpolation/fabrication flag.

The phase-envelope tracer should:

1. Trace bubble and dew branches independently over a predefined temperature grid.
2. Use previous converged K-values and pressure as the next initial guess.
3. Reduce step size after failed convergence.
4. Increase step size cautiously after stable convergence.
5. Stop a branch after a defined consecutive-failure threshold.
6. Report gaps explicitly.
7. Treat the critical region as a separate termination condition, not as a forced branch closure.
8. Check cancellation between every solve and inside every iterative loop.

## Numerical Validation Plan

Use `Documentation/Feasibility/LocalPhaseDiagramNeqSimReferenceDataset.json` as the primary software-parity reference. Define tolerances before viewing results:

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

These are software-parity screening tolerances only. They are not experimental validation or engineering accuracy limits.

Comparison rules:

- match points by branch and nearest temperature, never by array index;
- report bubble and dew statistics separately;
- report mean, median, 95th percentile and maximum errors;
- exclude explicitly flagged critical-region points from aggregate pressure-error gates, but report them separately;
- keep failed local points as gaps.

## Required Tests Before Runtime PR Acceptance

- deterministic pure CO2 saturation trace;
- 97/3 and 90/10 CO2/N2 bubble/dew traces with finite points or explicit gaps;
- invalid, duplicate, non-normalized and non-finite composition rejection;
- branch separation and no fabricated critical closure;
- cancellation from Swift and native loop;
- repeated calculations without increasing memory;
- comparison against the NeqSim reference dataset;
- iPhone 17 simulator execution;
- physical-iPhone execution by manual validation.

## Measurements Required Before Runtime PR Acceptance

- total envelope latency;
- per-point latency;
- attempted and converged point counts;
- peak memory;
- cancellation response time;
- native library size;
- final app-size delta.

No runtime prototype is accepted in this branch because the CoolProp primitive gate failed and the native cubic-EOS implementation requires a separately pinned parameter source before scientific calculations can be produced.
