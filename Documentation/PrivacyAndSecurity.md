# Privacy and Security

PhaseXpert keeps saved cases local to the device. The privacy manifest declares
no tracking and no collected data.

## Remote NeqSim Provider

The NeqSim provider is disabled unless `PHASEXPERT_NEQSIM_ENDPOINT` is
configured. When used, the app sends the calculation input needed by the remote
provider: pressure, temperature, composition, requested properties and phase
diagram limits. The service returns provider results, calculation IDs,
provenance, warnings and convergence metadata.

Do not include personal data, credentials, internal IFE addresses or project
secrets in saved cases, notes, endpoints or exported reports. Production traffic
must use HTTPS. Localhost HTTP is only accepted for development and tests.

The NeqSim service must not expose stack traces, secrets or internal file paths.
Unavailable, unsupported, non-finite, incomplete and failed results must remain
explicit in API responses and exports.

