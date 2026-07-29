# IFE Model API contract

The source-of-truth Codable types are in
`PhaseXpertCore/Sources/PhaseXpertCore/API/IFEModelAPIContract.swift`.
Version 1 uses JSON over HTTPS and canonical SI input units.

## Request

| Field | Meaning |
|---|---|
| `schemaVersion` | Contract version, initially `1.0` |
| `requestID` | Client-generated UUID for idempotency and traceability |
| `modelID` | Stable model identifier |
| `requestedModelVersion` | Optional exact version constraint |
| `pressure` | `{value, unit}`; unit must be `Pa` |
| `temperature` | `{value, unit}`; unit must be `K` |
| `composition` | Stable component IDs and mole fractions |
| `requestedProperties` | Stable property identifiers |
| `phaseEnvelopeSettings` | Optional temperature bounds and maximum point count |
| `clientAppVersion` | App version/build identity |

## Response

The response echoes `requestID`, supplies an optional `calculationID`, has
`complete`, `partial`, or `failed` status, and returns model metadata,
status-bearing properties, phase-envelope points, solver metadata, warnings,
structured errors, server timestamp and API version.

The production contract must additionally define:

- a controlled error-code registry;
- any additional phase-envelope continuation and sampling settings;
- coefficient/resource versions and full provenance;
- model-version mismatch semantics;
- maximum payload sizes and rate-limit headers;
- canonical JSON examples and compatibility tests.

## Transport requirements

- TLS with normal platform trust evaluation; no certificate bypass.
- Ephemeral OAuth/OIDC access tokens obtained at runtime and stored in
  Keychain when persistence is necessary.
- No production secret in the app bundle.
- Explicit request/connect/resource timeouts and cooperative cancellation.
- Retry only idempotent requests after transient failures, with bounded
  exponential backoff and server `Retry-After` support.
- Validate content type, schema version, request ID, units, finite values,
  fractions, model identity and partial-result status before display.
- A network disclosure screen must show the exact scientific input sent.
