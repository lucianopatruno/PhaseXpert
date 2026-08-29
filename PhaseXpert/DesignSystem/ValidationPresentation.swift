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
    let detail: String
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
        return orderedProperties(PropertyID.allCases.filter {
            matrix.decision(
                for: canonical,
                property: $0,
                pressurePa: pressurePa,
                temperatureK: temperatureK
            ).validationState == .validated
        })
    }

    static func validatedProperties(for record: CalculationRecord) -> [PropertyID] {
        return validatedProperties(
            composition: record.request.composition,
            pressurePa: record.request.pressurePa,
            temperatureK: record.request.temperatureK
        )
    }

    static func savedCaseStatus(for record: CalculationRecord) -> String {
        let properties = validatedProperties(for: record)
        guard !properties.isEmpty else { return "General Properties · No independent validation available" }
        return "General Properties · Independently validated \(propertyList(properties))"
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
        TeqpFormulationCatalog.productionFormulations
            .filter { $0.components.count > 1 }
            .flatMap { formulation in
                formulation.propertyCapabilities.compactMap { capability in
                    representativeState(
                        formulation: formulation,
                        capability: capability,
                        currentPressurePa: currentPressurePa,
                        currentTemperatureK: currentTemperatureK
                    )
                }
            }
            .sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
                    || ($0.name == $1.name && $0.detail.localizedStandardCompare($1.detail) == .orderedAscending)
        }
    }

    static func validatedCaseOptions() -> [ValidatedStateOption] {
        stateOptions(currentPressurePa: nil, currentTemperatureK: nil)
    }

    static func propertyList(_ properties: [PropertyID]) -> String {
        let labels = orderedProperties(properties).map { property -> String in
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
                    properties: orderedProperties(Array(merged))
                )
            } else {
                options.append(option)
            }
        }
        return options
    }

    private static func representativeState(
        formulation: TeqpFormulation,
        capability: TeqpPropertyCapability,
        currentPressurePa: Double?,
        currentTemperatureK: Double?
    ) -> ValidatedStateOption? {
        guard let option = exactCompositionOption(
            for: formulation,
            capability: capability
        ),
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
            pressurePa = limit.minimumPressurePa
        }

        return ValidatedStateOption(
            id: "\(formulation.id)|\(capability.property.rawValue)|\(capability.validationArtifact)",
            name: "Validated \(propertyList(presentationProperties(for: capability, formulation: formulation)).lowercased()) state",
            detail: "\(option.name) · \(temperatureSummary(limit)) · \(pressureSummary(limit))",
            composition: option.composition,
            properties: presentationProperties(for: capability, formulation: formulation),
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
            properties: orderedProperties(Array(formulation.supportedProperties))
        )
    }

    private static func exactCompositionOption(
        for formulation: TeqpFormulation,
        capability: TeqpPropertyCapability
    ) -> ValidatedCompositionOption? {
        let exactLimits = capability.compositionLimits.filter {
            abs($0.minimumMoleFraction - $0.maximumMoleFraction)
                <= CalculationValidator.compositionTolerance
        }
        guard exactLimits.count == capability.compositionLimits.count else { return nil }

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
            properties: presentationProperties(for: capability, formulation: formulation)
        )
    }

    private static func nominalTemperatureTolerance(
        for formulation: TeqpFormulation
    ) -> Double {
        if formulation.components.count > 2 {
            return TeqpFormulationCatalog.multicomponentNominalIsothermToleranceK
        }
        if formulation.id == TeqpFormulationCatalog.co2HydrogenEOSCGGasDensity.id {
            return TeqpFormulationCatalog.co2HydrogenNominalIsothermToleranceK
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

    private static func orderedProperties(_ properties: [PropertyID]) -> [PropertyID] {
        let order: [PropertyID] = [
            .density,
            .molarMass,
            .specificVolume,
            .compressibilityFactor,
            .speedOfSound
        ]
        return properties.sorted { lhs, rhs in
            let lhsIndex = order.firstIndex(of: lhs) ?? order.count
            let rhsIndex = order.firstIndex(of: rhs) ?? order.count
            if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }

    private static func presentationProperties(
        for capability: TeqpPropertyCapability,
        formulation: TeqpFormulation
    ) -> [PropertyID] {
        if capability.property == .density {
            return orderedProperties([
                .density,
                .molarMass,
                .specificVolume,
                .compressibilityFactor
            ].filter { formulation.supportedProperties.contains($0) })
        }
        return orderedProperties([capability.property])
    }

    private static func temperatureSummary(_ limit: TeqpTemperaturePressureLimit) -> String {
        if abs(limit.minimumTemperatureK - limit.maximumTemperatureK) <= 1e-9 {
            return "T \(celsius(limit.temperatureK)) °C"
        }
        return "T \(celsius(limit.minimumTemperatureK))–\(celsius(limit.maximumTemperatureK)) °C"
    }

    private static func pressureSummary(_ limit: TeqpTemperaturePressureLimit) -> String {
        let minimum = limit.minimumPressurePa / 100_000
        let maximum = limit.maximumPressurePa / 100_000
        return "P \(minimum.formatted(.number.precision(.fractionLength(1...3))))–\(maximum.formatted(.number.precision(.fractionLength(1...3)))) bar(a)"
    }

    private static func celsius(_ kelvin: Double) -> String {
        (kelvin - 273.15).formatted(.number.precision(.fractionLength(0...2)))
    }
}
