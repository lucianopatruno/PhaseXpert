import Foundation
import Observation
import PhaseXpertCore

struct CompositionInput: Identifiable, Equatable {
    let id = UUID()
    var component: ComponentID
    var value: String
}

enum CompositionInputBasis: String, CaseIterable, Identifiable {
    case partsPerMillion = "ppm"
    case molePercent = "mol%"

    var id: String { rawValue }
}

@MainActor
@Observable
final class CalculatorViewModel {
    var pressureText = "150"
    var temperatureText = "20"
    var selectedModelID = "coolprop-heos"
    var compositionBasis: CompositionInputBasis = .partsPerMillion
    var composition: [CompositionInput] = [
        CompositionInput(component: .carbonDioxide, value: "1000000")
    ]
    private(set) var validationReport = ValidationReport(issues: [], normalizedComposition: nil)
    private(set) var calculationRecord: CalculationRecord?
    private(set) var calculationError: String?
    private(set) var isCalculating = false

    let registry = ProviderRegistry()
    private let validator = CalculationValidator()
    private var compositionBeforeNormalization: [CompositionInputSnapshot]?
    private var lastNormalizedComposition: [MixtureComponent]?

    var descriptors: [ModelDescriptor] { registry.descriptors }

    var selectedDescriptor: ModelDescriptor? {
        descriptors.first { $0.id == selectedModelID }
    }

    var canNormalize: Bool {
        false
    }

    var supportedImpurityComponents: [ComponentID] {
        let supported = selectedDescriptor?.supportedComponents ?? []
        return ComponentID.allCases.filter {
            $0 != .carbonDioxide && supported.contains($0)
        }
    }

    func impurityOptions(including current: ComponentID) -> [ComponentID] {
        supportedImpurityComponents.contains(current)
            ? supportedImpurityComponents
            : [current] + supportedImpurityComponents
    }

    @discardableResult
    func addImpurity() -> UUID? {
        let selected = Set(composition.map(\.component))
        guard let component = supportedImpurityComponents.first(where: {
            !selected.contains($0)
        }) else {
            return nil
        }
        let input = CompositionInput(component: component, value: "")
        composition.append(input)
        return input.id
    }

    func updateImpurity(id: UUID, component: ComponentID) {
        guard
            component != .carbonDioxide,
            supportedImpurityComponents.contains(component),
            let index = composition.firstIndex(where: { $0.id == id }),
            composition[index].component != .carbonDioxide
        else {
            return
        }
        composition[index].component = component
        validate()
    }

    func removeImpurity(id: UUID) {
        guard
            let index = composition.firstIndex(where: { $0.id == id }),
            composition[index].component != .carbonDioxide
        else {
            return
        }
        composition.remove(at: index)
        validate()
    }

    func removeImpurities(at offsets: IndexSet) {
        let removableIDs = offsets.compactMap { index -> UUID? in
            guard composition.indices.contains(index) else { return nil }
            let entry = composition[index]
            return entry.component == .carbonDioxide ? nil : entry.id
        }
        for id in removableIDs {
            removeImpurity(id: id)
        }
    }

    func moveImpurities(from source: IndexSet, to destination: Int) {
        composition.move(fromOffsets: source, toOffset: destination)
        if let co2Index = composition.firstIndex(where: { $0.component == .carbonDioxide }), co2Index != 0 {
            let co2 = composition.remove(at: co2Index)
            composition.insert(co2, at: 0)
        }
    }

    func validate() {
        guard
            let pressure = parse(pressureText),
            let temperature = parse(temperatureText),
            let descriptor = selectedDescriptor
        else {
            validationReport = ValidationReport(
                issues: [.init(
                    code: .nonFiniteInput,
                    severity: .error,
                    message: "Enter valid pressure and temperature values."
                )],
                normalizedComposition: nil
            )
            return
        }

        let requestedComposition = domainComposition()
        let supportedComponents = descriptor.availability == .unavailable
            ? Set(requestedComposition.map(\.component))
            : descriptor.supportedComponents
        let coreReport = validator.validate(
            pressurePa: PressureUnit.bar.toPascal(pressure),
            temperatureK: TemperatureUnit.celsius.toKelvin(temperature),
            composition: requestedComposition,
            supportedComponents: supportedComponents,
            domain: descriptor.domain
        )
        var issues = coreReport.issues
        if impurityEnteredTotal > compositionScale {
            let limitMessage = compositionBasis == .partsPerMillion
                ? "Total impurity cannot exceed 1,000,000 ppm; CO₂ is the remainder."
                : "Total impurity cannot exceed 100 mol%; CO₂ is the remainder."
            issues.insert(
                .init(
                    code: .compositionTotal,
                    severity: .error,
                    message: limitMessage
                ),
                at: 0
            )
        }
        if
            descriptor.availability != .unavailable,
            let provider = registry.provider(id: selectedModelID)
        {
            issues.append(contentsOf: provider.applicabilityIssues(for: requestedComposition))
        }
        if descriptor.availability == .unavailable {
            issues.insert(
                .init(
                    code: .modelUnavailable,
                    severity: .error,
                    message: "\(descriptor.name) is not available for calculation."
                ),
                at: 0
            )
        }
        validationReport = ValidationReport(
            issues: issues,
            normalizedComposition: coreReport.normalizedComposition
        )
    }

    func normalizeComposition() {
        guard compositionBasis == .molePercent else { return }
        guard let normalized = validationReport.normalizedComposition else { return }
        compositionBeforeNormalization = compositionSnapshot()
        lastNormalizedComposition = normalized
        composition = normalized.map {
            return CompositionInput(
                component: $0.component,
                value: String(format: "%.8g", $0.moleFraction * 100)
            )
        }
        validate()
    }

    func loadInputs(from record: CalculationRecord) {
        pressureText = String(format: "%.8g", record.input.pressurePa / 100_000)
        temperatureText = String(format: "%.8g", record.input.temperatureK - 273.15)
        if registry.provider(id: record.request.modelID) != nil {
            selectedModelID = record.request.modelID
        }
        if !record.input.originalComposition.isEmpty,
           record.input.originalComposition.allSatisfy({ $0.unit == .partsPerMillion }) {
            compositionBasis = .partsPerMillion
            composition = record.input.originalComposition.map {
                CompositionInput(component: $0.component, value: String(format: "%.12g", $0.value))
            }
        } else {
            compositionBasis = .molePercent
            composition = record.request.composition.map {
                CompositionInput(
                    component: $0.component,
                    value: String(format: "%.8g", $0.moleFraction * 100)
                )
            }
        }
        compositionBeforeNormalization = nil
        lastNormalizedComposition = nil
        calculationRecord = nil
        calculationError = nil
        validate()
    }

    func changeCompositionBasis(to newBasis: CompositionInputBasis) {
        guard newBasis != compositionBasis else { return }
        let oldBasis = compositionBasis
        let oldCarbonDioxideValue = carbonDioxideEnteredValue
        compositionBasis = newBasis
        composition = composition.map { entry in
            let oldValue: Double? = entry.component == .carbonDioxide
                ? oldCarbonDioxideValue
                : parse(entry.value)
            guard let oldValue else {
                return CompositionInput(component: entry.component, value: "")
            }
            let moleFraction = oldValue / (oldBasis == .partsPerMillion ? 1_000_000 : 100)
            return CompositionInput(
                component: entry.component,
                value: String(
                    format: newBasis == .partsPerMillion ? "%.12g" : "%.8g",
                    moleFraction * (newBasis == .partsPerMillion ? 1_000_000 : 100)
                )
            )
        }
        compositionBeforeNormalization = nil
        lastNormalizedComposition = nil
        validate()
    }

    var impurityEnteredTotal: Double {
        composition
            .filter { $0.component != .carbonDioxide }
            .reduce(0) { $0 + (parse($1.value) ?? 0) }
    }

    var carbonDioxideEnteredValue: Double {
        compositionScale - impurityEnteredTotal
    }

    var carbonDioxidePartsPerMillion: Double {
        compositionBasis == .partsPerMillion
            ? carbonDioxideEnteredValue
            : carbonDioxideEnteredValue * 10_000
    }

    var carbonDioxideMolePercent: Double {
        compositionBasis == .molePercent
            ? carbonDioxideEnteredValue
            : carbonDioxideEnteredValue / 10_000
    }

    func displayedCompositionValue(for entry: CompositionInput) -> String {
        guard entry.component == .carbonDioxide else { return entry.value }
        return String(
            format: compositionBasis == .partsPerMillion ? "%.12g" : "%.8g",
            carbonDioxideEnteredValue
        )
    }

    func calculate() async {
        validate()
        guard validationReport.canCalculate else { return }
        guard
            let provider = registry.provider(id: selectedModelID),
            let pressure = parse(pressureText),
            let temperature = parse(temperatureText)
        else { return }

        isCalculating = true
        calculationError = nil
        calculationRecord = nil
        defer { isCalculating = false }

        let pressurePa = PressureUnit.bar.toPascal(pressure)
        let temperatureK = TemperatureUnit.celsius.toKelvin(temperature)
        let calculatedComposition = domainComposition()
        let request = CalculationRequest(
            modelID: selectedModelID,
            pressurePa: pressurePa,
            temperatureK: temperatureK,
            composition: calculatedComposition,
            clientVersion: Bundle.main.releaseVersion
        )

        do {
            let response = try await provider.calculate(request)
            let normalizationWasUsed = lastNormalizedComposition == calculatedComposition
            calculationRecord = CalculationRecord(
                request: request,
                input: CalculationInputSnapshot(
                    pressureValue: pressure,
                    pressureUnit: .bara,
                    pressurePa: pressurePa,
                    temperatureValue: temperature,
                    temperatureUnit: .celsius,
                    temperatureK: temperatureK,
                    originalComposition: normalizationWasUsed
                        ? compositionBeforeNormalization ?? compositionSnapshot()
                        : compositionSnapshot(),
                    normalizedComposition: normalizationWasUsed ? calculatedComposition : nil
                ),
                response: response,
                application: Bundle.main.applicationIdentity
            )
        } catch {
            calculationError = userMessage(for: error)
        }
    }

    private func domainComposition() -> [MixtureComponent] {
        composition.map { entry in
            let enteredValue = entry.component == .carbonDioxide
                ? carbonDioxideEnteredValue
                : parse(entry.value) ?? .nan
            return MixtureComponent(
                component: entry.component,
                moleFraction: enteredValue / (compositionBasis == .partsPerMillion ? 1_000_000 : 100)
            )
        }
    }

    private func compositionSnapshot() -> [CompositionInputSnapshot] {
        composition.map { entry in
            let enteredValue = entry.component == .carbonDioxide
                ? carbonDioxideEnteredValue
                : parse(entry.value) ?? .nan
            return CompositionInputSnapshot(
                component: entry.component,
                value: enteredValue,
                unit: compositionBasis == .partsPerMillion ? .partsPerMillion : .molePercent
            )
        }
    }

    private func userMessage(for error: Error) -> String {
        if error is CancellationError {
            return "The calculation was cancelled."
        }
        guard let providerError = error as? ProviderError else {
            return "The calculation failed unexpectedly. Please review the inputs and try again."
        }
        switch providerError {
        case let .modelUnavailable(message),
             let .invalidRequest(message),
             let .malformedResponse(message):
            return message
        case let .unsupportedComponent(component):
            return "\(component.symbol) is not supported by the selected model."
        case .timeout:
            return "The calculation timed out."
        case .cancelled:
            return "The calculation was cancelled."
        }
    }

    private var compositionScale: Double {
        compositionBasis == .partsPerMillion ? 1_000_000 : 100
    }

    private func parse(_ value: String) -> Double? {
        Double(value.replacingOccurrences(of: ",", with: "."))
    }
}

extension Bundle {
    var applicationIdentity: ApplicationIdentity {
        ApplicationIdentity(
            version: object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown",
            build: object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        )
    }

    var releaseVersion: String {
        "\(applicationIdentity.version) (\(applicationIdentity.build))"
    }
}
