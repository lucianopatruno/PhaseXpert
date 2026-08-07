# NeqSim Offline Atlas Feasibility

This milestone evaluates whether a small precomputed NeqSim CO2/N2 phase-envelope atlas plus interpolation can replace an on-device phase-equilibrium solver. It does not generate the full atlas and does not modify production providers, Swift UI, or the Xcode project.

## Provenance

- NeqSim release: `3.16.0`
- NeqSim source tag: `v3.16.0`
- NeqSim source commit: `3af7b560525b57f2d3da2c803a08e2b41a8d7f5a`
- Python package: `neqsim==3.16.0`
- Python dependencies used in the local `/tmp` virtualenv: `jpype1==1.7.1`, `numpy==2.5.1`, `pandas==3.0.5`, `packaging==26.3`, `python-dateutil==2.9.0.post0`, `six==1.17.0`
- Java runtime used for generation: Eclipse Temurin JRE `21.0.12+8`, installed under `/tmp`
- EOS: `SystemSrkEos`
- Mixing rule: `classic`
- Operation: `ThermodynamicOperations.calcPTphaseEnvelope`
- Interaction data: `src/main/resources/data/INTER.csv`, row `7452`, `CO2,nitrogen,Classic`

The pinned NeqSim row contains `KIJSRK = -0.0171`, `KIJTSRK = 0`, `KIJTType = 0`, `KIJPR = -0.019997`, `KIJTPR = 0`, and `KIJPCSAFT = -0.017`. PhaseXpert does not override or tune these parameters.

NeqSim is Apache-2.0. `numpy` and `pandas` are BSD-3-Clause, `python-dateutil` is dual Apache-2.0/BSD, `six` is MIT, and the local Eclipse Temurin JRE is GPLv2 with the Classpath Exception. `jpype1`, `packaging`, NeqSim's bundled parameter data, and generated-data redistribution need legal review before production distribution. This milestone does not treat the software licence as automatic proof that a generated iOS atlas can be redistributed without review.

## Failure Audit

The original direct interpolation failed for physical-topology reasons, not because of a pressure-unit or relative-error implementation defect. NeqSim returns pressure in bara and the generator stores Pa by multiplying by `100000`; reported relative errors are fractions, not percentages. `ThermodynamicOperations.calcPTphaseEnvelope()` constructs `PTPhaseEnvelopeMichelsen`; `bubT/bubP` and `dewT/dewP` are NeqSim branch arrays with NaN break sentinels, so branch labels are sourced from NeqSim rather than inferred from plotting order. `criticalPoint1` is distinct from `cricondentherm` and `cricondenbar`; in the Michelsen implementation it returns the first traced critical point when present or a fallback `{system.getTC(), system.getPC()}`. In this CO2/N2 matrix the field is not consistently attached to compatible bubble/dew topology for pure and very-low-N2 mixtures, so critical interpolation must be treated as conditional rather than forced.

The largest baseline pressure errors are low-temperature bubble-endpoint mismatches where bracketing envelopes have different endpoint temperatures and pressure varies rapidly at small absolute pressure. Examples from the 0.25%, 0.5%, and 1.0% grids respectively are `xN2=0.04125` at `57.623258 K`, reference `134985.880758 Pa`, interpolated `5849249.508372 Pa`, relative error `42.332306131024`; `xN2=0.06125` at `57.878107 K`, reference `166320.352975 Pa`, interpolated `5778199.311274 Pa`, relative error `33.741384370093`; and `xN2=0.06125` at `57.878107 K`, reference `166320.352975 Pa`, interpolated `6713393.853442 Pa`, relative error `39.364235244568`. The largest prior critical-temperature errors came from interpolating across pure CO2 and early N2 brackets: `102.755543711983 K` for the 1.0% grid, `88.061118026411 K` for the 0.5% grid, and `58.707541079803 K` for the 0.25% grid.

## Topology Methods

The frozen topology configuration checksum is `2fbbfb877fdb29c3931b00f95196abaddd240e99834387f99cc4c9997b40363c`. Each branch is split into explicit continuous segments from NeqSim's NaN-delimited output. Segment signatures include branch identity, critical attachment, detached-step detection, temperature direction, pressure direction, and pressure turning-point count. Interpolation is refused when neighboring atlas segments and the reference segment do not have compatible signatures. The 10 ppm case remains without a bubble branch.

Two predetermined topology-aligned methods were evaluated. Method A is endpoint-aligned reduced temperature with separately interpolated endpoint landmarks and `log(P)` interpolation. Method B is normalized arc length in normalized temperature and `log(P)` space. Both methods use only the two bracketing atlas compositions and reject endpoint/critical portions inside the predefined `0.03` branch-coordinate exclusion.

## Composition Matrix

The development matrix remains the 81 engineering-range compositions `xN2 = 0.00000, 0.00125, 0.00250, ..., 0.10000` plus 10, 50, 100, 500, 1000, and 5000 ppm N2, for 86 unique generated references. The locked validation set was generated only after the topology algorithm was frozen and contains 45 envelopes: `xN2 = 0.000625 + 0.0025 * k`, `k = 0...39`, plus 25, 75, 250, 750, and 2500 ppm N2.

## Locked Results

No method/grid passed. All locked topology-aligned results had zero false connections, zero branch swaps, and zero invalid accepted values, but reproduced coverage was far below the required 95% because topology incompatibility was explicitly refused. Method A was the better pressure method among accepted points, but it still failed the bubble pressure gate and coverage gate. Locked Method A results were:

- 1.0% grid: bubble coverage `0.070427127486`, p95 relative error fraction `0.063353139956`, max `0.132661047472`; dew coverage `0.573913043478`, p95 `0.000093234117`, max `0.143136749668`; critical comparisons `4`, unsupported critical cases `40`, max critical temperature error `0.001514295711 K`
- 0.5% grid: bubble coverage `0.071405282035`, p95 `0.065759739076`, max `0.123690274566`; dew coverage `0.573913043478`, p95 `0.00004120952`, max `0.000362865171`; critical comparisons `4`, unsupported critical cases `40`, max critical temperature error `0.00036665414 K`
- 0.25% grid: bubble coverage `0.107697390155`, p95 `0.072944026472`, max `0.199726518479`; dew coverage `0.623330365093`, p95 `0.000016462886`, max `0.000876469948`; critical comparisons `7`, unsupported critical cases `36`, max critical temperature error `0.00148630084 K`

Locked Method B performed worse on accepted pressure points: bubble p95 relative error fractions were `0.652076366117`, `0.6605222334`, and `0.629880994858` for the 1.0%, 0.5%, and 0.25% grids; dew p95 values were `0.234637644073`, `0.233454177917`, and `0.234634674627`.

Development-set topology validation showed the same pattern: Method A bubble coverage ranged from `0.070921985816` to `0.101418439716`, dew coverage from `0.648148148148` to `0.673934588702`, and accepted bubble p95 relative errors remained `0.045668087283` to `0.063463751385`. Method B remained much less accurate.

## Performance And Scaling

The final v2 campaign generated the 86 development envelopes in `1.355352 s` and the 45 locked envelopes in `1.133407 s`, with zero timeouts, zero retries, and zero worker restarts. The runner explicitly stopped and waited for its worker subprocesses; an OS-level process scan was sandbox-blocked in this environment. The deterministic scientific JSON is byte-for-byte reproducible across complete regenerated reports.

The v2 scientific JSON is `1131334` bytes uncompressed and `159446` bytes gzip-compressed for the 86-reference atlas plus topology diagnostics. The locked-reference increment is `587792` bytes uncompressed and `84306` bytes gzip-compressed. The updated linear full-atlas estimate is `575638525` bytes uncompressed and `81128349` bytes compressed, so lazy or indexed loading would be required for any full atlas. Lookup estimates remain `0.00008 s` single and `0.0065 s` for an 81-holdout batch. Memory was not safely measured.

## Classification

NeqSim's envelope topology is too unstable for reliable general interpolation.

The full atlas was not generated. The minimal Apple-consumption gate was not reached because the locked scientific gate failed.
