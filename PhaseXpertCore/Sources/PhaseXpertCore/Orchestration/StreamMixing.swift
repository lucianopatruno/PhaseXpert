import Foundation

public enum StreamFlowBasis: String, Codable, Equatable, Sendable, CaseIterable, Identifiable {
    case mass
    case molar

    public var id: String { rawValue }
}

public enum StreamFlowUnit: String, Codable, Equatable, Sendable, CaseIterable, Identifiable {
    case kilogramsPerSecond = "kg/s"
    case kilogramsPerHour = "kg/h"
    case tonnesPerHour = "t/h"
    case molesPerSecond = "mol/s"
    case kilomolesPerHour = "kmol/h"

    public var id: String { rawValue }

    public var basis: StreamFlowBasis {
        switch self {
        case .kilogramsPerSecond, .kilogramsPerHour, .tonnesPerHour:
            .mass
        case .molesPerSecond, .kilomolesPerHour:
            .molar
        }
    }

    public func kilogramsPerSecond(from value: Double) -> Double? {
        guard basis == .mass else { return nil }
        switch self {
        case .kilogramsPerSecond:
            return value
        case .kilogramsPerHour:
            return value / 3_600
        case .tonnesPerHour:
            return value * 1_000 / 3_600
        case .molesPerSecond, .kilomolesPerHour:
            return nil
        }
    }

    public func displayMassFlow(fromKilogramsPerSecond value: Double) -> Double? {
        guard basis == .mass else { return nil }
        switch self {
        case .kilogramsPerSecond:
            return value
        case .kilogramsPerHour:
            return value * 3_600
        case .tonnesPerHour:
            return value * 3_600 / 1_000
        case .molesPerSecond, .kilomolesPerHour:
            return nil
        }
    }

    public func molesPerSecond(from value: Double) -> Double? {
        guard basis == .molar else { return nil }
        switch self {
        case .molesPerSecond:
            return value
        case .kilomolesPerHour:
            return value * 1_000 / 3_600
        case .kilogramsPerSecond, .kilogramsPerHour, .tonnesPerHour:
            return nil
        }
    }

    public func displayMolarFlow(fromMolesPerSecond value: Double) -> Double? {
        guard basis == .molar else { return nil }
        switch self {
        case .molesPerSecond:
            return value
        case .kilomolesPerHour:
            return value * 3_600 / 1_000
        case .kilogramsPerSecond, .kilogramsPerHour, .tonnesPerHour:
            return nil
        }
    }
}

public struct StreamMixingOutletConditionInput: Codable, Equatable, Sendable {
    public let pressureValue: Double
    public let pressureUnit: PressureUnit
    public let pressurePa: Double
    public let temperatureValue: Double
    public let temperatureUnit: TemperatureUnit
    public let temperatureK: Double

    public init(
        pressureValue: Double,
        pressureUnit: PressureUnit,
        temperatureValue: Double,
        temperatureUnit: TemperatureUnit
    ) {
        self.pressureValue = pressureValue
        self.pressureUnit = pressureUnit
        self.pressurePa = pressureUnit.toPascal(pressureValue)
        self.temperatureValue = temperatureValue
        self.temperatureUnit = temperatureUnit
        self.temperatureK = temperatureUnit.toKelvin(temperatureValue)
    }
}

public enum StreamMixingConversionError: Error, Equatable, Sendable {
    case emptyComposition
    case inconsistentCompositionBasis
    case duplicateComponent(ComponentID)
    case nonFiniteCompositionValue(ComponentID)
    case negativeCompositionValue(ComponentID)
    case missingMolarMass(ComponentID)
    case invalidCompositionTotal
    case invalidMolarMass
    case invalidFlow
    case incompatibleFlowBasis
}

public struct StreamCompositionConverter: Sendable {
    public init() {}

    public func moleFractions(
        from original: [CompositionInputSnapshot]
    ) throws -> [MixtureComponent] {
        let unit = try validatedUnitAndValues(for: original)
        switch unit {
        case .moleFraction, .molePercent, .partsPerMillion:
            let scale = compositionScale(for: unit)
            return original
                .map {
                    MixtureComponent(
                        component: $0.component,
                        moleFraction: $0.value / scale
                    )
                }
                .sorted { $0.component.rawValue < $1.component.rawValue }
        case .massFraction:
            return try moleFractionsFromMassFractions(original)
        }
    }

    public func normalizedMoleFractions(
        from original: [CompositionInputSnapshot]
    ) throws -> [MixtureComponent] {
        let unit = try validatedUnitAndValues(for: original)
        let total = original.reduce(0) { $0 + $1.value }
        guard total.isFinite, total > 0 else {
            throw StreamMixingConversionError.invalidCompositionTotal
        }
        let scale = compositionScale(for: unit)
        let normalizedOriginal = original.map {
            CompositionInputSnapshot(
                component: $0.component,
                value: $0.value / total * scale,
                unit: $0.unit
            )
        }
        return try moleFractions(from: normalizedOriginal)
    }

    public func compositionSnapshots(
        from moleFractions: [MixtureComponent],
        basis: CompositionUnit
    ) throws -> [CompositionInputSnapshot] {
        try validateMoleFractions(moleFractions)
        switch basis {
        case .moleFraction:
            return ordered(moleFractions).map {
                CompositionInputSnapshot(component: $0.component, value: $0.moleFraction, unit: basis)
            }
        case .molePercent:
            return ordered(moleFractions).map {
                CompositionInputSnapshot(component: $0.component, value: $0.moleFraction * 100, unit: basis)
            }
        case .partsPerMillion:
            return ordered(moleFractions).map {
                CompositionInputSnapshot(component: $0.component, value: $0.moleFraction * 1_000_000, unit: basis)
            }
        case .massFraction:
            let molarMass = try mixtureMolarMassKilogramsPerMole(moleFractions)
            return try ordered(moleFractions).map {
                guard let componentMass = $0.component.molarMassKilogramsPerMole else {
                    throw StreamMixingConversionError.missingMolarMass($0.component)
                }
                return CompositionInputSnapshot(
                    component: $0.component,
                    value: $0.moleFraction * componentMass / molarMass,
                    unit: basis
                )
            }
        }
    }

    public func mixtureMolarMassKilogramsPerMole(
        _ moleFractions: [MixtureComponent]
    ) throws -> Double {
        try validateMoleFractions(moleFractions)
        var molarMass = 0.0
        for item in moleFractions where item.moleFraction > 0 {
            guard let componentMass = item.component.molarMassKilogramsPerMole,
                  componentMass.isFinite,
                  componentMass > 0
            else {
                throw StreamMixingConversionError.missingMolarMass(item.component)
            }
            molarMass += item.moleFraction * componentMass
        }
        guard molarMass.isFinite, molarMass > 0 else {
            throw StreamMixingConversionError.invalidMolarMass
        }
        return molarMass
    }

    private func validatedUnitAndValues(
        for original: [CompositionInputSnapshot]
    ) throws -> CompositionUnit {
        guard !original.isEmpty else {
            throw StreamMixingConversionError.emptyComposition
        }
        let units = Set(original.map(\.unit))
        guard units.count == 1, let unit = units.first else {
            throw StreamMixingConversionError.inconsistentCompositionBasis
        }
        var seen: Set<ComponentID> = []
        for entry in original {
            guard entry.value.isFinite else {
                throw StreamMixingConversionError.nonFiniteCompositionValue(entry.component)
            }
            guard entry.value >= 0 else {
                throw StreamMixingConversionError.negativeCompositionValue(entry.component)
            }
            guard seen.insert(entry.component).inserted else {
                throw StreamMixingConversionError.duplicateComponent(entry.component)
            }
            if unit == .massFraction,
               entry.value > 0,
               entry.component.molarMassKilogramsPerMole == nil {
                throw StreamMixingConversionError.missingMolarMass(entry.component)
            }
        }
        return unit
    }

    private func moleFractionsFromMassFractions(
        _ original: [CompositionInputSnapshot]
    ) throws -> [MixtureComponent] {
        var moleAmounts: [(component: ComponentID, amount: Double)] = []
        for entry in original {
            guard let molarMass = entry.component.molarMassKilogramsPerMole,
                  molarMass.isFinite,
                  molarMass > 0
            else {
                throw StreamMixingConversionError.missingMolarMass(entry.component)
            }
            moleAmounts.append((entry.component, entry.value / molarMass))
        }
        let total = moleAmounts.reduce(0) { $0 + $1.amount }
        guard total.isFinite, total > 0 else {
            throw StreamMixingConversionError.invalidCompositionTotal
        }
        return moleAmounts
            .map {
                MixtureComponent(
                    component: $0.component,
                    moleFraction: $0.amount / total
                )
            }
            .sorted { $0.component.rawValue < $1.component.rawValue }
    }

    private func validateMoleFractions(_ moleFractions: [MixtureComponent]) throws {
        guard !moleFractions.isEmpty else {
            throw StreamMixingConversionError.emptyComposition
        }
        var seen: Set<ComponentID> = []
        for item in moleFractions {
            guard item.moleFraction.isFinite else {
                throw StreamMixingConversionError.nonFiniteCompositionValue(item.component)
            }
            guard item.moleFraction >= 0 else {
                throw StreamMixingConversionError.negativeCompositionValue(item.component)
            }
            guard seen.insert(item.component).inserted else {
                throw StreamMixingConversionError.duplicateComponent(item.component)
            }
        }
        let total = moleFractions.reduce(0) { $0 + $1.moleFraction }
        guard total.isFinite,
              abs(total - 1) <= CalculationValidator.normalizationTolerance
        else {
            throw StreamMixingConversionError.invalidCompositionTotal
        }
    }

    private func ordered(_ composition: [MixtureComponent]) -> [MixtureComponent] {
        composition.sorted { $0.component.rawValue < $1.component.rawValue }
    }

    private func compositionScale(for unit: CompositionUnit) -> Double {
        switch unit {
        case .moleFraction, .massFraction:
            1
        case .molePercent:
            100
        case .partsPerMillion:
            1_000_000
        }
    }
}

public struct StreamFlowConverter: Sendable {
    private let compositionConverter: StreamCompositionConverter

    public init(compositionConverter: StreamCompositionConverter = StreamCompositionConverter()) {
        self.compositionConverter = compositionConverter
    }

    public func convertedFlowValue(
        _ value: Double,
        from oldUnit: StreamFlowUnit,
        to newUnit: StreamFlowUnit,
        composition: [MixtureComponent]
    ) throws -> Double {
        guard value.isFinite, value > 0 else {
            throw StreamMixingConversionError.invalidFlow
        }
        if oldUnit.basis == newUnit.basis {
            switch oldUnit.basis {
            case .mass:
                guard let kilogramsPerSecond = oldUnit.kilogramsPerSecond(from: value),
                      let converted = newUnit.displayMassFlow(
                        fromKilogramsPerSecond: kilogramsPerSecond
                      )
                else {
                    throw StreamMixingConversionError.incompatibleFlowBasis
                }
                return converted
            case .molar:
                guard let molesPerSecond = oldUnit.molesPerSecond(from: value),
                      let converted = newUnit.displayMolarFlow(fromMolesPerSecond: molesPerSecond)
                else {
                    throw StreamMixingConversionError.incompatibleFlowBasis
                }
                return converted
            }
        }

        let molarMass = try compositionConverter.mixtureMolarMassKilogramsPerMole(composition)
        if oldUnit.basis == .mass {
            guard let kilogramsPerSecond = oldUnit.kilogramsPerSecond(from: value),
                  let converted = newUnit.displayMolarFlow(
                    fromMolesPerSecond: kilogramsPerSecond / molarMass
                  )
            else {
                throw StreamMixingConversionError.incompatibleFlowBasis
            }
            return converted
        } else {
            guard let molesPerSecond = oldUnit.molesPerSecond(from: value),
                  let converted = newUnit.displayMassFlow(
                    fromKilogramsPerSecond: molesPerSecond * molarMass
                  )
            else {
                throw StreamMixingConversionError.incompatibleFlowBasis
            }
            return converted
        }
    }
}

public struct InletStreamInput: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let flowValue: Double
    public let flowUnit: StreamFlowUnit
    public let flowBasis: StreamFlowBasis
    public let pressureValue: Double
    public let pressureUnit: PressureUnit
    public let pressurePa: Double
    public let temperatureValue: Double
    public let temperatureUnit: TemperatureUnit
    public let temperatureK: Double
    public let originalComposition: [CompositionInputSnapshot]
    public let composition: [MixtureComponent]
    public let normalizedComposition: [MixtureComponent]?

    public init(
        id: UUID = UUID(),
        name: String,
        flowValue: Double,
        flowUnit: StreamFlowUnit,
        flowBasis: StreamFlowBasis? = nil,
        pressureValue: Double,
        pressureUnit: PressureUnit,
        temperatureValue: Double,
        temperatureUnit: TemperatureUnit,
        originalComposition: [CompositionInputSnapshot],
        composition: [MixtureComponent],
        normalizedComposition: [MixtureComponent]? = nil
    ) {
        self.id = id
        self.name = name
        self.flowValue = flowValue
        self.flowUnit = flowUnit
        self.flowBasis = flowBasis ?? flowUnit.basis
        self.pressureValue = pressureValue
        self.pressureUnit = pressureUnit
        self.pressurePa = pressureUnit.toPascal(pressureValue)
        self.temperatureValue = temperatureValue
        self.temperatureUnit = temperatureUnit
        self.temperatureK = temperatureUnit.toKelvin(temperatureValue)
        self.originalComposition = originalComposition
        self.composition = composition
        self.normalizedComposition = normalizedComposition
    }
}

public enum StreamCompositionConversionStatus: String, Codable, Equatable, Sendable {
    case valid
    case normalizationAccepted
}

public struct StreamCompositionProvenance: Codable, Equatable, Sendable {
    public let originalComposition: [CompositionInputSnapshot]
    public let convertedComposition: [MixtureComponent]
    public let normalizedComposition: [MixtureComponent]?
    public let canonicalComposition: [MixtureComponent]
    public let status: StreamCompositionConversionStatus

    public init(
        originalComposition: [CompositionInputSnapshot],
        convertedComposition: [MixtureComponent],
        normalizedComposition: [MixtureComponent]?,
        canonicalComposition: [MixtureComponent],
        status: StreamCompositionConversionStatus
    ) {
        self.originalComposition = originalComposition
        self.convertedComposition = convertedComposition
        self.normalizedComposition = normalizedComposition
        self.canonicalComposition = canonicalComposition
        self.status = status
    }
}

public struct OriginalStreamInputSnapshot: Codable, Equatable, Sendable {
    public let streamID: UUID
    public let name: String
    public let flowValue: Double
    public let flowUnit: StreamFlowUnit
    public let flowBasis: StreamFlowBasis
    public let pressureValue: Double
    public let pressureUnit: PressureUnit
    public let pressurePa: Double
    public let temperatureValue: Double
    public let temperatureUnit: TemperatureUnit
    public let temperatureK: Double
    public let originalComposition: [CompositionInputSnapshot]
    public let convertedComposition: [MixtureComponent]
    public let normalizedComposition: [MixtureComponent]?
    public let canonicalComposition: [MixtureComponent]
    public let compositionStatus: StreamCompositionConversionStatus

    public init(stream: InletStreamInput, compositionProvenance: StreamCompositionProvenance) {
        self.streamID = stream.id
        self.name = stream.name
        self.flowValue = stream.flowValue
        self.flowUnit = stream.flowUnit
        self.flowBasis = stream.flowBasis
        self.pressureValue = stream.pressureValue
        self.pressureUnit = stream.pressureUnit
        self.pressurePa = stream.pressurePa
        self.temperatureValue = stream.temperatureValue
        self.temperatureUnit = stream.temperatureUnit
        self.temperatureK = stream.temperatureK
        self.originalComposition = stream.originalComposition
        self.convertedComposition = compositionProvenance.convertedComposition
        self.normalizedComposition = compositionProvenance.normalizedComposition
        self.canonicalComposition = compositionProvenance.canonicalComposition
        self.compositionStatus = compositionProvenance.status
    }
}

public struct StreamMixingRequest: Codable, Equatable, Sendable {
    public static let minimumStreamCount = 2
    public static let maximumStreamCount = 6

    public let requestID: UUID
    public let streams: [InletStreamInput]
    public let outlet: StreamMixingOutletConditionInput
    public let clientVersion: String

    public init(
        requestID: UUID = UUID(),
        streams: [InletStreamInput],
        outlet: StreamMixingOutletConditionInput,
        clientVersion: String
    ) {
        self.requestID = requestID
        self.streams = streams
        self.outlet = outlet
        self.clientVersion = clientVersion
    }
}

public enum StreamMixingField: String, Codable, Equatable, Sendable {
    case streamCount
    case streamID
    case name
    case flow
    case flowUnit
    case pressure
    case temperature
    case composition
    case molarMass
    case aggregation
    case outletPressure
    case outletTemperature
}

public enum StreamMixingValidationCode: String, Codable, Equatable, Sendable {
    case tooFewStreams
    case tooManyStreams
    case duplicateStreamIdentifier
    case invalidStreamName
    case invalidFlow
    case flowUnitBasisMismatch
    case invalidPressure
    case invalidTemperature
    case invalidComposition
    case inconsistentCompositionBasis
    case compositionProvenanceMismatch
    case normalizationRequired
    case invalidNormalization
    case missingMolarMass
    case invalidTotalMolarFlow
    case nonFiniteResult
    case mixedCompositionUnsupported
}

public struct StreamMixingValidationIssue: Codable, Equatable, Sendable, Identifiable {
    public var id: String {
        [
            code.rawValue,
            streamID?.uuidString ?? "",
            field.rawValue,
            message
        ].joined(separator: ":")
    }

    public let code: StreamMixingValidationCode
    public let field: StreamMixingField
    public let streamID: UUID?
    public let streamName: String?
    public let message: String

    public init(
        code: StreamMixingValidationCode,
        field: StreamMixingField,
        streamID: UUID? = nil,
        streamName: String? = nil,
        message: String
    ) {
        self.code = code
        self.field = field
        self.streamID = streamID
        self.streamName = streamName
        self.message = message
    }
}

public struct StreamMixingValidationReport: Codable, Equatable, Sendable {
    public let issues: [StreamMixingValidationIssue]

    public var canCalculate: Bool {
        issues.isEmpty
    }

    public init(issues: [StreamMixingValidationIssue]) {
        self.issues = issues
    }
}

public enum StreamMixingWarningCode: String, Codable, Equatable, Sendable {
    case inletPressureDifference
}

public struct StreamMixingWarning: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "\(code.rawValue):\(message)" }
    public let code: StreamMixingWarningCode
    public let message: String

    public init(code: StreamMixingWarningCode, message: String) {
        self.code = code
        self.message = message
    }
}

public enum StreamMixingAssumptionCode: String, Codable, Equatable, Sendable {
    case compositionOnlyMixing
    case userDefinedOutletState
    case noEnergyBalance
    case explicitCompositionNormalization
}

public struct StreamMixingAssumption: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "\(code.rawValue):\(streamID?.uuidString ?? ""):\(message)" }
    public let code: StreamMixingAssumptionCode
    public let streamID: UUID?
    public let message: String

    public init(
        code: StreamMixingAssumptionCode,
        streamID: UUID? = nil,
        message: String
    ) {
        self.code = code
        self.streamID = streamID
        self.message = message
    }
}

public struct StreamMixingComponentMolarFlow: Codable, Equatable, Sendable, Identifiable {
    public var id: ComponentID { component }
    public let component: ComponentID
    public let molarFlowMolesPerSecond: Double
    public let massFlowKilogramsPerSecond: Double

    public init(
        component: ComponentID,
        molarFlowMolesPerSecond: Double,
        massFlowKilogramsPerSecond: Double
    ) {
        self.component = component
        self.molarFlowMolesPerSecond = molarFlowMolesPerSecond
        self.massFlowKilogramsPerSecond = massFlowKilogramsPerSecond
    }
}

public struct StreamMixingStreamContribution: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID { streamID }
    public let streamID: UUID
    public let streamName: String
    public let input: OriginalStreamInputSnapshot
    public let massFlowKilogramsPerSecond: Double
    public let molarFlowMolesPerSecond: Double
    public let componentMolarFlows: [StreamMixingComponentMolarFlow]

    public init(
        streamID: UUID,
        streamName: String,
        input: OriginalStreamInputSnapshot,
        massFlowKilogramsPerSecond: Double,
        molarFlowMolesPerSecond: Double,
        componentMolarFlows: [StreamMixingComponentMolarFlow]
    ) {
        self.streamID = streamID
        self.streamName = streamName
        self.input = input
        self.massFlowKilogramsPerSecond = massFlowKilogramsPerSecond
        self.molarFlowMolesPerSecond = molarFlowMolesPerSecond
        self.componentMolarFlows = componentMolarFlows
    }
}

public struct StreamMixingConservationCheck: Codable, Equatable, Sendable {
    public let molarFlowAbsoluteTolerance: Double
    public let molarFlowRelativeTolerance: Double
    public let massFlowAbsoluteTolerance: Double
    public let massFlowRelativeTolerance: Double
    public let componentMolarFlowAbsoluteTolerance: Double
    public let componentMolarFlowRelativeTolerance: Double
    public let totalMolarFlowResidual: Double
    public let totalMolarFlowRelativeResidual: Double
    public let maximumComponentMolarFlowResidual: Double
    public let maximumComponentMolarFlowRelativeResidual: Double
    public let totalMassFlowResidual: Double
    public let totalMassFlowRelativeResidual: Double
    public let maximumMassBasisInletMassFlowResidual: Double
    public let maximumMassBasisInletMassFlowRelativeResidual: Double

    public var isConserved: Bool {
        residualIsWithinTolerance(
            absolute: totalMolarFlowResidual,
            relative: totalMolarFlowRelativeResidual,
            absoluteTolerance: molarFlowAbsoluteTolerance,
            relativeTolerance: molarFlowRelativeTolerance
        )
            && residualIsWithinTolerance(
                absolute: maximumComponentMolarFlowResidual,
                relative: maximumComponentMolarFlowRelativeResidual,
                absoluteTolerance: componentMolarFlowAbsoluteTolerance,
                relativeTolerance: componentMolarFlowRelativeTolerance
            )
            && residualIsWithinTolerance(
                absolute: totalMassFlowResidual,
                relative: totalMassFlowRelativeResidual,
                absoluteTolerance: massFlowAbsoluteTolerance,
                relativeTolerance: massFlowRelativeTolerance
            )
            && residualIsWithinTolerance(
                absolute: maximumMassBasisInletMassFlowResidual,
                relative: maximumMassBasisInletMassFlowRelativeResidual,
                absoluteTolerance: massFlowAbsoluteTolerance,
                relativeTolerance: massFlowRelativeTolerance
            )
    }

    public init(
        molarFlowAbsoluteTolerance: Double,
        molarFlowRelativeTolerance: Double,
        massFlowAbsoluteTolerance: Double,
        massFlowRelativeTolerance: Double,
        componentMolarFlowAbsoluteTolerance: Double,
        componentMolarFlowRelativeTolerance: Double,
        totalMolarFlowResidual: Double,
        totalMolarFlowRelativeResidual: Double,
        maximumComponentMolarFlowResidual: Double,
        maximumComponentMolarFlowRelativeResidual: Double,
        totalMassFlowResidual: Double,
        totalMassFlowRelativeResidual: Double,
        maximumMassBasisInletMassFlowResidual: Double,
        maximumMassBasisInletMassFlowRelativeResidual: Double
    ) {
        self.molarFlowAbsoluteTolerance = molarFlowAbsoluteTolerance
        self.molarFlowRelativeTolerance = molarFlowRelativeTolerance
        self.massFlowAbsoluteTolerance = massFlowAbsoluteTolerance
        self.massFlowRelativeTolerance = massFlowRelativeTolerance
        self.componentMolarFlowAbsoluteTolerance = componentMolarFlowAbsoluteTolerance
        self.componentMolarFlowRelativeTolerance = componentMolarFlowRelativeTolerance
        self.totalMolarFlowResidual = totalMolarFlowResidual
        self.totalMolarFlowRelativeResidual = totalMolarFlowRelativeResidual
        self.maximumComponentMolarFlowResidual = maximumComponentMolarFlowResidual
        self.maximumComponentMolarFlowRelativeResidual = maximumComponentMolarFlowRelativeResidual
        self.totalMassFlowResidual = totalMassFlowResidual
        self.totalMassFlowRelativeResidual = totalMassFlowRelativeResidual
        self.maximumMassBasisInletMassFlowResidual = maximumMassBasisInletMassFlowResidual
        self.maximumMassBasisInletMassFlowRelativeResidual =
            maximumMassBasisInletMassFlowRelativeResidual
    }

    private func residualIsWithinTolerance(
        absolute: Double,
        relative: Double,
        absoluteTolerance: Double,
        relativeTolerance: Double
    ) -> Bool {
        absolute.isFinite
            && relative.isFinite
            && (
                abs(absolute) <= absoluteTolerance
                    || abs(relative) <= relativeTolerance
            )
    }
}

public struct StreamMixingTolerances: Codable, Equatable, Sendable {
    public let molarFlowAbsoluteTolerance: Double
    public let molarFlowRelativeTolerance: Double
    public let massFlowAbsoluteTolerance: Double
    public let massFlowRelativeTolerance: Double
    public let componentMolarFlowAbsoluteTolerance: Double
    public let componentMolarFlowRelativeTolerance: Double

    public init(
        molarFlowAbsoluteTolerance: Double = 1e-12,
        molarFlowRelativeTolerance: Double = 1e-12,
        massFlowAbsoluteTolerance: Double = 1e-12,
        massFlowRelativeTolerance: Double = 1e-12,
        componentMolarFlowAbsoluteTolerance: Double = 1e-13,
        componentMolarFlowRelativeTolerance: Double = 1e-12
    ) {
        self.molarFlowAbsoluteTolerance = molarFlowAbsoluteTolerance
        self.molarFlowRelativeTolerance = molarFlowRelativeTolerance
        self.massFlowAbsoluteTolerance = massFlowAbsoluteTolerance
        self.massFlowRelativeTolerance = massFlowRelativeTolerance
        self.componentMolarFlowAbsoluteTolerance = componentMolarFlowAbsoluteTolerance
        self.componentMolarFlowRelativeTolerance = componentMolarFlowRelativeTolerance
    }
}

public enum StreamMixingCalculationStatus: String, Codable, Equatable, Sendable {
    case calculated
    case blocked
}

public struct MixedCompositionResult: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID { requestID }
    public let requestID: UUID
    public let calculatedAt: Date
    public let status: StreamMixingCalculationStatus
    public let outlet: StreamMixingOutletConditionInput
    public let composition: [MixtureComponent]
    public let totalMassFlowKilogramsPerSecond: Double
    public let totalMolarFlowMolesPerSecond: Double
    public let componentMolarFlows: [StreamMixingComponentMolarFlow]
    public let streamContributions: [StreamMixingStreamContribution]
    public let conservation: StreamMixingConservationCheck
    public let warnings: [StreamMixingWarning]
    public let assumptions: [StreamMixingAssumption]
    public let validationIssues: [StreamMixingValidationIssue]

    public init(
        requestID: UUID,
        calculatedAt: Date = Date(),
        status: StreamMixingCalculationStatus,
        outlet: StreamMixingOutletConditionInput,
        composition: [MixtureComponent],
        totalMassFlowKilogramsPerSecond: Double,
        totalMolarFlowMolesPerSecond: Double,
        componentMolarFlows: [StreamMixingComponentMolarFlow],
        streamContributions: [StreamMixingStreamContribution],
        conservation: StreamMixingConservationCheck,
        warnings: [StreamMixingWarning],
        assumptions: [StreamMixingAssumption],
        validationIssues: [StreamMixingValidationIssue]
    ) {
        self.requestID = requestID
        self.calculatedAt = calculatedAt
        self.status = status
        self.outlet = outlet
        self.composition = composition
        self.totalMassFlowKilogramsPerSecond = totalMassFlowKilogramsPerSecond
        self.totalMolarFlowMolesPerSecond = totalMolarFlowMolesPerSecond
        self.componentMolarFlows = componentMolarFlows
        self.streamContributions = streamContributions
        self.conservation = conservation
        self.warnings = warnings
        self.assumptions = assumptions
        self.validationIssues = validationIssues
    }
}

public struct StreamMixingEngine: Sendable {
    public static let pressureComparisonTolerancePa = 1.0

    private let validator: CalculationValidator
    private let domain: ScientificDomain
    private let supportedComponents: Set<ComponentID>
    private let tolerances: StreamMixingTolerances
    private let compositionConverter: StreamCompositionConverter

    private struct CompositionConversionOutcome {
        let provenance: StreamCompositionProvenance?
        let issues: [StreamMixingValidationIssue]
    }

    public init(
        validator: CalculationValidator = CalculationValidator(),
        domain: ScientificDomain = .initialCO2Transport,
        supportedComponents: Set<ComponentID> = Set(ComponentID.allCases),
        tolerances: StreamMixingTolerances = StreamMixingTolerances(),
        compositionConverter: StreamCompositionConverter = StreamCompositionConverter()
    ) {
        self.validator = validator
        self.domain = domain
        self.supportedComponents = supportedComponents
        self.tolerances = tolerances
        self.compositionConverter = compositionConverter
    }

    public func validate(_ request: StreamMixingRequest) -> StreamMixingValidationReport {
        StreamMixingValidationReport(issues: validationIssues(for: request))
    }

    public func mix(_ request: StreamMixingRequest) -> MixedCompositionResult {
        let initialIssues = validationIssues(for: request)
        let warnings = warnings(for: request.streams)
        let generalAssumptions = assumptions(acceptedNormalizedStreamIDs: [])
        if !initialIssues.isEmpty {
            return blockedResult(
                request: request,
                warnings: warnings,
                assumptions: generalAssumptions,
                issues: initialIssues
            )
        }

        var streamContributions: [StreamMixingStreamContribution] = []
        var acceptedNormalizedStreamIDs: [UUID] = []

        for stream in request.streams {
            guard let compositionProvenance = compositionProvenance(for: stream).provenance else {
                return blockedResult(
                    request: request,
                    warnings: warnings,
                    assumptions: generalAssumptions,
                    issues: [issue(
                        .invalidComposition,
                        field: .composition,
                        stream: stream,
                        message: "Stream composition provenance could not be converted."
                    )]
                )
            }
            guard
                let molarFlow = molarFlowMolesPerSecond(
                    for: stream,
                    composition: compositionProvenance.canonicalComposition
                ),
                molarFlow.isFinite,
                molarFlow > 0
            else {
                return blockedResult(
                    request: request,
                    warnings: warnings,
                    assumptions: generalAssumptions,
                    issues: [aggregationIssue(
                        stream: stream,
                        message: "Stream total molar flow was non-finite or non-positive."
                    )]
                )
            }

            let componentFlows = componentFlowValues(
                composition: compositionProvenance.canonicalComposition,
                totalMolarFlow: molarFlow
            )
            let massFlow = componentFlows.reduce(0) { $0 + $1.massFlowKilogramsPerSecond }
            guard massFlow.isFinite, massFlow > 0,
                  componentFlows.allSatisfy({
                      $0.molarFlowMolesPerSecond.isFinite
                          && $0.molarFlowMolesPerSecond >= 0
                          && $0.massFlowKilogramsPerSecond.isFinite
                          && $0.massFlowKilogramsPerSecond >= 0
                  })
            else {
                return blockedResult(
                    request: request,
                    warnings: warnings,
                    assumptions: generalAssumptions,
                    issues: [aggregationIssue(
                        stream: stream,
                        message: "Stream component flow calculation produced a non-finite value."
                    )]
                )
            }

            streamContributions.append(StreamMixingStreamContribution(
                streamID: stream.id,
                streamName: stream.name,
                input: OriginalStreamInputSnapshot(
                    stream: stream,
                    compositionProvenance: compositionProvenance
                ),
                massFlowKilogramsPerSecond: massFlow,
                molarFlowMolesPerSecond: molarFlow,
                componentMolarFlows: componentFlows
            ))
            if compositionProvenance.status == .normalizationAccepted {
                acceptedNormalizedStreamIDs.append(stream.id)
            }
        }

        let canonicalContributions = stableStreamOrder(streamContributions)
        let calculationAssumptions = assumptions(
            acceptedNormalizedStreamIDs: acceptedNormalizedStreamIDs
        )
        let totalMolarFlow = canonicalContributions.reduce(0) {
            $0 + $1.molarFlowMolesPerSecond
        }
        guard totalMolarFlow.isFinite, totalMolarFlow > 0 else {
            return blockedResult(
                request: request,
                warnings: warnings,
                assumptions: calculationAssumptions,
                issues: [StreamMixingValidationIssue(
                    code: .invalidTotalMolarFlow,
                    field: .aggregation,
                    message: "Total mixed molar flow was non-finite or non-positive."
                )]
            )
        }

        let componentMolarFlows = orderedComponentFlows(from: canonicalContributions)
        let totalMassFlow = componentMolarFlows.reduce(0) {
            $0 + $1.massFlowKilogramsPerSecond
        }
        let composition = componentMolarFlows.map {
            MixtureComponent(
                component: $0.component,
                moleFraction: $0.molarFlowMolesPerSecond / totalMolarFlow
            )
        }
        guard totalMassFlow.isFinite, totalMassFlow > 0,
              composition.allSatisfy({ $0.moleFraction.isFinite && $0.moleFraction >= 0 })
        else {
            return blockedResult(
                request: request,
                warnings: warnings,
                assumptions: calculationAssumptions,
                issues: [StreamMixingValidationIssue(
                    code: .nonFiniteResult,
                    field: .aggregation,
                    message: "Mixed composition or total mass flow was non-finite."
                )]
            )
        }

        let mixedValidation = validator.validate(
            pressurePa: request.outlet.pressurePa,
            temperatureK: request.outlet.temperatureK,
            composition: composition,
            supportedComponents: supportedComponents,
            domain: domain
        )
        if !mixedValidation.canCalculate {
            return blockedResult(
                request: request,
                warnings: warnings,
                assumptions: calculationAssumptions,
                issues: mixedValidation.issues.map {
                    StreamMixingValidationIssue(
                        code: .mixedCompositionUnsupported,
                        field: .composition,
                        message: "Mixed composition rejected: \($0.message)"
                    )
                }
            )
        }

        let conservation = conservationCheck(
            componentMolarFlows: componentMolarFlows,
            streamContributions: streamContributions,
            totalMolarFlow: totalMolarFlow,
            totalMassFlow: totalMassFlow
        )
        guard conservation.isConserved else {
            return blockedResult(
                request: request,
                warnings: warnings,
                assumptions: calculationAssumptions,
                issues: [StreamMixingValidationIssue(
                    code: .nonFiniteResult,
                    field: .aggregation,
                    message: "Stream mixing failed conservation checks."
                )]
            )
        }

        return MixedCompositionResult(
            requestID: request.requestID,
            status: .calculated,
            outlet: request.outlet,
            composition: composition,
            totalMassFlowKilogramsPerSecond: totalMassFlow,
            totalMolarFlowMolesPerSecond: totalMolarFlow,
            componentMolarFlows: componentMolarFlows,
            streamContributions: streamContributions,
            conservation: conservation,
            warnings: warnings,
            assumptions: calculationAssumptions,
            validationIssues: []
        )
    }

    private func validationIssues(for request: StreamMixingRequest) -> [StreamMixingValidationIssue] {
        var issues: [StreamMixingValidationIssue] = []
        if request.streams.count < StreamMixingRequest.minimumStreamCount {
            issues.append(StreamMixingValidationIssue(
                code: .tooFewStreams,
                field: .streamCount,
                message: "Stream mixing requires at least 2 inlet streams."
            ))
        }
        if request.streams.count > StreamMixingRequest.maximumStreamCount {
            issues.append(StreamMixingValidationIssue(
                code: .tooManyStreams,
                field: .streamCount,
                message: "Stream mixing supports at most 6 inlet streams."
            ))
        }

        let groupedIDs = Dictionary(grouping: request.streams, by: \.id)
        for (id, streams) in groupedIDs where streams.count > 1 {
            issues.append(StreamMixingValidationIssue(
                code: .duplicateStreamIdentifier,
                field: .streamID,
                streamID: id,
                streamName: streams.first?.name,
                message: "Each inlet stream requires a stable unique identifier."
            ))
        }

        issues.append(contentsOf: validateOutlet(request.outlet))
        for stream in request.streams {
            issues.append(contentsOf: validate(stream))
        }
        return issues
    }

    private func validate(_ stream: InletStreamInput) -> [StreamMixingValidationIssue] {
        var issues: [StreamMixingValidationIssue] = []
        let trimmedName = stream.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            issues.append(issue(
                .invalidStreamName,
                field: .name,
                stream: stream,
                message: "Each inlet stream requires a non-empty name."
            ))
        }
        if stream.flowBasis != stream.flowUnit.basis {
            issues.append(issue(
                .flowUnitBasisMismatch,
                field: .flowUnit,
                stream: stream,
                message: "Flow unit \(stream.flowUnit.rawValue) does not match \(stream.flowBasis.rawValue) flow basis."
            ))
        }
        if !stream.flowValue.isFinite || stream.flowValue <= 0 {
            issues.append(issue(
                .invalidFlow,
                field: .flow,
                stream: stream,
                message: "Flow rate must be finite and greater than zero."
            ))
        }
        if !stream.pressurePa.isFinite || stream.pressurePa <= 0
            || stream.pressurePa < domain.minimumPressurePa
            || stream.pressurePa > domain.maximumPressurePa
        {
            issues.append(issue(
                .invalidPressure,
                field: .pressure,
                stream: stream,
                message: "Inlet pressure must be finite, positive and inside the recorded domain."
            ))
        }
        if !stream.temperatureK.isFinite || stream.temperatureK <= 0
            || stream.temperatureK < domain.minimumTemperatureK
            || stream.temperatureK > domain.maximumTemperatureK
        {
            issues.append(issue(
                .invalidTemperature,
                field: .temperature,
                stream: stream,
                message: "Inlet temperature must be finite, positive and inside the recorded domain."
            ))
        }

        let conversion = compositionProvenance(for: stream)
        issues.append(contentsOf: conversion.issues)
        if let provenance = conversion.provenance {
            let report = validator.validate(
                pressurePa: stream.pressurePa,
                temperatureK: stream.temperatureK,
                composition: provenance.canonicalComposition,
                supportedComponents: supportedComponents,
                domain: domain
            )
            for validationIssue in report.issues {
                issues.append(issue(
                    validationIssue.code == .normalizationAvailable
                        ? .normalizationRequired
                        : .invalidComposition,
                    field: .composition,
                    stream: stream,
                    message: validationIssue.message
                ))
            }
        }
        return issues
    }

    private func validateOutlet(
        _ outlet: StreamMixingOutletConditionInput
    ) -> [StreamMixingValidationIssue] {
        var issues: [StreamMixingValidationIssue] = []
        if !outlet.pressurePa.isFinite || outlet.pressurePa <= 0
            || outlet.pressurePa < domain.minimumPressurePa
            || outlet.pressurePa > domain.maximumPressurePa
        {
            issues.append(StreamMixingValidationIssue(
                code: .invalidPressure,
                field: .outletPressure,
                message: "Outlet pressure must be finite, positive and inside the recorded domain."
            ))
        }
        if !outlet.temperatureK.isFinite || outlet.temperatureK <= 0
            || outlet.temperatureK < domain.minimumTemperatureK
            || outlet.temperatureK > domain.maximumTemperatureK
        {
            issues.append(StreamMixingValidationIssue(
                code: .invalidTemperature,
                field: .outletTemperature,
                message: "Outlet temperature must be finite, positive and inside the recorded domain."
            ))
        }
        return issues
    }

    private func compositionProvenance(
        for stream: InletStreamInput
    ) -> CompositionConversionOutcome {
        var issues: [StreamMixingValidationIssue] = []
        let original = stream.originalComposition

        guard !original.isEmpty else {
            return CompositionConversionOutcome(
                provenance: nil,
                issues: [issue(
                    .invalidComposition,
                    field: .composition,
                    stream: stream,
                    message: "Composition cannot be empty."
                )]
            )
        }

        issues.append(contentsOf: duplicateComponentIssues(
            in: stream.composition,
            code: .invalidComposition,
            stream: stream,
            message: "Canonical composition may list each component only once."
        ))
        if let normalizedComposition = stream.normalizedComposition {
            issues.append(contentsOf: duplicateComponentIssues(
                in: normalizedComposition,
                code: .invalidNormalization,
                stream: stream,
                message: "Normalized composition may list each component only once."
            ))
        }

        let units = Set(original.map(\.unit))
        guard units.count == 1, let unit = units.first else {
            return CompositionConversionOutcome(
                provenance: nil,
                issues: [issue(
                    .inconsistentCompositionBasis,
                    field: .composition,
                    stream: stream,
                    message: "Every component in one stream must use the same composition basis."
                )]
            )
        }

        if original.contains(where: { !$0.value.isFinite }) {
            issues.append(issue(
                .invalidComposition,
                field: .composition,
                stream: stream,
                message: "Composition values must be finite."
            ))
        }
        if original.contains(where: { $0.value < 0 }) {
            issues.append(issue(
                .invalidComposition,
                field: .composition,
                stream: stream,
                message: "Composition values cannot be negative."
            ))
        }
        let grouped = Dictionary(grouping: original, by: \.component)
        if grouped.values.contains(where: { $0.count > 1 }) {
            issues.append(issue(
                .invalidComposition,
                field: .composition,
                stream: stream,
                message: "Each component may appear only once."
            ))
        }
        if unit == .massFraction {
            let missing = original
                .filter {
                    $0.value > 0
                        && $0.component.molarMassKilogramsPerMole == nil
                }
                .map(\.component)
                .sorted { $0.rawValue < $1.rawValue }
            issues.append(contentsOf: missing.map { component in
                issue(
                    .missingMolarMass,
                    field: .molarMass,
                    stream: stream,
                    message: "No reviewed molar mass is configured for \(component.symbol)."
                )
            })
        }
        guard issues.isEmpty else {
            return CompositionConversionOutcome(provenance: nil, issues: issues)
        }

        let converted: [MixtureComponent]
        do {
            converted = try compositionConverter.moleFractions(from: original)
        } catch {
            return CompositionConversionOutcome(
                provenance: nil,
                issues: [issue(
                    .invalidComposition,
                    field: .composition,
                    stream: stream,
                    message: "Composition could not be converted to mole fractions."
                )]
            )
        }
        let missingConvertedMasses = converted
            .filter {
                $0.moleFraction > 0
                    && $0.component.molarMassKilogramsPerMole == nil
            }
            .map(\.component)
            .sorted { $0.rawValue < $1.rawValue }
        if !missingConvertedMasses.isEmpty {
            return CompositionConversionOutcome(
                provenance: nil,
                issues: missingConvertedMasses.map { component in
                    issue(
                        .missingMolarMass,
                        field: .molarMass,
                        stream: stream,
                        message: "No reviewed molar mass is configured for \(component.symbol)."
                    )
                }
            )
        }

        let scale = compositionScale(for: unit)
        let total = original.reduce(0) { $0 + $1.value }
        let fractionalDeviation = abs(total / scale - 1)
        if fractionalDeviation > CalculationValidator.normalizationTolerance || total <= 0 {
            return CompositionConversionOutcome(
                provenance: nil,
                issues: [issue(
                    .invalidComposition,
                    field: .composition,
                    stream: stream,
                    message: "Composition must total 100 mol% within ±0.01 mol%."
                )]
            )
        }

        let convertedValidation = validator.validate(
            pressurePa: stream.pressurePa,
            temperatureK: stream.temperatureK,
            composition: converted,
            supportedComponents: supportedComponents,
            domain: domain
        )
        let normalizedProposal: [MixtureComponent]?
        if fractionalDeviation > CalculationValidator.compositionTolerance {
            normalizedProposal = try? compositionConverter.normalizedMoleFractions(from: original)
        } else {
            normalizedProposal = convertedValidation.normalizedComposition
        }

        let canonical: [MixtureComponent]
        let status: StreamCompositionConversionStatus
        if let normalizedProposal {
            guard stream.normalizedComposition != nil else {
                return CompositionConversionOutcome(
                    provenance: nil,
                    issues: [issue(
                        .normalizationRequired,
                        field: .composition,
                        stream: stream,
                        message: "Composition requires explicit normalization before stream mixing."
                    )]
                )
            }
            guard compositionsMatch(stream.normalizedComposition ?? [], normalizedProposal) else {
                return CompositionConversionOutcome(
                    provenance: nil,
                    issues: [issue(
                        .invalidNormalization,
                        field: .composition,
                        stream: stream,
                        message: "Recorded normalized composition does not match the explicit normalization available from the original entries."
                    )]
                )
            }
            guard compositionsMatch(stream.composition, normalizedProposal) else {
                return CompositionConversionOutcome(
                    provenance: nil,
                    issues: [issue(
                        .compositionProvenanceMismatch,
                        field: .composition,
                        stream: stream,
                        message: "Canonical composition does not match the recorded normalized composition."
                    )]
                )
            }
            canonical = normalizedProposal
            status = .normalizationAccepted
        } else {
            if stream.normalizedComposition != nil {
                return CompositionConversionOutcome(
                    provenance: nil,
                    issues: [issue(
                        .invalidNormalization,
                        field: .composition,
                        stream: stream,
                        message: "Normalization was recorded for a composition already valid as entered."
                    )]
                )
            }
            guard compositionsMatch(stream.composition, converted) else {
                return CompositionConversionOutcome(
                    provenance: nil,
                    issues: [issue(
                        .compositionProvenanceMismatch,
                        field: .composition,
                        stream: stream,
                        message: "Canonical composition does not match the original entered composition."
                    )]
                )
            }
            canonical = converted
            status = .valid
        }

        return CompositionConversionOutcome(
            provenance: StreamCompositionProvenance(
                originalComposition: original,
                convertedComposition: converted,
                normalizedComposition: status == .normalizationAccepted ? canonical : nil,
                canonicalComposition: canonical,
                status: status
            ),
            issues: []
        )
    }

    private func compositionScale(for unit: CompositionUnit) -> Double {
        switch unit {
        case .moleFraction, .massFraction:
            1
        case .molePercent:
            100
        case .partsPerMillion:
            1_000_000
        }
    }

    private func compositionsMatch(
        _ lhs: [MixtureComponent],
        _ rhs: [MixtureComponent],
        tolerance: Double = 1e-12
    ) -> Bool {
        guard lhs.count == rhs.count else { return false }
        guard !hasDuplicateComponents(lhs),
              !hasDuplicateComponents(rhs)
        else { return false }
        let left = Dictionary(uniqueKeysWithValues: lhs.map { ($0.component, $0.moleFraction) })
        let right = Dictionary(uniqueKeysWithValues: rhs.map { ($0.component, $0.moleFraction) })
        guard Set(left.keys) == Set(right.keys) else { return false }
        return left.allSatisfy { component, value in
            guard let other = right[component],
                  value.isFinite,
                  other.isFinite
            else { return false }
            return abs(value - other) <= tolerance
        }
    }

    private func duplicateComponentIssues(
        in composition: [MixtureComponent],
        code: StreamMixingValidationCode,
        stream: InletStreamInput,
        message: String
    ) -> [StreamMixingValidationIssue] {
        hasDuplicateComponents(composition)
            ? [issue(code, field: .composition, stream: stream, message: message)]
            : []
    }

    private func hasDuplicateComponents(_ composition: [MixtureComponent]) -> Bool {
        var seen: Set<ComponentID> = []
        for item in composition where !seen.insert(item.component).inserted {
            return true
        }
        return false
    }

    private func molarFlowMolesPerSecond(
        for stream: InletStreamInput,
        composition: [MixtureComponent]
    ) -> Double? {
        switch stream.flowBasis {
        case .molar:
            return stream.flowUnit.molesPerSecond(from: stream.flowValue)
        case .mass:
            guard
                let massFlow = stream.flowUnit.kilogramsPerSecond(from: stream.flowValue),
                let molarMass = mixtureMolarMassKilogramsPerMole(composition),
                molarMass > 0
            else { return nil }
            return massFlow / molarMass
        }
    }

    private func componentFlowValues(
        composition: [MixtureComponent],
        totalMolarFlow: Double
    ) -> [StreamMixingComponentMolarFlow] {
        composition
            .filter { $0.moleFraction > 0 }
            .sorted { $0.component.rawValue < $1.component.rawValue }
            .map { component in
                let molarFlow = totalMolarFlow * component.moleFraction
                let massFlow = molarFlow * (component.component.molarMassKilogramsPerMole ?? .nan)
                return StreamMixingComponentMolarFlow(
                    component: component.component,
                    molarFlowMolesPerSecond: molarFlow,
                    massFlowKilogramsPerSecond: massFlow
                )
            }
    }

    private func orderedComponentFlows(
        from contributions: [StreamMixingStreamContribution]
    ) -> [StreamMixingComponentMolarFlow] {
        let orderedContributions = stableStreamOrder(contributions)
        return ComponentID.allCases.compactMap { component -> StreamMixingComponentMolarFlow? in
            let molarFlow = orderedContributions
                .compactMap { contribution in
                    contribution.componentMolarFlows.first {
                        $0.component == component
                    }?.molarFlowMolesPerSecond
                }
                .reduce(0, +)
            guard molarFlow > 0 else { return nil }
            return StreamMixingComponentMolarFlow(
                component: component,
                molarFlowMolesPerSecond: molarFlow,
                massFlowKilogramsPerSecond: molarFlow
                    * (component.molarMassKilogramsPerMole ?? .nan)
            )
        }
    }

    private func stableStreamOrder(
        _ contributions: [StreamMixingStreamContribution]
    ) -> [StreamMixingStreamContribution] {
        contributions.sorted { $0.streamID.uuidString < $1.streamID.uuidString }
    }

    public func conservationCheck(
        componentMolarFlows: [StreamMixingComponentMolarFlow],
        streamContributions: [StreamMixingStreamContribution],
        totalMolarFlow: Double,
        totalMassFlow: Double
    ) -> StreamMixingConservationCheck {
        let orderedContributions = stableStreamOrder(streamContributions)
        let summedStreamMolarFlow = orderedContributions
            .reduce(0) { $0 + $1.molarFlowMolesPerSecond }
        let totalMolarResidual = abs(totalMolarFlow - summedStreamMolarFlow)

        let maximumComponentResidual = componentMolarFlows.reduce(0) { maximum, flow in
            let inletComponentTotal = orderedContributions
                .compactMap { contribution in
                    contribution.componentMolarFlows.first {
                        $0.component == flow.component
                    }?.molarFlowMolesPerSecond
                }
                .reduce(0, +)
            return max(maximum, abs(flow.molarFlowMolesPerSecond - inletComponentTotal))
        }
        let maximumComponentRelativeResidual = componentMolarFlows.reduce(0) { maximum, flow in
            let inletComponentTotal = orderedContributions
                .compactMap { contribution in
                    contribution.componentMolarFlows.first {
                        $0.component == flow.component
                    }?.molarFlowMolesPerSecond
                }
                .reduce(0, +)
            return max(
                maximum,
                relativeResidual(flow.molarFlowMolesPerSecond, expected: inletComponentTotal)
            )
        }

        let summedStreamMassFlow = orderedContributions
            .reduce(0) { $0 + $1.massFlowKilogramsPerSecond }
        let totalMassResidual = abs(totalMassFlow - summedStreamMassFlow)

        var maximumMassBasisResidual = 0.0
        var maximumMassBasisRelativeResidual = 0.0
        for contribution in orderedContributions where contribution.input.flowBasis == .mass {
            guard let enteredMassFlow = contribution.input.flowUnit.kilogramsPerSecond(
                from: contribution.input.flowValue
            ) else {
                maximumMassBasisResidual = .infinity
                maximumMassBasisRelativeResidual = .infinity
                continue
            }
            let residual = abs(contribution.massFlowKilogramsPerSecond - enteredMassFlow)
            maximumMassBasisResidual = max(maximumMassBasisResidual, residual)
            maximumMassBasisRelativeResidual = max(
                maximumMassBasisRelativeResidual,
                relativeResidual(contribution.massFlowKilogramsPerSecond, expected: enteredMassFlow)
            )
        }

        return StreamMixingConservationCheck(
            molarFlowAbsoluteTolerance: tolerances.molarFlowAbsoluteTolerance,
            molarFlowRelativeTolerance: tolerances.molarFlowRelativeTolerance,
            massFlowAbsoluteTolerance: tolerances.massFlowAbsoluteTolerance,
            massFlowRelativeTolerance: tolerances.massFlowRelativeTolerance,
            componentMolarFlowAbsoluteTolerance:
                tolerances.componentMolarFlowAbsoluteTolerance,
            componentMolarFlowRelativeTolerance:
                tolerances.componentMolarFlowRelativeTolerance,
            totalMolarFlowResidual: totalMolarResidual,
            totalMolarFlowRelativeResidual: relativeResidual(
                totalMolarFlow,
                expected: summedStreamMolarFlow
            ),
            maximumComponentMolarFlowResidual: maximumComponentResidual,
            maximumComponentMolarFlowRelativeResidual: maximumComponentRelativeResidual,
            totalMassFlowResidual: totalMassResidual,
            totalMassFlowRelativeResidual: relativeResidual(
                totalMassFlow,
                expected: summedStreamMassFlow
            ),
            maximumMassBasisInletMassFlowResidual: maximumMassBasisResidual,
            maximumMassBasisInletMassFlowRelativeResidual:
                maximumMassBasisRelativeResidual
        )
    }

    private func relativeResidual(_ actual: Double, expected: Double) -> Double {
        let denominator = max(abs(actual), abs(expected), Double.leastNonzeroMagnitude)
        return abs(actual - expected) / denominator
    }

    private func mixtureMolarMassKilogramsPerMole(
        _ composition: [MixtureComponent]
    ) -> Double? {
        guard !composition.isEmpty,
              composition.allSatisfy({
                  $0.moleFraction.isFinite && $0.moleFraction >= 0
              })
        else { return nil }
        let total = composition.reduce(0) { $0 + $1.moleFraction }
        guard total.isFinite,
              abs(total - 1) <= CalculationValidator.compositionTolerance
        else { return nil }

        var molarMass = 0.0
        for item in composition where item.moleFraction > 0 {
            guard let componentMass = item.component.molarMassKilogramsPerMole else {
                return nil
            }
            molarMass += item.moleFraction * componentMass
        }
        return molarMass.isFinite && molarMass > 0 ? molarMass : nil
    }

    private func warnings(for streams: [InletStreamInput]) -> [StreamMixingWarning] {
        let finitePressures = streams.map(\.pressurePa).filter(\.isFinite)
        guard let minimum = finitePressures.min(),
              let maximum = finitePressures.max(),
              maximum - minimum > Self.pressureComparisonTolerancePa
        else { return [] }
        return [
            StreamMixingWarning(
                code: .inletPressureDifference,
                message: "Inlet pressures differ. Stream Mixing v1 records this difference but does not model pressure equalization or alter the user-defined outlet pressure."
            )
        ]
    }

    private func assumptions(
        acceptedNormalizedStreamIDs: [UUID]
    ) -> [StreamMixingAssumption] {
        var assumptions = [
            StreamMixingAssumption(
                code: .compositionOnlyMixing,
                message: "Stream Mixing v1 conserves component molar flows and calculates only the mixed composition and flow totals."
            ),
            StreamMixingAssumption(
                code: .userDefinedOutletState,
                message: "Outlet pressure and temperature are supplied explicitly by the user."
            ),
            StreamMixingAssumption(
                code: .noEnergyBalance,
                message: "Inlet temperatures are retained for traceability but are not used in an energy balance; v1 is not enthalpy-balanced and does not calculate heat transfer, phase separation or outlet temperature."
            )
        ]
        for streamID in acceptedNormalizedStreamIDs {
            assumptions.append(StreamMixingAssumption(
                code: .explicitCompositionNormalization,
                streamID: streamID,
                message: "This stream used an explicitly accepted normalized composition recorded in provenance."
            ))
        }
        return assumptions
    }

    private func blockedResult(
        request: StreamMixingRequest,
        warnings: [StreamMixingWarning],
        assumptions: [StreamMixingAssumption],
        issues: [StreamMixingValidationIssue]
    ) -> MixedCompositionResult {
        MixedCompositionResult(
            requestID: request.requestID,
            status: .blocked,
            outlet: request.outlet,
            composition: [],
            totalMassFlowKilogramsPerSecond: 0,
            totalMolarFlowMolesPerSecond: 0,
            componentMolarFlows: [],
            streamContributions: [],
            conservation: StreamMixingConservationCheck(
                molarFlowAbsoluteTolerance: tolerances.molarFlowAbsoluteTolerance,
                molarFlowRelativeTolerance: tolerances.molarFlowRelativeTolerance,
                massFlowAbsoluteTolerance: tolerances.massFlowAbsoluteTolerance,
                massFlowRelativeTolerance: tolerances.massFlowRelativeTolerance,
                componentMolarFlowAbsoluteTolerance:
                    tolerances.componentMolarFlowAbsoluteTolerance,
                componentMolarFlowRelativeTolerance:
                    tolerances.componentMolarFlowRelativeTolerance,
                totalMolarFlowResidual: .infinity,
                totalMolarFlowRelativeResidual: .infinity,
                maximumComponentMolarFlowResidual: .infinity,
                maximumComponentMolarFlowRelativeResidual: .infinity,
                totalMassFlowResidual: .infinity,
                totalMassFlowRelativeResidual: .infinity,
                maximumMassBasisInletMassFlowResidual: .infinity,
                maximumMassBasisInletMassFlowRelativeResidual: .infinity
            ),
            warnings: warnings,
            assumptions: assumptions,
            validationIssues: issues
        )
    }

    private func issue(
        _ code: StreamMixingValidationCode,
        field: StreamMixingField,
        stream: InletStreamInput,
        message: String
    ) -> StreamMixingValidationIssue {
        StreamMixingValidationIssue(
            code: code,
            field: field,
            streamID: stream.id,
            streamName: stream.name,
            message: message
        )
    }

    private func aggregationIssue(
        stream: InletStreamInput,
        message: String
    ) -> StreamMixingValidationIssue {
        issue(.invalidTotalMolarFlow, field: .aggregation, stream: stream, message: message)
    }
}
