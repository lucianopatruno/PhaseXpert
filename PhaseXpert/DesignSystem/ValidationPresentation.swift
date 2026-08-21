import Foundation
import PhaseXpertCore

struct ValidatedCompositionOption: Identifiable, Equatable {
    let id: String
    let name: String
    let composition: [MixtureComponent]
    let properties: [PropertyID]
}

struct ValidatedStateOption: Identifiable, Equatable {
    let id: String
    let name: String
    let composition: [MixtureComponent]
    let properties: [PropertyID]
    let pressurePa: Double
    let temperatureK: Double
    let phaseDomain: TeqpPhaseDomain?
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
        exactCompositionOptions().sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    static func stateOptions(
        currentPressurePa: Double?,
        currentTemperatureK: Double?
    ) -> [ValidatedStateOption] {
        exactCompositionOptions().compactMap { option in
            representativeState(
                for: option,
                currentPressurePa: currentPressurePa,
                currentTemperatureK: currentTemperatureK
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
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

    private static func exactCompositionOptions() -> [ValidatedCompositionOption] {
        var options: [ValidatedCompositionOption] = []
        for formulation in TeqpFormulationCatalog.productionFormulations
            where formulation.components.count > 1 {
            guard let option = exactCompositionOption(for: formulation) else { continue }
            if let index = options.firstIndex(where: { $0.id == option.id }) {
                let merged = Set(options[index].properties).union(option.properties)
                options[index] = .init(
                    id: option.id,
                    name: options[index].name,
                    composition: options[index].composition,
                    properties: merged.sorted { $0.displayName < $1.displayName }
                )
            } else {
                options.append(option)
            }
        }
        return options
    }

    private static func representativeState(
        for option: ValidatedCompositionOption,
        currentPressurePa: Double?,
        currentTemperatureK: Double?
    ) -> ValidatedStateOption? {
        guard let formulation = formulation(for: option),
              let capability = formulation.propertyCapabilities.first(where: {
                  !$0.isothermPressureLimits.isEmpty
              }),
              let limit = representativeLimit(
                  capability: capability,
                  currentPressurePa: currentPressurePa,
                  currentTemperatureK: currentTemperatureK,
                  nominalTemperatureToleranceK: nominalTemperatureTolerance(for: formulation)
              ) else {
            return nil
        }

        let temperatureK: Double
        if let currentTemperatureK,
           limit.containsTemperature(
            currentTemperatureK,
            nominalToleranceK: nominalTemperatureTolerance(for: formulation)
           ) {
            temperatureK = currentTemperatureK
        } else {
            temperatureK = limit.temperatureK
        }

        let pressurePa: Double
        if let currentPressurePa,
           (limit.minimumPressurePa...limit.maximumPressurePa).contains(currentPressurePa) {
            pressurePa = currentPressurePa
        } else {
            pressurePa = (limit.minimumPressurePa + limit.maximumPressurePa) / 2
        }

        return ValidatedStateOption(
            id: option.id,
            name: option.name,
            composition: option.composition,
            properties: option.properties,
            pressurePa: pressurePa,
            temperatureK: temperatureK,
            phaseDomain: capability.phaseDomain
        )
    }

    private static func representativeLimit(
        capability: TeqpPropertyCapability,
        currentPressurePa: Double?,
        currentTemperatureK: Double?,
        nominalTemperatureToleranceK: Double
    ) -> TeqpTemperaturePressureLimit? {
        if let currentTemperatureK,
           let currentPressurePa,
           let currentLimit = capability.isothermPressureLimits.first(where: {
               $0.contains(
                   temperatureK: currentTemperatureK,
                   pressurePa: currentPressurePa,
                   nominalTemperatureToleranceK: nominalTemperatureToleranceK
               )
           }) {
            return currentLimit
        }

        if let currentTemperatureK,
           let temperatureLimit = capability.isothermPressureLimits.first(where: {
               $0.containsTemperature(
                   currentTemperatureK,
                   nominalToleranceK: nominalTemperatureToleranceK
               )
           }) {
            return temperatureLimit
        }

        return capability.isothermPressureLimits.first
    }

    private static func formulation(
        for option: ValidatedCompositionOption
    ) -> TeqpFormulation? {
        TeqpFormulationCatalog.productionFormulations.first {
            exactCompositionOption(for: $0)?.id == option.id
                && !$0.propertyCapabilities.isEmpty
        }
    }

    private static func exactCompositionOption(
        for formulation: TeqpFormulation
    ) -> ValidatedCompositionOption? {
        let exactLimits = formulation.compositionLimits.filter {
            abs($0.minimumMoleFraction - $0.maximumMoleFraction)
                <= CalculationValidator.compositionTolerance
        }
        guard exactLimits.count == formulation.compositionLimits.count else { return nil }

        var composition = exactLimits.map {
            MixtureComponent(component: $0.component, moleFraction: $0.minimumMoleFraction)
        }
        if formulation.components.contains(.carbonDioxide),
           !composition.contains(where: { $0.component == .carbonDioxide }) {
            let remainder = 1 - composition.reduce(0) { $0 + $1.moleFraction }
            guard remainder >= 0 else { return nil }
            composition.append(.init(component: .carbonDioxide, moleFraction: remainder))
        }
        guard Set(composition.map(\.component)) == formulation.components,
              (try? CanonicalComposition(composition)) != nil else { return nil }

        let key = composition
            .sorted { $0.component.rawValue < $1.component.rawValue }
            .map { "\($0.component.rawValue):\($0.moleFraction)" }
            .joined(separator: "|")
        return ValidatedCompositionOption(
            id: key,
            name: compositionName(composition),
            composition: composition,
            properties: formulation.supportedProperties.sorted {
                $0.displayName < $1.displayName
            }
        )
    }

    private static func nominalTemperatureTolerance(
        for formulation: TeqpFormulation
    ) -> Double {
        if formulation.components.count > 2 {
            return TeqpFormulationCatalog.multicomponentNominalIsothermToleranceK
        }
        if formulation.id == TeqpFormulationCatalog.co2OxygenEOSCGGasDensity.id {
            return TeqpFormulationCatalog.co2OxygenNominalIsothermToleranceK
        }
        if formulation.id == TeqpFormulationCatalog.co2OxygenEOSCGDenseSpeedOfSound.id {
            return TeqpFormulationCatalog.multicomponentNominalIsothermToleranceK
        }
        return 0
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
