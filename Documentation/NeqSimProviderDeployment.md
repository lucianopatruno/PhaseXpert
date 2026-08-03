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
uvicorn --app-dir src neqsim_provider.main:app --host localhost --port 8080
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

Set `PHASEXPERT_NEQSIM_ENDPOINT` for development or validation builds when a
non-default endpoint is needed. Debug iPhone Simulator builds default to
`http://localhost:8080`, which reaches a service running on the Mac. Release and
non-simulator builds do not inherit this HTTP endpoint and require explicit
HTTPS configuration.

Start the service:

```sh
cd Services/NeqSimProvider
. .venv/bin/activate
uvicorn --app-dir src neqsim_provider.main:app --host localhost --port 8080
```

Verify health:

```sh
curl http://localhost:8080/v1/health
```

Run PhaseXpert on an iPhone Simulator Debug destination. If the service is
running, the model picker shows `NeqSim Remote SRK — Preliminary`; if the
service is stopped, NeqSim calculations fail with a remote/offline provider
error and the app must not fall back to CoolProp. Stop the service with
`Control-C` in the terminal running `uvicorn`.

If the app still reports that no endpoint is configured, confirm that the build
is a Debug iPhone Simulator build, or set:

```sh
PHASEXPERT_NEQSIM_ENDPOINT=http://localhost:8080
```

## Operational Limits

The API contract carries requested timeout, iteration and point-count limits.
The current service applies request validation and point-count bounds; deployment
must still enforce process-level CPU, memory and request-time limits at the
container or orchestration layer. Cancellation support is client-side and
transport-level where the server/runtime can observe it.
