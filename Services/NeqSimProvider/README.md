# PhaseXpert NeqSim Provider Service

This service is a development-only FastAPI wrapper around the pinned NeqSim
engine used by the PhaseXpert remote provider.

## Scientific Configuration

- NeqSim release: `v3.16.0`
- Source commit: `3af7b560525b57f2d3da2c803a08e2b41a8d7f5a`
- Licence: Apache-2.0
- EOS: `SystemSrkEos`
- Mixing rule: `classic`
- Interaction data: `src/main/resources/data/INTER.csv`, row `7452`,
  `CO2,nitrogen,Classic`, with shipped SRK/PR/PC-SAFT interaction columns.

This configuration is selected because the pinned source ships both CO2 and
nitrogen components, documents `SystemSrkEos`, `setMixingRule("classic")`,
`TPflash()`, bubble/dew flashes, and `calcPTphaseEnvelope()`, and includes a
CO2/nitrogen `Classic` interaction row. PhaseXpert does not override or invent
binary interaction parameters.

Successful execution is integration evidence only. It is not experimental
validation or an accuracy claim.

## Development

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
pytest
uvicorn neqsim_provider.main:app --host 127.0.0.1 --port 8080
```

## Docker

```bash
docker build -t phasexpert-neqsim-provider:0.1.0 .
docker run --rm -p 8080:8080 phasexpert-neqsim-provider:0.1.0
```

No production endpoint is hard-coded in PhaseXpert. Production deployments must
use HTTPS. Localhost HTTP is only for development and tests.
