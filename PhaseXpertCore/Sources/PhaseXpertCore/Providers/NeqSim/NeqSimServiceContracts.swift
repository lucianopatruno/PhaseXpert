import Foundation

public struct NeqSimCompositionEntry: Codable, Equatable, Sendable {
    public let component: String
    public let moleFraction: Double

    enum CodingKeys: String, CodingKey {
        case component
        case moleFraction = "mole_fraction"
    }

    public init(component: String, moleFraction: Double) {
        self.component = component
        self.moleFraction = moleFraction
    }
}

public struct NeqSimStateRequest: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let requestID: String
    public let pressurePa: Double
    public let temperatureK: Double
    public let composition: [NeqSimCompositionEntry]
    public let requestedProperties: [String]
    public let normalizeComposition: Bool
    public let clientVersion: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case requestID = "request_id"
        case pressurePa = "pressure_pa"
        case temperatureK = "temperature_k"
        case composition
        case requestedProperties = "requested_properties"
        case normalizeComposition = "normalize_composition"
        case clientVersion = "client_version"
    }

    public init(from request: CalculationRequest) {
        self.schemaVersion = NeqSimMetadata.apiSchemaVersion
        self.requestID = request.requestID.uuidString
        self.pressurePa = request.pressurePa
        self.temperatureK = request.temperatureK
        self.composition = request.composition.map {
            NeqSimCompositionEntry(component: $0.component.rawValue, moleFraction: $0.moleFraction)
        }
        self.requestedProperties = request.requestedProperties
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.rawValue)
        self.normalizeComposition = false
        self.clientVersion = request.clientVersion
    }
}

public struct NeqSimEnvelopeRequest: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let requestID: String
    public let composition: [NeqSimCompositionEntry]
    public let maximumPoints: Int
    public let timeoutSeconds: Double
    public let normalizeComposition: Bool

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case requestID = "request_id"
        case composition
        case maximumPoints = "maximum_points"
        case timeoutSeconds = "timeout_seconds"
        case normalizeComposition = "normalize_composition"
    }

    public init(from request: PhaseEnvelopeRequest) {
        self.schemaVersion = NeqSimMetadata.apiSchemaVersion
        self.requestID = request.requestID.uuidString
        self.composition = request.composition.map {
            NeqSimCompositionEntry(component: $0.component.rawValue, moleFraction: $0.moleFraction)
        }
        self.maximumPoints = 240
        self.timeoutSeconds = 20
        self.normalizeComposition = false
    }
}

public struct NeqSimProvenance: Codable, Equatable, Sendable {
    public let providerID: String
    public let providerCapabilityVersion: String
    public let serviceVersion: String
    public let apiSchemaVersion: String
    public let neqsimVersion: String
    public let neqsimSourceCommit: String
    public let javaRuntimeVersion: String
    public let eos: String
    public let alphaFunction: String
    public let mixingRule: String
    public let interactionData: String

    enum CodingKeys: String, CodingKey {
        case providerID = "provider_id"
        case providerCapabilityVersion = "provider_capability_version"
        case serviceVersion = "service_version"
        case apiSchemaVersion = "api_schema_version"
        case neqsimVersion = "neqsim_version"
        case neqsimSourceCommit = "neqsim_source_commit"
        case javaRuntimeVersion = "java_runtime_version"
        case eos
        case alphaFunction = "alpha_function"
        case mixingRule = "mixing_rule"
        case interactionData = "interaction_data"
    }

    public init(
        providerID: String = NeqSimMetadata.providerID,
        providerCapabilityVersion: String = NeqSimMetadata.capabilityVersion,
        serviceVersion: String = NeqSimMetadata.serviceVersion,
        apiSchemaVersion: String = NeqSimMetadata.apiSchemaVersion,
        neqsimVersion: String = NeqSimMetadata.releaseVersion,
        neqsimSourceCommit: String = NeqSimMetadata.sourceCommit,
        javaRuntimeVersion: String = "mock-java",
        eos: String = NeqSimMetadata.eos,
        alphaFunction: String = NeqSimMetadata.alphaFunction,
        mixingRule: String = NeqSimMetadata.mixingRule,
        interactionData: String = NeqSimMetadata.interactionData
    ) {
        self.providerID = providerID
        self.providerCapabilityVersion = providerCapabilityVersion
        self.serviceVersion = serviceVersion
        self.apiSchemaVersion = apiSchemaVersion
        self.neqsimVersion = neqsimVersion
        self.neqsimSourceCommit = neqsimSourceCommit
        self.javaRuntimeVersion = javaRuntimeVersion
        self.eos = eos
        self.alphaFunction = alphaFunction
        self.mixingRule = mixingRule
        self.interactionData = interactionData
    }
}

public struct NeqSimConvergenceMetadata: Codable, Equatable, Sendable {
    public let method: String
    public let converged: Bool
    public let iterationCount: Int?
    public let durationMilliseconds: Double
    public let status: String

    enum CodingKeys: String, CodingKey {
        case method
        case converged
        case iterationCount = "iteration_count"
        case durationMilliseconds = "duration_ms"
        case status
    }

    public init(
        method: String,
        converged: Bool,
        iterationCount: Int? = nil,
        durationMilliseconds: Double,
        status: String
    ) {
        self.method = method
        self.converged = converged
        self.iterationCount = iterationCount
        self.durationMilliseconds = durationMilliseconds
        self.status = status
    }
}

public struct NeqSimPropertyResult: Codable, Equatable, Sendable {
    public let property: String
    public let value: Double?
    public let unit: String
    public let status: String
    public let message: String?

    public init(
        property: String,
        value: Double?,
        unit: String,
        status: String,
        message: String? = nil
    ) {
        self.property = property
        self.value = value
        self.unit = unit
        self.status = status
        self.message = message
    }
}

public struct NeqSimStateResponse: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let requestID: String
    public let calculationID: String
    public let provenance: NeqSimProvenance
    public let pressurePa: Double
    public let temperatureK: Double
    public let composition: [NeqSimCompositionEntry]
    public let compositionBasis: String
    public let phase: String
    public let properties: [NeqSimPropertyResult]
    public let warnings: [String]
    public let convergence: NeqSimConvergenceMetadata

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case requestID = "request_id"
        case calculationID = "calculation_id"
        case provenance
        case pressurePa = "pressure_pa"
        case temperatureK = "temperature_k"
        case composition
        case compositionBasis = "composition_basis"
        case phase
        case properties
        case warnings
        case convergence
    }

    public init(
        schemaVersion: String = NeqSimMetadata.apiSchemaVersion,
        requestID: String,
        calculationID: String = UUID().uuidString,
        provenance: NeqSimProvenance = .init(),
        pressurePa: Double,
        temperatureK: Double,
        composition: [NeqSimCompositionEntry],
        compositionBasis: String = "mole_fraction",
        phase: String,
        properties: [NeqSimPropertyResult],
        warnings: [String],
        convergence: NeqSimConvergenceMetadata
    ) {
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.calculationID = calculationID
        self.provenance = provenance
        self.pressurePa = pressurePa
        self.temperatureK = temperatureK
        self.composition = composition
        self.compositionBasis = compositionBasis
        self.phase = phase
        self.properties = properties
        self.warnings = warnings
        self.convergence = convergence
    }
}

public struct NeqSimEnvelopePoint: Codable, Equatable, Sendable {
    public let temperatureK: Double
    public let pressurePa: Double
    public let branch: String

    enum CodingKeys: String, CodingKey {
        case temperatureK = "temperature_k"
        case pressurePa = "pressure_pa"
        case branch
    }

    public init(temperatureK: Double, pressurePa: Double, branch: String) {
        self.temperatureK = temperatureK
        self.pressurePa = pressurePa
        self.branch = branch
    }
}

public struct NeqSimEnvelopeResponse: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let requestID: String
    public let calculationID: String
    public let provenance: NeqSimProvenance
    public let points: [NeqSimEnvelopePoint]
    public let isAvailable: Bool
    public let isComplete: Bool
    public let warnings: [String]
    public let convergence: NeqSimConvergenceMetadata

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case requestID = "request_id"
        case calculationID = "calculation_id"
        case provenance
        case points
        case isAvailable = "is_available"
        case isComplete = "is_complete"
        case warnings
        case convergence
    }

    public init(
        schemaVersion: String = NeqSimMetadata.apiSchemaVersion,
        requestID: String,
        calculationID: String = UUID().uuidString,
        provenance: NeqSimProvenance = .init(),
        points: [NeqSimEnvelopePoint],
        isAvailable: Bool,
        isComplete: Bool,
        warnings: [String],
        convergence: NeqSimConvergenceMetadata
    ) {
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.calculationID = calculationID
        self.provenance = provenance
        self.points = points
        self.isAvailable = isAvailable
        self.isComplete = isComplete
        self.warnings = warnings
        self.convergence = convergence
    }
}
