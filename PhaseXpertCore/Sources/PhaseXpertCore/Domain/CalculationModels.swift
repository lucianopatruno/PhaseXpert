import Foundation

public struct CalculationRequest: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let modelID: String
    public let pressurePa: Double
    public let temperatureK: Double
    public let composition: [MixtureComponent]
    public let requestedProperties: Set<PropertyID>
    public let clientVersion: String

    public init(
        requestID: UUID = UUID(),
        modelID: String,
        pressurePa: Double,
        temperatureK: Double,
        composition: [MixtureComponent],
        requestedProperties: Set<PropertyID> = Set(PropertyID.allCases),
        clientVersion: String
    ) {
        self.requestID = requestID
        self.modelID = modelID
        self.pressurePa = pressurePa
        self.temperatureK = temperatureK
        self.composition = composition
        self.requestedProperties = requestedProperties
        self.clientVersion = clientVersion
    }
}

public enum PropertyID: String, CaseIterable, Codable, Hashable, Sendable {
    case density
    case dynamicViscosity
    case molarMass
    case compressibilityFactor
    case specificVolume
    case enthalpy
    case entropy
    case internalEnergy
    case isobaricHeatCapacity
    case isochoricHeatCapacity
    case heatCapacityRatio
    case speedOfSound
    case thermalConductivity
    case jouleThomsonCoefficient
    case isothermalCompressibility
    case thermalExpansionCoefficient
    case vapourFraction
}

public enum PropertyStatus: String, Codable, Equatable, Sendable {
    case calculated
    case unavailable
    case outsideValidatedRange
    case extrapolated
    case failed
}

public struct PropertyValue: Codable, Equatable, Sendable {
    public let property: PropertyID
    public let value: Double?
    public let unit: String
    public let status: PropertyStatus
    public let message: String?

    public init(
        property: PropertyID,
        value: Double?,
        unit: String,
        status: PropertyStatus,
        message: String? = nil
    ) {
        self.property = property
        self.value = value
        self.unit = unit
        self.status = status
        self.message = message
    }
}

public enum PhaseRegion: String, Codable, Equatable, Sendable {
    case gas
    case liquid
    case dense
    case supercritical
    case twoPhase
    case solid
    case unknown
    case unavailable
}

public struct SolverMetadata: Codable, Equatable, Sendable {
    public let method: String
    public let converged: Bool
    public let iterationCount: Int?
    public let absoluteTolerance: Double?
    public let relativeTolerance: Double?
    public let durationMilliseconds: Double

    public init(
        method: String,
        converged: Bool,
        iterationCount: Int? = nil,
        absoluteTolerance: Double? = nil,
        relativeTolerance: Double? = nil,
        durationMilliseconds: Double
    ) {
        self.method = method
        self.converged = converged
        self.iterationCount = iterationCount
        self.absoluteTolerance = absoluteTolerance
        self.relativeTolerance = relativeTolerance
        self.durationMilliseconds = durationMilliseconds
    }
}

public struct CalculationResponse: Codable, Equatable, Sendable {
    public let calculationID: UUID
    public let requestID: UUID
    public let model: ModelDescriptor
    public let calculatedAt: Date
    public let phase: PhaseRegion
    public let properties: [PropertyValue]
    public let solver: SolverMetadata
    public let warnings: [String]
    public let isScientificResult: Bool

    public init(
        calculationID: UUID = UUID(),
        requestID: UUID,
        model: ModelDescriptor,
        calculatedAt: Date = Date(),
        phase: PhaseRegion,
        properties: [PropertyValue],
        solver: SolverMetadata,
        warnings: [String],
        isScientificResult: Bool
    ) {
        self.calculationID = calculationID
        self.requestID = requestID
        self.model = model
        self.calculatedAt = calculatedAt
        self.phase = phase
        self.properties = properties
        self.solver = solver
        self.warnings = warnings
        self.isScientificResult = isScientificResult
    }
}
