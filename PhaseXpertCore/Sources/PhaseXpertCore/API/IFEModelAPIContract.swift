import Foundation

public struct APIQuantityV1: Codable, Equatable, Sendable {
    public let value: Double
    public let unit: String

    public init(value: Double, unit: String) {
        self.value = value
        self.unit = unit
    }
}

public struct PhaseEnvelopeSettingsV1: Codable, Equatable, Sendable {
    public let minimumTemperatureK: Double?
    public let maximumTemperatureK: Double?
    public let maximumPointCount: Int

    public init(
        minimumTemperatureK: Double? = nil,
        maximumTemperatureK: Double? = nil,
        maximumPointCount: Int = 200
    ) {
        self.minimumTemperatureK = minimumTemperatureK
        self.maximumTemperatureK = maximumTemperatureK
        self.maximumPointCount = maximumPointCount
    }
}

public struct IFECalculationRequestV1: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let requestID: UUID
    public let modelID: String
    public let requestedModelVersion: String?
    public let pressure: APIQuantityV1
    public let temperature: APIQuantityV1
    public let composition: [MixtureComponent]
    public let requestedProperties: Set<PropertyID>
    public let phaseEnvelopeSettings: PhaseEnvelopeSettingsV1?
    public let clientAppVersion: String

    public init(
        requestID: UUID = UUID(),
        modelID: String,
        requestedModelVersion: String? = nil,
        pressurePa: Double,
        temperatureK: Double,
        composition: [MixtureComponent],
        requestedProperties: Set<PropertyID>,
        phaseEnvelopeSettings: PhaseEnvelopeSettingsV1? = nil,
        clientAppVersion: String
    ) {
        self.schemaVersion = "1.0"
        self.requestID = requestID
        self.modelID = modelID
        self.requestedModelVersion = requestedModelVersion
        self.pressure = APIQuantityV1(value: pressurePa, unit: "Pa")
        self.temperature = APIQuantityV1(value: temperatureK, unit: "K")
        self.composition = composition
        self.requestedProperties = requestedProperties
        self.phaseEnvelopeSettings = phaseEnvelopeSettings
        self.clientAppVersion = clientAppVersion
    }
}

public enum IFEResponseStatusV1: String, Codable, Equatable, Sendable {
    case complete
    case partial
    case failed
}

public struct IFEStructuredErrorV1: Codable, Equatable, Sendable {
    public let code: String
    public let message: String
    public let retryable: Bool

    public init(code: String, message: String, retryable: Bool) {
        self.code = code
        self.message = message
        self.retryable = retryable
    }
}

public struct IFECalculationResponseV1: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let requestID: UUID
    public let calculationID: UUID?
    public let status: IFEResponseStatusV1
    public let model: ModelDescriptor?
    public let phase: PhaseRegion?
    public let properties: [PropertyValue]
    public let phaseEnvelope: [PhaseEnvelopePoint]
    public let solver: SolverMetadata?
    public let warnings: [String]
    public let errors: [IFEStructuredErrorV1]
    public let serverCalculationTimestamp: Date?
    public let serverAPIVersion: String

    public init(
        requestID: UUID,
        calculationID: UUID?,
        status: IFEResponseStatusV1,
        model: ModelDescriptor?,
        phase: PhaseRegion?,
        properties: [PropertyValue],
        phaseEnvelope: [PhaseEnvelopePoint],
        solver: SolverMetadata?,
        warnings: [String],
        errors: [IFEStructuredErrorV1],
        serverCalculationTimestamp: Date?,
        serverAPIVersion: String
    ) {
        self.schemaVersion = "1.0"
        self.requestID = requestID
        self.calculationID = calculationID
        self.status = status
        self.model = model
        self.phase = phase
        self.properties = properties
        self.phaseEnvelope = phaseEnvelope
        self.solver = solver
        self.warnings = warnings
        self.errors = errors
        self.serverCalculationTimestamp = serverCalculationTimestamp
        self.serverAPIVersion = serverAPIVersion
    }
}

public protocol IFEAPIClient: Sendable {
    func calculate(_ request: IFECalculationRequestV1) async throws -> IFECalculationResponseV1
}

public protocol AuthenticationTokenProvider: Sendable {
    func validAccessToken() async throws -> String
}
