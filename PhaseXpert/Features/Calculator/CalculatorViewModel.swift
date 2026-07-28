import Foundation
import Observation
import PhaseXpertCore

struct CompositionInput: Identifiable, Equatable {
    let id = UUID()
    var component: ComponentID
    var molPercent: String
}

@MainActor
@Observable
final class CalculatorViewModel {
    var pressureText = "150"
    var temperatureText = "20"
    var selectedModelID = "architecture-demo"
    var composition: [CompositionInput] = [
        CompositionInput(component: .carbonDioxide, molPercent: "100")
    ]
    private(set) var validationReport = ValidationReport(issues: [], normalizedComposition: nil)
    private(set) var response: CalculationResponse?
    private(set) var calculationError: String?
    private(set) var isCalculating = false

    let registry = ProviderRegistry()
    private let validator = CalculationValidator()

    var descriptors: [ModelDescriptor] { registry.descriptors }

    var selectedDescriptor: ModelDescriptor? {
        descriptors.first { $0.id == selectedModelID }
    }

    var canNormalize: Bool {
        validationReport.normalizedComposition != nil
    }

    func addImpurity() {
        let selected = Set(composition.map(\.component))
        guard let component = ComponentID.allCases.first(where: {
            $0 != .carbonDioxide && !selected.contains($0)
        }) else { return }
        composition.append(CompositionInput(component: component, molPercent: "0"))
    }

    func removeImpurities(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where composition[index].component != .carbonDioxide {
            composition.remove(at: index)
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

        let supportedComponents = descriptor.availability == .available
            ? descriptor.supportedComponents
            : Set(domainComposition().map(\.component))
        let coreReport = validator.validate(
            pressurePa: PressureUnit.bar.toPascal(pressure),
            temperatureK: TemperatureUnit.celsius.toKelvin(temperature),
            composition: domainComposition(),
            supportedComponents: supportedComponents,
            domain: descriptor.domain
        )
        var issues = coreReport.issues
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
        guard let normalized = validationReport.normalizedComposition else { return }
        composition = normalized.map {
            CompositionInput(
                component: $0.component,
                molPercent: String(format: "%.8g", $0.moleFraction * 100)
            )
        }
        validate()
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
        defer { isCalculating = false }

        let request = CalculationRequest(
            modelID: selectedModelID,
            pressurePa: PressureUnit.bar.toPascal(pressure),
            temperatureK: TemperatureUnit.celsius.toKelvin(temperature),
            composition: domainComposition(),
            clientVersion: Bundle.main.releaseVersion
        )

        do {
            response = try await provider.calculate(request)
        } catch {
            response = nil
            calculationError = String(describing: error)
        }
    }

    private func domainComposition() -> [MixtureComponent] {
        composition.map {
            MixtureComponent(
                component: $0.component,
                moleFraction: (parse($0.molPercent) ?? .nan) / 100
            )
        }
    }

    private func parse(_ value: String) -> Double? {
        Double(value.replacingOccurrences(of: ",", with: "."))
    }
}

extension Bundle {
    var releaseVersion: String {
        let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        return "\(version) (\(build))"
    }
}
