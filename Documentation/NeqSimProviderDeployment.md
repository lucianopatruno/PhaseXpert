# NeqSim Provider Deployment

PR23 keeps NeqSim outside the iOS app. NeqSim depends on a Java runtime and is
operated as a remote service so the iOS app can remain small, offline-capable
through CoolProp, and independent of server-only thermodynamic dependencies.

## Local Development

From `Services/NeqSimProvider`:

```sh
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
pytest
uvicorn neqsim_provider.main:app --host 127.0.0.1 --port 8080
```

The service requires a Java 21-compatible runtime for NeqSim `v3.16.0`.

## Container

The included Dockerfile uses Eclipse Temurin 21 and pinned Python dependencies:

```sh
docker build -t phasexpert-neqsim-provider:0.1.0 .
docker run --rm -p 8080:8080 phasexpert-neqsim-provider:0.1.0
```

The container image must be rebuilt and tested before any deployment. Docker was
not available in the local Xcode validation environment used for PR23, so
container build and container API validation remain pending until Docker is
available.

## iOS Configuration

Set `PHASEXPERT_NEQSIM_ENDPOINT` for development or validation builds. If the
variable is missing, the NeqSim provider is visible as unavailable and explains
that no endpoint is configured. Production endpoints must use HTTPS.

## Operational Limits

The API contract carries requested timeout, iteration and point-count limits.
The current service applies request validation and point-count bounds; deployment
must still enforce process-level CPU, memory and request-time limits at the
container or orchestration layer. Cancellation support is client-side and
transport-level where the server/runtime can observe it.

