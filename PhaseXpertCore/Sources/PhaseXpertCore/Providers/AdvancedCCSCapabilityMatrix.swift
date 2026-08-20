import Foundation

public enum AdvancedCCSValidationState: String, Codable, Equatable, Sendable {
    case validated
    case preliminaryValidationPending
    case researchOnly
    case unsupported
}

public struct AdvancedCCSCapabilityDecision: Equatable, Sendable {
    public let isSupported: Bool
    public let validationState: AdvancedCCSValidationState
    public let formulationID: String?
    public let property: PropertyID
    public let phaseDomain: TeqpPhaseDomain?
    public let reasons: [String]

    public init(
        isSupported: Bool,
        validationState: AdvancedCCSValidationState,
        formulationID: String?,
        property: PropertyID,
        phaseDomain: TeqpPhaseDomain?,
        reasons: [String]
    ) {
        self.isSupported = isSupported
        self.validationState = validationState
        self.formulationID = formulationID
        self.property = property
        self.phaseDomain = phaseDomain
        self.reasons = reasons
    }
}

public struct AdvancedCCSCapabilityMatrix: Sendable {
    public init() {}

    public func decision(
        for composition: CanonicalComposition,
        property: PropertyID,
        pressurePa: Double? = nil,
        temperatureK: Double? = nil
    ) -> AdvancedCCSCapabilityDecision {
        if composition.componentSet == [.carbonDioxide],
           abs((composition.moleFraction(of: .carbonDioxide) ?? 0) - 1)
            <= CalculationValidator.compositionTolerance {
            return pureCarbonDioxideDecision(property: property)
        }

        for formulation in TeqpFormulationCatalog.productionFormulations
            where formulation.components == composition.componentSet {
            if let decision = binaryDecision(
                formulation: formulation,
                composition: composition,
                property: property,
                pressurePa: pressurePa,
                temperatureK: temperatureK
            ) {
                return decision
            }
        }

        let names = composition.components
            .map { $0.component.symbol }
            .joined(separator: " + ")
        return AdvancedCCSCapabilityDecision(
            isSupported: false,
            validationState: .unsupported,
            formulationID: nil,
            property: property,
            phaseDomain: nil,
            reasons: [
                "No production Advanced CCS formulation is validated for \(names). All active components remain part of the rejected request."
            ]
        )
    }

    private func pureCarbonDioxideDecision(
        property: PropertyID
    ) -> AdvancedCCSCapabilityDecision {
        let formulation = TeqpFormulationCatalog.pureCarbonDioxide
        let supported = formulation.supportedProperties.contains(property)
        return AdvancedCCSCapabilityDecision(
            isSupported: supported,
            validationState: supported ? .preliminaryValidationPending : .unsupported,
            formulationID: supported ? formulation.id : nil,
            property: property,
            phaseDomain: .pureFluid,
            reasons: supported
                ? formulation.limitations
                : ["\(property.rawValue) is not enabled for pure CO₂ Advanced CCS."]
        )
    }

    private func binaryDecision(
        formulation: TeqpFormulation,
        composition: CanonicalComposition,
        property: PropertyID,
        pressurePa: Double?,
        temperatureK: Double?
    ) -> AdvancedCCSCapabilityDecision? {
        guard formulation.supportedProperties.contains(property) else {
            return AdvancedCCSCapabilityDecision(
                isSupported: false,
                validationState: .unsupported,
                formulationID: nil,
                property: property,
                phaseDomain: nil,
                reasons: [
                    "\(property.rawValue) is not production-enabled for \(formulation.name)."
                ]
            )
        }

        let densityCapability = formulation.propertyCapabilities
            .first { $0.property == .density }
        guard let capability = densityCapability else {
            return AdvancedCCSCapabilityDecision(
                isSupported: false,
                validationState: .unsupported,
                formulationID: nil,
                property: property,
                phaseDomain: nil,
                reasons: [
                    "\(formulation.name) has no property-specific production capability metadata."
                ]
            )
        }

        for limit in capability.compositionLimits {
            guard let fraction = composition.moleFraction(of: limit.component),
                  fraction >= limit.minimumMoleFraction - CalculationValidator.compositionTolerance,
                  fraction <= limit.maximumMoleFraction + CalculationValidator.compositionTolerance
            else {
                return AdvancedCCSCapabilityDecision(
                    isSupported: false,
                    validationState: .unsupported,
                    formulationID: nil,
                    property: property,
                    phaseDomain: capability.phaseDomain,
                    reasons: [
                        "\(formulation.name) is validated only for \(limit.component.symbol) mole fraction \(limit.minimumMoleFraction) to \(limit.maximumMoleFraction)."
                    ]
                )
            }
        }

        if let pressurePa, let temperatureK {
            let nominalTemperatureToleranceK: Double
            if formulation.components.count > 2 {
                nominalTemperatureToleranceK = TeqpFormulationCatalog
                    .multicomponentNominalIsothermToleranceK
            } else if formulation.id == TeqpFormulationCatalog.co2OxygenEOSCGGasDensity.id {
                nominalTemperatureToleranceK = TeqpFormulationCatalog
                    .co2OxygenNominalIsothermToleranceK
            } else {
                nominalTemperatureToleranceK = 0
            }
            guard capability.contains(
                temperatureK: temperatureK,
                pressurePa: pressurePa,
                nominalTemperatureToleranceK: nominalTemperatureToleranceK
            ) else {
                return AdvancedCCSCapabilityDecision(
                    isSupported: false,
                    validationState: .unsupported,
                    formulationID: nil,
                    property: property,
                    phaseDomain: capability.phaseDomain,
                    reasons: [
                        "\(formulation.name) is outside its validated temperature/pressure slices for \(property.rawValue)."
                    ]
                )
            }
        }

        return AdvancedCCSCapabilityDecision(
            isSupported: true,
            validationState: .validated,
            formulationID: formulation.id,
            property: property,
            phaseDomain: capability.phaseDomain,
            reasons: [capability.validationSummary, capability.accuracySummary].compactMap { $0 }
        )
    }
}
