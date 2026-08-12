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

Never change the meaning of an existing provider ID or version after results
have been saved.

For optional native providers, prefer the CoolProp/teqp pattern: commit the
small C ABI, Swift adapter, build script and provenance documentation, but keep
generated XCFrameworks ignored and conditionally linked through
`PhaseXpertCore/Package.swift`.

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
