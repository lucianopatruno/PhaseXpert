import Foundation
import PhaseXpertCore

struct ValidatedCompositionOption: Identifiable, Equatable {
    let id: String
    let name: String
    let composition: [MixtureComponent]
    let properties: [PropertyID]
}

enum AdvancedValidationPresentation {
    static func validatedProperties(
        composition: [MixtureComponent],
        pressurePa: Double,
        temperatureK: Double
    ) -> [PropertyID] {
        guard let canonical = try? CanonicalComposition(composition) else { return [] }
        let matrix = AdvancedCCSCapabilityMatrix()
        return PropertyID.allCases.filter {
            matrix.decision(
                for: canonical,
                property: $0,
                pressurePa: pressurePa,
                temperatureK: temperatureK
            ).validationState == .validated
        }
    }

    static func validatedProperties(for record: CalculationRecord) -> [PropertyID] {
        guard record.request.modelID == "teqp-pure-co2-experimental" else { return [] }
        return validatedProperties(
            composition: record.request.composition,
            pressurePa: record.request.pressurePa,
            temperatureK: record.request.temperatureK
        )
    }

    static func savedCaseStatus(for record: CalculationRecord) -> String {
        guard record.request.modelID == "teqp-pure-co2-experimental" else {
            return "General Properties"
        }
        let properties = validatedProperties(for: record)
        guard !properties.isEmpty else { return "Advanced CCS · Outside validated range" }
        return "Advanced CCS · Validated \(propertyList(properties))"
    }

    static func compositionOptions() -> [ValidatedCompositionOption] {
        var options: [ValidatedCompositionOption] = []
        for formulation in TeqpFormulationCatalog.productionFormulations
            where formulation.components.count > 1 {
            let exactLimits = formulation.compositionLimits.filter {
                abs($0.minimumMoleFraction - $0.maximumMoleFraction)
                    <= CalculationValidator.compositionTolerance
            }
            guard exactLimits.count == formulation.compositionLimits.count else { continue }

            var composition = exactLimits.map {
                MixtureComponent(component: $0.component, moleFraction: $0.minimumMoleFraction)
            }
            if formulation.components.contains(.carbonDioxide),
               !composition.contains(where: { $0.component == .carbonDioxide }) {
                let remainder = 1 - composition.reduce(0) { $0 + $1.moleFraction }
                guard remainder >= 0 else { continue }
                composition.append(.init(component: .carbonDioxide, moleFraction: remainder))
            }
            guard Set(composition.map(\.component)) == formulation.components,
                  (try? CanonicalComposition(composition)) != nil else { continue }

            let key = composition
                .sorted { $0.component.rawValue < $1.component.rawValue }
                .map { "\($0.component.rawValue):\($0.moleFraction)" }
                .joined(separator: "|")
            if let index = options.firstIndex(where: { $0.id == key }) {
                let merged = Set(options[index].properties).union(formulation.supportedProperties)
                options[index] = .init(
                    id: key,
                    name: options[index].name,
                    composition: options[index].composition,
                    properties: merged.sorted { $0.displayName < $1.displayName }
                )
            } else {
                options.append(.init(
                    id: key,
                    name: compositionName(composition),
                    composition: composition,
                    properties: formulation.supportedProperties.sorted {
                        $0.displayName < $1.displayName
                    }
                ))
            }
        }
        return options.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func propertyList(_ properties: [PropertyID]) -> String {
        let labels = properties.map { property -> String in
            switch property {
            case .molarMass: "M"
            case .specificVolume: "v"
            case .compressibilityFactor: "Z"
            default: property.displayName
            }
        }
        return labels.joined(separator: " · ")
    }

    private static func compositionName(_ composition: [MixtureComponent]) -> String {
        let impurities = composition
            .filter { $0.component != .carbonDioxide && $0.moleFraction > 0 }
            .sorted { $0.component.rawValue < $1.component.rawValue }
            .map {
                "\($0.component.symbol) \(($0.moleFraction * 100).formatted(.number.precision(.significantDigits(1...6)))) mol%"
            }
        return impurities.isEmpty ? "Pure CO₂" : impurities.joined(separator: " + ")
    }
}
