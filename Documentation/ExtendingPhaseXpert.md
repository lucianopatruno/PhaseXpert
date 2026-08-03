# Extending PhaseXpert

## Add a provider

1. Add a type conforming to `ThermodynamicModelProvider`.
2. Publish a complete `ModelDescriptor` with stable ID, versions, actual
   capabilities, scientific domain, limitations and real references.
3. Validate all request values and component combinations inside the provider;
   the UI validator is not a security or numerical boundary.
4. Return status for every requested property and complete solver metadata.
5. Implement `phaseEnvelope` or return an explicit unavailable response.
6. Register the provider in `ProviderRegistry` through dependency injection.
7. Add capability, reference-value, boundary, non-convergence and cancellation
   tests.
8. Add licence notices and Model Information content.
9. For a remote provider, add a versioned service contract, endpoint
   configuration, HTTPS requirements, structured error mapping, cancellation
   and stale-result tests, plus API documentation.

Never change the meaning of an existing provider ID or version after results
have been saved.

## Add a component

1. Add a stable `ComponentID` case and display symbol/name.
2. Add molecular weight only from a cited source if mass-fraction conversion is
   implemented.
3. Do not add it to a provider's `supportedComponents` until pure-fluid and
   required binary-pair capability is verified.
4. Document provider-specific composition and domain limits.
5. Add serialization, validation and numerical reference tests.
6. Add the component to UI selection only when at least one selectable
   scientific provider supports it, or label it as unavailable.
