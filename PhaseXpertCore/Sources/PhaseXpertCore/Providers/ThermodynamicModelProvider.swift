import Foundation

public enum CalculationMode: String, Codable, Equatable, Sendable {
    case local
    case remote
    case hybrid
}

public enum ModelAvailability: String, Codable, Equatable, Sendable {
    case available
    case preliminary
    case unavailable
}

public struct SourceReference: Codable, Equatable, Sendable {
    public let authors: String
    public let title: String
    public let year: Int
    public let doiOrURL: String?

    public init(authors: String, title: String, year: Int, doiOrURL: String? = nil) {
        self.authors = authors
        self.title = title
        self.year = year
        self.doiOrURL = doiOrURL
    }
}

public struct ModelDescriptor: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let modelVersion: String
    public let providerVersion: String
    public let availability: ModelAvailability
    public let calculationMode: CalculationMode
    public let supportedComponents: Set<ComponentID>
    public let supportedProperties: Set<PropertyID>
    public let domain: ScientificDomain
    public let scientificBasis: String
    public let equationOrMethod: String
    public let coefficientSetVersion: String?
    public let requiredResources: [String]
    public let limitations: [String]
    public let references: [SourceReference]

    public init(
        id: String,
        name: String,
        modelVersion: String,
        providerVersion: String,
        availability: ModelAvailability,
        calculationMode: CalculationMode,
        supportedComponents: Set<ComponentID>,
        supportedProperties: Set<PropertyID>,
        domain: ScientificDomain,
        scientificBasis: String,
        equationOrMethod: String,
        coefficientSetVersion: String? = nil,
        requiredResources: [String] = [],
        limitations: [String],
        references: [SourceReference]
    ) {
        self.id = id
        self.name = name
        self.modelVersion = modelVersion
        self.providerVersion = providerVersion
        self.availability = availability
        self.calculationMode = calculationMode
        self.supportedComponents = supportedComponents
        self.supportedProperties = supportedProperties
        self.domain = domain
        self.scientificBasis = scientificBasis
        self.equationOrMethod = equationOrMethod
        self.coefficientSetVersion = coefficientSetVersion
        self.requiredResources = requiredResources
        self.limitations = limitations
        self.references = references
    }
}

public struct PhaseEnvelopeRequest: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let modelID: String
    public let composition: [MixtureComponent]

    public init(requestID: UUID = UUID(), modelID: String, composition: [MixtureComponent]) {
        self.requestID = requestID
        self.modelID = modelID
        self.composition = composition
    }
}

public struct PhaseEnvelopePoint: Codable, Equatable, Sendable {
    public enum Branch: String, Codable, Equatable, Sendable {
        case bubble
        case dew
        case critical
    }

    public let temperatureK: Double
    public let pressurePa: Double
    public let branch: Branch

    public init(temperatureK: Double, pressurePa: Double, branch: Branch) {
        self.temperatureK = temperatureK
        self.pressurePa = pressurePa
        self.branch = branch
    }
}

public struct PhaseEnvelopeResponse: Codable, Equatable, Sendable {
    public enum BoundaryKind: String, Codable, Equatable, Sendable {
        case pureFluidSaturation
        case mixtureEnvelope
    }

    public let requestID: UUID
    public let points: [PhaseEnvelopePoint]
    public let warnings: [String]
    public let isAvailable: Bool
    public let boundaryKind: BoundaryKind?
    public let model: ModelDescriptor?
    public let generatedAt: Date?
    public let solver: SolverMetadata?

    public init(
        requestID: UUID,
        points: [PhaseEnvelopePoint],
        warnings: [String],
        isAvailable: Bool,
        boundaryKind: BoundaryKind? = nil,
        model: ModelDescriptor? = nil,
        generatedAt: Date? = nil,
        solver: SolverMetadata? = nil
    ) {
        self.requestID = requestID
        self.points = points
        self.warnings = warnings
        self.isAvailable = isAvailable
        self.boundaryKind = boundaryKind
        self.model = model
        self.generatedAt = generatedAt
        self.solver = solver
    }
}

public protocol ThermodynamicModelProvider: Sendable {
    var descriptor: ModelDescriptor { get }
    func applicabilityIssues(for composition: [MixtureComponent]) -> [ValidationIssue]
    func operatingRangeGuidance(
        for context: OperatingGuidanceContext
    ) -> OperatingRangeGuidance?
    func calculate(_ request: CalculationRequest) async throws -> CalculationResponse
    func phaseEnvelope(_ request: PhaseEnvelopeRequest) async throws -> PhaseEnvelopeResponse
}

public extension ThermodynamicModelProvider {
    /// Provider-specific applicability checks that supplement shared input validation.
    ///
    /// Providers should report documented composition restrictions here so the
    /// calculator can block an unsupported request before model execution.
    func applicabilityIssues(for composition: [MixtureComponent]) -> [ValidationIssue] {
        []
    }

    func operatingRangeGuidance(
        for context: OperatingGuidanceContext
    ) -> OperatingRangeGuidance? {
        nil
    }
}

public enum ProviderError: Error, Equatable, Sendable {
    case modelUnavailable(String)
    case invalidRequest(String)
    case unsupportedComponent(ComponentID)
    case timeout
    case cancelled
    case malformedResponse(String)
}
