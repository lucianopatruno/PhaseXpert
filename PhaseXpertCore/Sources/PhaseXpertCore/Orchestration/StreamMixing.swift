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
    public let normalizedComposition: [MixtureComponent]?

    public init(stream: InletStreamInput) {
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
        self.normalizedComposition = stream.normalizedComposition
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
    case normalizationRequired
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
    public let tolerance: Double
    public let totalMolarFlowResidual: Double
    public let maximumComponentMolarFlowResidual: Double
    public let totalMassFlowResidual: Double

    public var isConserved: Bool {
        abs(totalMolarFlowResidual) <= tolerance
            && abs(maximumComponentMolarFlowResidual) <= tolerance
            && abs(totalMassFlowResidual) <= tolerance
    }

    public init(
        tolerance: Double,
        totalMolarFlowResidual: Double,
        maximumComponentMolarFlowResidual: Double,
        totalMassFlowResidual: Double
    ) {
        self.tolerance = tolerance
        self.totalMolarFlowResidual = totalMolarFlowResidual
        self.maximumComponentMolarFlowResidual = maximumComponentMolarFlowResidual
        self.totalMassFlowResidual = totalMassFlowResidual
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
    public static let conservationTolerance = 1e-9
    public static let pressureComparisonTolerancePa = 1.0

    private let validator: CalculationValidator
    private let domain: ScientificDomain
    private let supportedComponents: Set<ComponentID>

    public init(
        validator: CalculationValidator = CalculationValidator(),
        domain: ScientificDomain = .initialCO2Transport,
        supportedComponents: Set<ComponentID> = Set(ComponentID.allCases)
    ) {
        self.validator = validator
        self.domain = domain
        self.supportedComponents = supportedComponents
    }

    public func validate(_ request: StreamMixingRequest) -> StreamMixingValidationReport {
        StreamMixingValidationReport(issues: validationIssues(for: request))
    }

    public func mix(_ request: StreamMixingRequest) -> MixedCompositionResult {
        let initialIssues = validationIssues(for: request)
        let warnings = warnings(for: request.streams)
        let assumptions = assumptions(for: request.streams)
        if !initialIssues.isEmpty {
            return blockedResult(
                request: request,
                warnings: warnings,
                assumptions: assumptions,
                issues: initialIssues
            )
        }

        var streamContributions: [StreamMixingStreamContribution] = []
        var componentTotals: [ComponentID: Double] = [:]

        for stream in request.streams {
            guard
                let molarFlow = molarFlowMolesPerSecond(for: stream),
                molarFlow.isFinite,
                molarFlow > 0
            else {
                return blockedResult(
                    request: request,
                    warnings: warnings,
                    assumptions: assumptions,
                    issues: [aggregationIssue(
                        stream: stream,
                        message: "Stream total molar flow was non-finite or non-positive."
                    )]
                )
            }

            let componentFlows = componentFlowValues(
                composition: stream.composition,
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
                    assumptions: assumptions,
                    issues: [aggregationIssue(
                        stream: stream,
                        message: "Stream component flow calculation produced a non-finite value."
                    )]
                )
            }

            for componentFlow in componentFlows {
                componentTotals[componentFlow.component, default: 0] +=
                    componentFlow.molarFlowMolesPerSecond
            }

            streamContributions.append(StreamMixingStreamContribution(
                streamID: stream.id,
                streamName: stream.name,
                input: OriginalStreamInputSnapshot(stream: stream),
                massFlowKilogramsPerSecond: massFlow,
                molarFlowMolesPerSecond: molarFlow,
                componentMolarFlows: componentFlows
            ))
        }

        let totalMolarFlow = streamContributions.reduce(0) {
            $0 + $1.molarFlowMolesPerSecond
        }
        guard totalMolarFlow.isFinite, totalMolarFlow > 0 else {
            return blockedResult(
                request: request,
                warnings: warnings,
                assumptions: assumptions,
                issues: [StreamMixingValidationIssue(
                    code: .invalidTotalMolarFlow,
                    field: .aggregation,
                    message: "Total mixed molar flow was non-finite or non-positive."
                )]
            )
        }

        let componentMolarFlows = orderedComponentFlows(componentTotals)
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
                assumptions: assumptions,
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
                assumptions: assumptions,
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
                assumptions: assumptions,
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
            assumptions: assumptions,
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

        let report = validator.validate(
            pressurePa: stream.pressurePa,
            temperatureK: stream.temperatureK,
            composition: stream.composition,
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
        if let normalized = stream.normalizedComposition, normalized != stream.composition {
            issues.append(issue(
                .invalidComposition,
                field: .composition,
                stream: stream,
                message: "Recorded normalized composition must match the canonical stream composition."
            ))
        }
        issues.append(contentsOf: missingMolarMassIssues(for: stream))
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

    private func missingMolarMassIssues(
        for stream: InletStreamInput
    ) -> [StreamMixingValidationIssue] {
        var missing = Set<ComponentID>()
        for component in stream.composition
            where component.moleFraction > 0
                && component.component.molarMassKilogramsPerMole == nil
        {
            missing.insert(component.component)
        }
        for entry in stream.originalComposition
            where entry.unit == .massFraction
                && entry.value > 0
                && entry.component.molarMassKilogramsPerMole == nil
        {
            missing.insert(entry.component)
        }
        return missing.sorted { $0.rawValue < $1.rawValue }.map { component in
            issue(
                .missingMolarMass,
                field: .molarMass,
                stream: stream,
                message: "No reviewed molar mass is configured for \(component.symbol)."
            )
        }
    }

    private func molarFlowMolesPerSecond(for stream: InletStreamInput) -> Double? {
        switch stream.flowBasis {
        case .molar:
            return stream.flowUnit.molesPerSecond(from: stream.flowValue)
        case .mass:
            guard
                let massFlow = stream.flowUnit.kilogramsPerSecond(from: stream.flowValue),
                let molarMass = mixtureMolarMassKilogramsPerMole(stream.composition),
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
        _ totals: [ComponentID: Double]
    ) -> [StreamMixingComponentMolarFlow] {
        totals
            .filter { $0.value > 0 }
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { component, molarFlow in
                StreamMixingComponentMolarFlow(
                    component: component,
                    molarFlowMolesPerSecond: molarFlow,
                    massFlowKilogramsPerSecond: molarFlow
                        * (component.molarMassKilogramsPerMole ?? .nan)
                )
            }
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

    private func conservationCheck(
        componentMolarFlows: [StreamMixingComponentMolarFlow],
        streamContributions: [StreamMixingStreamContribution],
        totalMolarFlow: Double,
        totalMassFlow: Double
    ) -> StreamMixingConservationCheck {
        let summedStreamMolarFlow = streamContributions.reduce(0) {
            $0 + $1.molarFlowMolesPerSecond
        }
        let componentTotalMolarFlow = componentMolarFlows.reduce(0) {
            $0 + $1.molarFlowMolesPerSecond
        }
        let componentTotalMassFlow = componentMolarFlows.reduce(0) {
            $0 + $1.massFlowKilogramsPerSecond
        }

        let streamComponentTotals = streamContributions
            .flatMap(\.componentMolarFlows)
            .reduce(into: [ComponentID: Double]()) { result, flow in
                result[flow.component, default: 0] += flow.molarFlowMolesPerSecond
            }
        let maximumComponentResidual = componentMolarFlows.reduce(0) { maximum, flow in
            max(
                maximum,
                abs(flow.molarFlowMolesPerSecond - (streamComponentTotals[flow.component] ?? 0))
            )
        }

        return StreamMixingConservationCheck(
            tolerance: Self.conservationTolerance,
            totalMolarFlowResidual: max(
                abs(totalMolarFlow - summedStreamMolarFlow),
                abs(totalMolarFlow - componentTotalMolarFlow)
            ),
            maximumComponentMolarFlowResidual: maximumComponentResidual,
            totalMassFlowResidual: abs(totalMassFlow - componentTotalMassFlow)
        )
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

    private func assumptions(for streams: [InletStreamInput]) -> [StreamMixingAssumption] {
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
        for stream in streams where stream.normalizedComposition != nil {
            assumptions.append(StreamMixingAssumption(
                code: .explicitCompositionNormalization,
                streamID: stream.id,
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
                tolerance: Self.conservationTolerance,
                totalMolarFlowResidual: .infinity,
                maximumComponentMolarFlowResidual: .infinity,
                totalMassFlowResidual: .infinity
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
