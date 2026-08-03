# NeqSim Provider API

PR23 adds a development service contract for the standalone remote NeqSim
provider. The service lives in `Services/NeqSimProvider` and exposes a versioned
JSON API under `/v1`.

## Pinned Scientific Configuration

- NeqSim release: `v3.16.0`
- NeqSim source commit: `3af7b560525b57f2d3da2c803a08e2b41a8d7f5a`
- Licence: Apache-2.0
- EOS: `SystemSrkEos`
- Mixing rule: `classic`
- Interaction-data identifier:
  `neqsim-v3.16.0:src/main/resources/data/INTER.csv:7452:CO2-nitrogen:Classic`

The pinned source documents `SystemSrkEos`, `setMixingRule("classic")`,
`TPflash()` and `calcPTphaseEnvelope()`, and ships a CO2/nitrogen `Classic`
interaction row. PhaseXpert does not override or invent binary interaction
parameters.

## Endpoints

`GET /v1/health` returns provider identity, capability version, schema version,
model configuration, interaction-data provenance and service runtime metadata.

`POST /v1/state` accepts pressure in Pa, temperature in K, a mole-fraction
composition and requested property IDs. It returns one calculation ID, the
provider provenance, phase, property values with SI units, availability status,
warnings and convergence metadata.

`POST /v1/phase-envelope` accepts a mole-fraction composition and bounded
calculation limits. It returns finite provider points only, with explicit
`bubble`, `dew` or `critical` branch identity where NeqSim exposes those series.

## Error Handling

The service rejects unsupported components, duplicates, negative values,
non-finite values, malformed compositions and non-normalized mole fractions
before calling NeqSim. NeqSim execution failures are returned as structured
provider errors with request and calculation IDs. Stack traces, secrets and
internal paths must not be returned to clients.

## Transport

Production communication must use HTTPS. The iOS client permits `http://` only
for `localhost` and `127.0.0.1` development endpoints. PhaseXpert never commits a
public endpoint, private endpoint, credential or token.

