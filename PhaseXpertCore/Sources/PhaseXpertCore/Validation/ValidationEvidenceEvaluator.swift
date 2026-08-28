import Foundation

public enum ValidationEvidenceStatus: String, Codable, Equatable, Sendable {
    case independentlyValidated
    case nearby
    case unavailable
}

public struct ValidationEvidenceDelta: Codable, Equatable, Sendable {
    public let compositionMoleFraction: [ComponentID: Double]
    public let temperatureK: Double
    public let pressurePa: Double
}

public struct PropertyValidationEvidence: Codable, Equatable, Sendable {
    public let property: PropertyID
    public let status: ValidationEvidenceStatus
    public let formulationID: String?
    public let formulationName: String?
    public let validationArtifact: String?
    public let validationSummary: String?
    public let accuracySummary: String?
    public let deltas: ValidationEvidenceDelta?
}

/// Property-specific evidence derived exclusively from production capability metadata.
/// Nearby matches are informational and never change a production capability decision.
public struct ValidationEvidenceEvaluator: Sendable {
    public static let nearbyCompositionLimit = 0.005 // 0.5 mol% per component
    public static let nearbyTemperatureLimitK = 5.0
    public static let nearbyPressureLimitPa = 1_000_000.0

    public init() {}

    public func evaluate(
        composition: [MixtureComponent],
        pressurePa: Double,
        temperatureK: Double,
        properties: Set<PropertyID> = Set(PropertyID.allCases)
    ) -> [PropertyValidationEvidence] {
        guard let canonical = try? CanonicalComposition(composition) else {
            return properties.map { unavailable($0) }.sorted(by: order)
        }
        let matrix = AdvancedCCSCapabilityMatrix()
        return properties.map { property in
            let decision = matrix.decision(
                for: canonical,
                property: property,
                pressurePa: pressurePa,
                temperatureK: temperatureK
            )
            if decision.validationState == .validated,
               let formulationID = decision.formulationID,
               let formulation = TeqpFormulationCatalog.productionFormulations.first(where: { $0.id == formulationID }),
               let capability = capability(for: property, in: formulation) {
                return evidence(property, .independentlyValidated, formulation, capability, nil)
            }
            return nearestEvidence(
                property: property,
                canonical: canonical,
                pressurePa: pressurePa,
                temperatureK: temperatureK
            ) ?? unavailable(property)
        }.sorted(by: order)
    }

    private func nearestEvidence(
        property: PropertyID,
        canonical: CanonicalComposition,
        pressurePa: Double,
        temperatureK: Double
    ) -> PropertyValidationEvidence? {
        let candidates = TeqpFormulationCatalog.productionFormulations.compactMap { formulation -> PropertyValidationEvidence? in
            guard formulation.components == canonical.componentSet,
                  let capability = capability(for: property, in: formulation) else { return nil }
            let compositionDeltas = Dictionary(uniqueKeysWithValues: capability.compositionLimits.map { limit in
                let value = canonical.moleFraction(of: limit.component) ?? 0
                return (limit.component, distance(value, limit.minimumMoleFraction...limit.maximumMoleFraction))
            })
            guard compositionDeltas.values.allSatisfy({ $0 <= Self.nearbyCompositionLimit }) else { return nil }
            let nominalTolerance = nominalTemperatureTolerance(for: formulation)
            let ranges = capability.isothermPressureLimits.map { limit -> ValidationEvidenceDelta in
                let temperatureDistance = max(0, distance(temperatureK, limit.minimumTemperatureK...limit.maximumTemperatureK) - nominalTolerance)
                return ValidationEvidenceDelta(
                    compositionMoleFraction: compositionDeltas,
                    temperatureK: temperatureDistance,
                    pressurePa: distance(pressurePa, limit.minimumPressurePa...limit.maximumPressurePa)
                )
            }
            guard let nearest = ranges.min(by: { score($0) < score($1) }),
                  nearest.temperatureK <= Self.nearbyTemperatureLimitK,
                  nearest.pressurePa <= Self.nearbyPressureLimitPa,
                  nearest.compositionMoleFraction.values.contains(where: { $0 > CalculationValidator.compositionTolerance })
                    || nearest.temperatureK > 0
                    || nearest.pressurePa > 0 else { return nil }
            return evidence(property, .nearby, formulation, capability, nearest)
        }
        return candidates.min {
            score($0.deltas!) < score($1.deltas!)
                || (score($0.deltas!) == score($1.deltas!) && ($0.formulationID ?? "") < ($1.formulationID ?? ""))
        }
    }

    private func capability(for property: PropertyID, in formulation: TeqpFormulation) -> TeqpPropertyCapability? {
        if let direct = formulation.propertyCapabilities.first(where: { $0.property == property }) { return direct }
        if [.molarMass, .specificVolume, .compressibilityFactor].contains(property) {
            return formulation.propertyCapabilities.first(where: { $0.property == .density })
        }
        return nil
    }

    private func evidence(_ property: PropertyID, _ status: ValidationEvidenceStatus, _ formulation: TeqpFormulation, _ capability: TeqpPropertyCapability, _ deltas: ValidationEvidenceDelta?) -> PropertyValidationEvidence {
        .init(property: property, status: status, formulationID: formulation.id, formulationName: formulation.name,
              validationArtifact: capability.validationArtifact, validationSummary: capability.validationSummary,
              accuracySummary: capability.accuracySummary, deltas: deltas)
    }

    private func unavailable(_ property: PropertyID) -> PropertyValidationEvidence {
        .init(property: property, status: .unavailable, formulationID: nil, formulationName: nil,
              validationArtifact: nil, validationSummary: nil, accuracySummary: nil, deltas: nil)
    }

    private func distance(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        value < range.lowerBound ? range.lowerBound - value : (value > range.upperBound ? value - range.upperBound : 0)
    }

    private func score(_ delta: ValidationEvidenceDelta) -> Double {
        (delta.compositionMoleFraction.values.max() ?? 0) / Self.nearbyCompositionLimit
            + delta.temperatureK / Self.nearbyTemperatureLimitK
            + delta.pressurePa / Self.nearbyPressureLimitPa
    }

    private func nominalTemperatureTolerance(for formulation: TeqpFormulation) -> Double {
        if formulation.components.count > 2 { return TeqpFormulationCatalog.multicomponentNominalIsothermToleranceK }
        if formulation.id == TeqpFormulationCatalog.co2HydrogenEOSCGGasDensity.id { return TeqpFormulationCatalog.co2HydrogenNominalIsothermToleranceK }
        if formulation.id == TeqpFormulationCatalog.co2OxygenEOSCGGasDensity.id { return TeqpFormulationCatalog.co2OxygenNominalIsothermToleranceK }
        if formulation.id == TeqpFormulationCatalog.co2OxygenEOSCGDenseSpeedOfSound.id { return TeqpFormulationCatalog.multicomponentNominalIsothermToleranceK }
        return 0
    }

    private func order(_ lhs: PropertyValidationEvidence, _ rhs: PropertyValidationEvidence) -> Bool {
        lhs.property.rawValue < rhs.property.rawValue
    }
}
