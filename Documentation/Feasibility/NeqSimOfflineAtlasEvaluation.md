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

## Offline Execution

The generator runs NeqSim in-process through JPype with one or more warm JVM worker subprocesses. It does not start an HTTP server and does not call the previous FastAPI service. The inspected PhaseXpert NeqSim provider code contains no telemetry or remote thermodynamic call path. A hard OS-level network block was not available in this environment, so offline behaviour was verified by implementation shape and source inspection rather than by a firewall-enforced run.

Each envelope request has a hard parent-process deadline, one bounded retry, and worker restart after timeout. The completed campaign had zero timeouts, zero retries, and zero worker restarts. The runner explicitly stopped and waited for its worker subprocesses; an OS-level process scan was sandbox-blocked in this environment.

## Composition Matrix

The main engineering-range matrix uses `xN2 = 0.00000, 0.00125, 0.00250, ..., 0.10000`, for 81 reference compositions. The near-pure supplement includes 10, 50, 100, 500, 1000, and 5000 ppm N2. The 5000 ppm case overlaps the main matrix, so the committed prototype contains 86 unique generated compositions.

Candidate interpolation grids are fixed before validation:

- 1.0 percentage point: 11 nodes
- 0.5 percentage point: 21 nodes
- 0.25 percentage point: 41 nodes

## Results

All 86 unique envelopes converged with finite phase-boundary output and critical-point outputs. The 10 ppm near-pure case returned no accepted bubble points, which is preserved explicitly rather than filled. The normalized scientific JSON is byte-for-byte deterministic across two complete generation and validation runs.

Direct interpolation of pressure at common temperatures reproduced 100% of eligible overlapping non-critical reference coverage and produced zero false gap connections, zero branch swaps, and zero invalid accepted points. It failed the scientific error thresholds:

- 1.0% grid bubble max relative pressure error `39.364235244568`, p95 `0.364850241638`; dew max `0.123864007224`, p95 `0.003066036289`
- 0.5% grid bubble max `33.741384370093`, p95 `0.194139430477`; dew max `0.07279290033`, p95 `0.001504827984`
- 0.25% grid bubble max `42.332306131024`, p95 `0.18519351611`; dew max `0.292115746715`, p95 `0.000892874289`

Critical interpolation also failed: maximum critical temperature errors were `102.755543711983 K`, `88.061118026411 K`, and `58.707541079803 K` for the 1.0%, 0.5%, and 0.25% grids respectively.

A branch-aligned normalized-coordinate alternative was assessed after direct interpolation failed. It was rejected because it also exceeded the pressure-error gate.

## Performance And Scaling

The final complete campaign generated 86 envelopes in `1.695978 s` after worker startup, with mean per-envelope NeqSim generation time `0.014135726 s`, median `0.005943417 s`, p95 `0.013403125 s`, and max `0.621248292 s`. The 24-composition scaling sample measured `1.106487 s` with one worker, `1.754539 s` with two workers, `3.45302 s` with four workers, and `6.204907 s` with eight workers, so this small workload is startup-bound and does not benefit from more workers.

The deterministic scientific JSON for 86 envelopes is `609643` bytes uncompressed and `149463` bytes gzip-compressed. Extrapolated linearly to 43,758 envelopes, the estimated size is about `310194865` bytes uncompressed and `76048859` bytes compressed. Lazy or indexed loading would be needed for a full atlas.

## Classification

Interpolation fails the scientific gate.

The full atlas was not generated. The minimal Apple-consumption gate was not reached because the scientific interpolation gate failed.
