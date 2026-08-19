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

    /// True only when a calculated property contains a finite numeric value
    /// that can safely be presented as a result.
    public var hasFiniteCalculatedValue: Bool {
        status == .calculated && value?.isFinite == true
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
    public let waterEquilibrium: CarbonDioxideWaterEquilibriumResult?

    public init(
        calculationID: UUID = UUID(),
        requestID: UUID,
        model: ModelDescriptor,
        calculatedAt: Date = Date(),
        phase: PhaseRegion,
        properties: [PropertyValue],
        solver: SolverMetadata,
        warnings: [String],
        isScientificResult: Bool,
        waterEquilibrium: CarbonDioxideWaterEquilibriumResult? = nil
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
        self.waterEquilibrium = waterEquilibrium
    }
}

/// A composition value exactly as entered by the user.
public struct CompositionInputSnapshot: Codable, Equatable, Sendable {
    public let component: ComponentID
    public let value: Double
    public let unit: CompositionUnit

    public init(component: ComponentID, value: Double, unit: CompositionUnit) {
        self.component = component
        self.value = value
        self.unit = unit
    }
}

/// Immutable operating-point and composition provenance for a calculation.
///
/// Display values are retained alongside SI values so a saved or exported
/// calculation never needs to reconstruct the user's original scientific input.
public struct CalculationInputSnapshot: Codable, Equatable, Sendable {
    public let pressureValue: Double
    public let pressureUnit: PressureUnit
    public let pressurePa: Double
    public let temperatureValue: Double
    public let temperatureUnit: TemperatureUnit
    public let temperatureK: Double
    public let originalComposition: [CompositionInputSnapshot]
    public let normalizedComposition: [MixtureComponent]?

    public init(
        pressureValue: Double,
        pressureUnit: PressureUnit,
        pressurePa: Double,
        temperatureValue: Double,
        temperatureUnit: TemperatureUnit,
        temperatureK: Double,
        originalComposition: [CompositionInputSnapshot],
        normalizedComposition: [MixtureComponent]? = nil
    ) {
        self.pressureValue = pressureValue
        self.pressureUnit = pressureUnit
        self.pressurePa = pressurePa
        self.temperatureValue = temperatureValue
        self.temperatureUnit = temperatureUnit
        self.temperatureK = temperatureK
        self.originalComposition = originalComposition
        self.normalizedComposition = normalizedComposition
    }

    public var pressureDisplayUnitLabel: String {
        switch pressureUnit {
        case .bara, .bar:
            "bar(a)"
        case .megapascal:
            "MPa(a)"
        case .psia:
            "psi(a)"
        default:
            pressureUnit.rawValue
        }
    }
}

/// App identity captured at calculation time rather than read back later.
public struct ApplicationIdentity: Codable, Equatable, Sendable {
    public let version: String
    public let build: String

    public init(version: String, build: String) {
        self.version = version
        self.build = build
    }
}

/// Complete immutable record used by results, persistence and future exports.
///
/// The response embeds its original model descriptor, ensuring model provenance
/// is retained even after PhaseXpert or a provider is updated.
public struct CalculationRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID { response.calculationID }
    public let request: CalculationRequest
    public let input: CalculationInputSnapshot
    public let response: CalculationResponse
    public let application: ApplicationIdentity

    public init(
        request: CalculationRequest,
        input: CalculationInputSnapshot,
        response: CalculationResponse,
        application: ApplicationIdentity
    ) {
        self.request = request
        self.input = input
        self.response = response
        self.application = application
    }
}
