import Foundation

public struct ProviderRegistry: Sendable {
    public let providers: [any ThermodynamicModelProvider]

    public init(providers: [any ThermodynamicModelProvider] = ProviderRegistry.defaults) {
        self.providers = providers
    }

    public var descriptors: [ModelDescriptor] {
        providers.map(\.descriptor)
    }

    public func provider(id: String) -> (any ThermodynamicModelProvider)? {
        providers.first { $0.descriptor.id == id }
    }

    public static var defaults: [any ThermodynamicModelProvider] {
        [
            ArchitectureDemoProvider(),
            UnavailableModelProvider.coolProp,
            UnavailableModelProvider.ife
        ]
    }
}

/// Exercises orchestration only. It never returns thermophysical values.
public struct ArchitectureDemoProvider: ThermodynamicModelProvider {
    public let descriptor = ModelDescriptor(
        id: "architecture-demo",
        name: "Architecture Demo — Non-scientific",
        modelVersion: "0",
        providerVersion: "0.1.0",
        availability: .available,
        calculationMode: .local,
        supportedComponents: Set(ComponentID.allCases),
        supportedProperties: [],
        domain: .initialCO2Transport,
        scientificBasis: "No thermodynamic formulation. This provider verifies application workflow only.",
        equationOrMethod: "No calculation",
        limitations: ["Returns no scientific property values.", "Must never be used for engineering decisions."],
        references: []
    )

    public init() {}

    public func calculate(_ request: CalculationRequest) async throws -> CalculationResponse {
        try Task.checkCancellation()
        return CalculationResponse(
            requestID: request.requestID,
            model: descriptor,
            phase: .unavailable,
            properties: request.requestedProperties.map {
                PropertyValue(
                    property: $0,
                    value: nil,
                    unit: "",
                    status: .unavailable,
                    message: "No scientific engine is connected."
                )
            },
            solver: SolverMetadata(
                method: "No calculation",
                converged: false,
                durationMilliseconds: 0
            ),
            warnings: [
                "NON-SCIENTIFIC DEMONSTRATION: no thermophysical calculation was performed."
            ],
            isScientificResult: false
        )
    }

    public func phaseEnvelope(_ request: PhaseEnvelopeRequest) async throws -> PhaseEnvelopeResponse {
        PhaseEnvelopeResponse(
            requestID: request.requestID,
            points: [],
            warnings: ["Phase envelope unavailable: no scientific engine is connected."],
            isAvailable: false
        )
    }
}

public struct UnavailableModelProvider: ThermodynamicModelProvider {
    public let descriptor: ModelDescriptor

    public init(descriptor: ModelDescriptor) {
        self.descriptor = descriptor
    }

    public func calculate(_ request: CalculationRequest) async throws -> CalculationResponse {
        throw ProviderError.modelUnavailable("\(descriptor.name) is not yet connected.")
    }

    public func phaseEnvelope(_ request: PhaseEnvelopeRequest) async throws -> PhaseEnvelopeResponse {
        throw ProviderError.modelUnavailable("\(descriptor.name) cannot generate a phase envelope.")
    }

    public static let coolProp = UnavailableModelProvider(descriptor: ModelDescriptor(
        id: "coolprop-heos",
        name: "CoolProp HEOS — Validation pending",
        modelVersion: "Not integrated",
        providerVersion: "0.1.0",
        availability: .unavailable,
        calculationMode: .local,
        supportedComponents: [],
        supportedProperties: [],
        domain: .initialCO2Transport,
        scientificBasis: "Planned local CoolProp HEOS integration. No CoolProp code is present in this milestone.",
        equationOrMethod: "CoolProp HEOS backend (planned; not integrated)",
        limitations: [
            "No calculations are currently available.",
            "Component combinations will be restricted after binary-pair and reference validation."
        ],
        references: [
            SourceReference(
                authors: "Bell, Wronski, Quoilin and Lemort",
                title: "Pure and Pseudo-pure Fluid Thermophysical Property Evaluation and the Open-Source Thermophysical Property Library CoolProp",
                year: 2014,
                doiOrURL: "https://doi.org/10.1021/ie4033999"
            )
        ]
    ))

    public static let ife = UnavailableModelProvider(descriptor: ModelDescriptor(
        id: "ife-model",
        name: "IFE Model — Not available",
        modelVersion: "Not supplied",
        providerVersion: "0.1.0",
        availability: .unavailable,
        calculationMode: .hybrid,
        supportedComponents: [],
        supportedProperties: [],
        domain: .initialCO2Transport,
        scientificBasis: "Provider interface reserved for a validated IFE implementation.",
        equationOrMethod: "Not supplied",
        limitations: ["Scientific formulation, coefficients, validity limits, and execution mode have not been supplied."],
        references: []
    ))
}
