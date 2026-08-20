import Foundation
import Observation
import PhaseXpertCore

struct CompositionInput: Identifiable, Equatable {
    let id: UUID
    var component: ComponentID
    var value: String

    init(id: UUID = UUID(), component: ComponentID, value: String) {
        self.id = id
        self.component = component
        self.value = value
    }
}

enum CompositionInputBasis: String, CaseIterable, Identifiable {
    case partsPerMillion = "ppm"
    case molePercent = "mol%"

    var id: String { rawValue }
}

enum PressureDisplayUnit: String, CaseIterable, Identifiable {
    case barAbsolute = "bar(a)"
    case megapascalAbsolute = "MPa(a)"
    case psiAbsolute = "psi(a)"

    var id: String { rawValue }

    func pascal(from displayValue: Double) -> Double {
        switch self {
        case .barAbsolute:
            PressureUnit.bar.toPascal(displayValue)
        case .megapascalAbsolute:
            displayValue * 1_000_000
        case .psiAbsolute:
            PressureUnit.psia.toPascal(displayValue)
        }
    }

    func displayValue(from pascal: Double) -> Double {
        switch self {
        case .barAbsolute:
            pascal / 100_000
        case .megapascalAbsolute:
            pascal / 1_000_000
        case .psiAbsolute:
            PressureUnit.psia.fromPascal(pascal)
        }
    }
}

enum TemperatureDisplayUnit: String, CaseIterable, Identifiable {
    case celsius = "°C"
    case kelvin = "K"
    case fahrenheit = "°F"

    var id: String { rawValue }

    func kelvin(from displayValue: Double) -> Double {
        switch self {
        case .celsius:
            TemperatureUnit.celsius.toKelvin(displayValue)
        case .kelvin:
            displayValue
        case .fahrenheit:
            TemperatureUnit.fahrenheit.toKelvin(displayValue)
        }
    }

    func displayValue(from kelvin: Double) -> Double {
        switch self {
        case .celsius:
            kelvin - 273.15
        case .kelvin:
            kelvin
        case .fahrenheit:
            TemperatureUnit.fahrenheit.fromKelvin(kelvin)
        }
    }
}

@MainActor
@Observable
final class CalculatorViewModel {
    var pressureText = "50"
    var temperatureText = "20"
    var pressureDisplayUnit: PressureDisplayUnit = .barAbsolute
    var temperatureDisplayUnit: TemperatureDisplayUnit = .celsius
    var selectedModelID = "coolprop-heos"
    var compositionBasis: CompositionInputBasis = .partsPerMillion
    var composition: [CompositionInput] = [
        CompositionInput(component: .carbonDioxide, value: "1000000")
    ]
    private(set) var validationReport = ValidationReport(issues: [], normalizedComposition: nil)
    private(set) var calculationRecord: CalculationRecord?
    private(set) var calculationError: String?
    private(set) var standaloneWaterEquilibriumResult: CarbonDioxideWaterEquilibriumResult?
    private(set) var isCalculating = false

    let registry: ProviderRegistry
    private let validator = CalculationValidator()
    private var compositionBeforeNormalization: [CompositionInputSnapshot]?
    private var lastNormalizedComposition: [MixtureComponent]?
    private var lastValidPressurePa = PressureUnit.bar.toPascal(50)
    private var lastValidTemperatureK = TemperatureUnit.celsius.toKelvin(20)

    init(registry: ProviderRegistry = ProviderRegistry()) {
        self.registry = registry
    }

    var descriptors: [ModelDescriptor] { registry.descriptors }

    var selectedDescriptor: ModelDescriptor? {
        descriptors.first { $0.id == selectedModelID }
    }

    var selectableDescriptors: [ModelDescriptor] {
        descriptors.filter { $0.availability != .unavailable }
    }

    var operatingRangeGuidance: OperatingRangeGuidance? {
        guard
            let provider = registry.provider(id: selectedModelID),
            selectedDescriptor != nil
        else {
            return nil
        }
        return provider.operatingRangeGuidance(
            for: OperatingGuidanceContext(
                pressurePa: parsedPressurePa,
                temperatureK: parsedTemperatureK,
                composition: domainComposition()
            )
        )
    }

    /// Independent binary pure-water equilibrium preview. This intentionally
    /// does not depend on, or broaden, the homogeneous CoolProp property gate.
    var waterEquilibriumPreview: CarbonDioxideWaterEquilibriumResult? {
        guard let pressurePa = parsedPressurePa,
              let temperatureK = parsedTemperatureK else { return nil }
        let active = domainComposition().filter { $0.moleFraction > 0 }
        guard active.count == 2,
              active.contains(where: { $0.component == .carbonDioxide }),
              let water = active.first(where: { $0.component == .water }) else {
            return nil
        }
        return try? SpycherPruess2003WaterEquilibrium().equilibrium(
            pressurePa: pressurePa,
            temperatureK: temperatureK,
            currentWaterMoleFraction: water.moleFraction
        )
    }

    var displayedWaterEquilibrium: CarbonDioxideWaterEquilibriumResult? {
        waterEquilibriumPreview
    }

    var waterEquilibriumUnavailableMessage: String? {
        guard isBinaryCarbonDioxideWaterComposition,
              !homogeneousWetPropertiesAreInPreliminaryDomain,
              waterEquilibriumPreview == nil,
              parsedPressurePa != nil,
              parsedTemperatureK != nil else {
            return nil
        }
        return "Water calculations are unavailable at this condition. Validated water-equilibrium ranges are \(SpycherPruess2003WaterEquilibrium.validatedRangeSummary)"
    }

    var canRunCalculation: Bool {
        if isBinaryCarbonDioxideWaterComposition {
            return homogeneousWetPropertiesAreInPreliminaryDomain
                || waterEquilibriumPreview != nil
        }
        return validationReport.canCalculate
    }

    var homogeneousPropertiesUnavailableWhileEquilibriumAvailable: Bool {
        isBinaryCarbonDioxideWaterComposition
            && !homogeneousWetPropertiesAreInPreliminaryDomain
            && waterEquilibriumPreview != nil
    }

    var homogeneousWetPropertiesAreInPreliminaryDomain: Bool {
        guard isBinaryCarbonDioxideWaterComposition,
              let pressurePa = parsedPressurePa,
              let temperatureK = parsedTemperatureK,
              let water = domainComposition().first(where: { $0.component == .water }) else {
            return false
        }
        return (1e-6...0.001).contains(water.moleFraction)
            && (350...423.15).contains(temperatureK)
            && (500_000...5_000_000).contains(pressurePa)
    }

    var calculationNotice: String? {
        homogeneousPropertiesUnavailableWhileEquilibriumAvailable
            ? Self.independentWaterEquilibriumNotice
            : nil
    }

    var canNormalize: Bool {
        false
    }

    var supportedImpurityComponents: [ComponentID] {
        let supported = selectedDescriptor?.supportedComponents ?? []
        return ComponentID.allCases.filter {
            $0 != .carbonDioxide && supported.contains($0)
        }
        .sortedByVisibleImpurityName()
    }

    func impurityOptions(including current: ComponentID) -> [ComponentID] {
        let options = supportedImpurityComponents.contains(current)
            ? supportedImpurityComponents
            : [current] + supportedImpurityComponents
        return options.sortedByVisibleImpurityName()
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
        standaloneWaterEquilibriumResult = nil
        guard
            let pressurePa = parsedPressurePa,
            let temperatureK = parsedTemperatureK,
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
        lastValidPressurePa = pressurePa
        lastValidTemperatureK = temperatureK

        let requestedComposition = domainComposition()
        let supportedComponents = descriptor.availability == .unavailable
            ? Set(requestedComposition.map(\.component))
            : descriptor.supportedComponents
        let coreReport = validator.validate(
            pressurePa: pressurePa,
            temperatureK: temperatureK,
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
                    message: "This model is not available in this version."
                ),
                at: 0
            )
        }
        validationReport = ValidationReport(
            issues: issues,
            normalizedComposition: coreReport.normalizedComposition
        )
    }

    func reset() {
        pressureDisplayUnit = .barAbsolute
        temperatureDisplayUnit = .celsius
        pressureText = "50"
        temperatureText = "20"
        lastValidPressurePa = PressureUnit.bar.toPascal(50)
        lastValidTemperatureK = TemperatureUnit.celsius.toKelvin(20)
        selectedModelID = "coolprop-heos"
        compositionBasis = .partsPerMillion
        composition = [CompositionInput(component: .carbonDioxide, value: "1000000")]
        compositionBeforeNormalization = nil
        lastNormalizedComposition = nil
        calculationRecord = nil
        calculationError = nil
        standaloneWaterEquilibriumResult = nil
        validate()
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
        pressureDisplayUnit = .barAbsolute
        temperatureDisplayUnit = .celsius
        lastValidPressurePa = record.input.pressurePa
        lastValidTemperatureK = record.input.temperatureK
        pressureText = Self.format(
            pressureDisplayUnit.displayValue(from: record.input.pressurePa),
            for: pressureDisplayUnit
        )
        temperatureText = Self.format(
            temperatureDisplayUnit.displayValue(from: record.input.temperatureK),
            for: temperatureDisplayUnit
        )
        if descriptors.contains(where: { $0.id == record.request.modelID }) {
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
        standaloneWaterEquilibriumResult = nil
        validate()
    }

    func loadInputs(from builtInCase: BuiltInCase) {
        guard
            let defaultPressurePa = builtInCase.defaultPressurePa,
            let defaultTemperatureK = builtInCase.defaultTemperatureK,
            let compositionPreset = builtInCase.composition
        else {
            return
        }
        lastValidPressurePa = defaultPressurePa
        lastValidTemperatureK = defaultTemperatureK
        pressureText = Self.format(
            pressureDisplayUnit.displayValue(from: defaultPressurePa),
            for: pressureDisplayUnit
        )
        temperatureText = Self.format(
            temperatureDisplayUnit.displayValue(from: defaultTemperatureK),
            for: temperatureDisplayUnit
        )
        compositionBasis = .molePercent
        composition = compositionPreset.map {
            CompositionInput(
                component: $0.component,
                value: String(format: "%.8g", $0.moleFraction * 100)
            )
        }
        compositionBeforeNormalization = nil
        lastNormalizedComposition = nil
        calculationRecord = nil
        calculationError = nil
        standaloneWaterEquilibriumResult = nil
        validate()
    }

    func changePressureDisplayUnit(to newUnit: PressureDisplayUnit) {
        guard newUnit != pressureDisplayUnit else { return }
        if let pressurePa = parsedPressurePa {
            lastValidPressurePa = pressurePa
        }
        pressureDisplayUnit = newUnit
        pressureText = Self.format(
            newUnit.displayValue(from: lastValidPressurePa),
            for: newUnit
        )
        validate()
    }

    func changeTemperatureDisplayUnit(to newUnit: TemperatureDisplayUnit) {
        guard newUnit != temperatureDisplayUnit else { return }
        if let temperatureK = parsedTemperatureK {
            lastValidTemperatureK = temperatureK
        }
        temperatureDisplayUnit = newUnit
        temperatureText = Self.format(
            newUnit.displayValue(from: lastValidTemperatureK),
            for: newUnit
        )
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
                id: entry.id,
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

    func applyGuidanceSuggestion(_ suggestion: OperatingGuidanceSuggestion) {
        switch suggestion.action {
        case let .setComposition(component, moleFraction):
            setComposition(component: component, moleFraction: moleFraction)
        case let .setTemperature(kelvin):
            lastValidTemperatureK = kelvin
            temperatureText = Self.format(
                temperatureDisplayUnit.displayValue(from: kelvin),
                for: temperatureDisplayUnit
            )
        }
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
        let equilibrium = waterEquilibriumPreview
        if isBinaryCarbonDioxideWaterComposition,
           !homogeneousWetPropertiesAreInPreliminaryDomain {
            calculationRecord = nil
            calculationError = nil
            standaloneWaterEquilibriumResult = equilibrium
            return
        }
        guard validationReport.canCalculate else {
            calculationRecord = nil
            calculationError = nil
            standaloneWaterEquilibriumResult = equilibrium
            return
        }
        guard
            let provider = registry.provider(id: selectedModelID),
            let pressureValue = parse(pressureText),
            let temperatureValue = parse(temperatureText),
            let pressurePa = parsedPressurePa,
            let temperatureK = parsedTemperatureK
        else { return }

        isCalculating = true
        calculationError = nil
        calculationRecord = nil
        standaloneWaterEquilibriumResult = nil
        defer { isCalculating = false }

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
                    pressureValue: pressureValue,
                    pressureUnit: pressureInputSnapshotUnit,
                    pressurePa: pressurePa,
                    temperatureValue: temperatureValue,
                    temperatureUnit: temperatureInputSnapshotUnit,
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

    static let independentWaterEquilibriumNotice =
        "Homogeneous wet-gas properties are outside their preliminary supported range. Water-equilibrium results remain available within their separate validated range."

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

    private var isBinaryCarbonDioxideWaterComposition: Bool {
        let active = domainComposition().filter {
            $0.moleFraction.isFinite && $0.moleFraction > 0
        }
        return active.count == 2
            && active.contains(where: { $0.component == .carbonDioxide })
            && active.contains(where: { $0.component == .water })
    }

    private func setComposition(component: ComponentID, moleFraction: Double) {
        guard component != .carbonDioxide else { return }
        let displayedValue = moleFraction * (compositionBasis == .partsPerMillion ? 1_000_000 : 100)
        let value = String(
            format: compositionBasis == .partsPerMillion ? "%.12g" : "%.8g",
            displayedValue
        )
        if let index = composition.firstIndex(where: { $0.component == component }) {
            composition[index].value = value
        } else if let index = composition.firstIndex(where: { $0.component != .carbonDioxide }) {
            composition[index].component = component
            composition[index].value = value
        } else {
            composition.append(CompositionInput(component: component, value: value))
        }
        compositionBeforeNormalization = nil
        lastNormalizedComposition = nil
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

    private var parsedPressurePa: Double? {
        guard let value = parse(pressureText) else { return nil }
        let pressurePa = pressureDisplayUnit.pascal(from: value)
        return pressurePa.isFinite ? pressurePa : nil
    }

    private var parsedTemperatureK: Double? {
        guard let value = parse(temperatureText) else { return nil }
        let temperatureK = temperatureDisplayUnit.kelvin(from: value)
        return temperatureK.isFinite ? temperatureK : nil
    }

    private var pressureInputSnapshotUnit: PressureUnit {
        switch pressureDisplayUnit {
        case .barAbsolute:
            .bara
        case .megapascalAbsolute:
            .megapascal
        case .psiAbsolute:
            .psia
        }
    }

    private var temperatureInputSnapshotUnit: TemperatureUnit {
        switch temperatureDisplayUnit {
        case .celsius:
            .celsius
        case .kelvin:
            .kelvin
        case .fahrenheit:
            .fahrenheit
        }
    }

    private func parse(_ value: String) -> Double? {
        Double(value.replacingOccurrences(of: ",", with: "."))
    }

    private static func format(
        _ value: Double,
        for unit: PressureDisplayUnit
    ) -> String {
        switch unit {
        case .barAbsolute:
            String(format: "%.8g", value)
        case .megapascalAbsolute, .psiAbsolute:
            String(format: "%.10g", value)
        }
    }

    private static func format(
        _ value: Double,
        for unit: TemperatureDisplayUnit
    ) -> String {
        switch unit {
        case .celsius:
            String(format: "%.8g", value)
        case .kelvin, .fahrenheit:
            String(format: "%.10g", value)
        }
    }
}

@MainActor
@Observable
final class StreamMixingViewModel {
    var streams: [StreamInputState] = [
        StreamInputState(
            name: "Stream 1",
            flowText: "10",
            composition: [
                CompositionInput(component: .carbonDioxide, value: "95"),
                CompositionInput(component: .nitrogen, value: "5")
            ]
        ),
        StreamInputState(
            name: "Stream 2",
            flowText: "5",
            pressureText: "125",
            composition: [
                CompositionInput(component: .carbonDioxide, value: "100")
            ]
        )
    ]
    var outletPressureText = "120"
    var outletPressureDisplayUnit: PressureDisplayUnit = .barAbsolute
    var outletTemperatureText = "25"
    var outletTemperatureDisplayUnit: TemperatureDisplayUnit = .celsius
    var result: MixedCompositionResult?
    var validationReport = StreamMixingValidationReport(issues: [])
    var statusMessage = "Ready for 2 to 6 inlet streams."
    var isResultStale = false
    var displayCompositionBasis: CompositionUnit = .molePercent

    private let engine: StreamMixingEngine
    private let compositionConverter = StreamCompositionConverter()
    private let flowConverter = StreamFlowConverter()
    private var conversionIssue: StreamMixingValidationIssue?

    init(engine: StreamMixingEngine = StreamMixingEngine()) {
        self.engine = engine
        validate()
    }

    var canAddStream: Bool {
        streams.count < StreamMixingRequest.maximumStreamCount
    }

    var canRemoveStream: Bool {
        streams.count > StreamMixingRequest.minimumStreamCount
    }

    var canCalculate: Bool {
        validationReport.canCalculate
    }

    func markInputsChanged() {
        if result != nil {
            isResultStale = true
            statusMessage = "Inputs changed. Calculate mixture again to refresh results."
        }
        validate()
    }

    func updateStreamName(streamID: UUID, value: String) {
        guard let index = streams.firstIndex(where: { $0.id == streamID }) else { return }
        streams[index].name = value
        markInputsChanged()
    }

    func updateFlowText(streamID: UUID, value: String) {
        guard let index = streams.firstIndex(where: { $0.id == streamID }) else { return }
        streams[index].flowText = value
        conversionIssue = nil
        markInputsChanged()
    }

    func updatePressureText(streamID: UUID, value: String) {
        guard let index = streams.firstIndex(where: { $0.id == streamID }) else { return }
        streams[index].pressureText = value
        conversionIssue = nil
        markInputsChanged()
    }

    func updateTemperatureText(streamID: UUID, value: String) {
        guard let index = streams.firstIndex(where: { $0.id == streamID }) else { return }
        streams[index].temperatureText = value
        conversionIssue = nil
        markInputsChanged()
    }

    func updateOutletPressureText(_ value: String) {
        outletPressureText = value
        conversionIssue = nil
        markInputsChanged()
    }

    func updateOutletTemperatureText(_ value: String) {
        outletTemperatureText = value
        conversionIssue = nil
        markInputsChanged()
    }

    @discardableResult
    func addStream() -> UUID? {
        guard canAddStream else { return nil }
        let stream = StreamInputState(name: "Stream \(streams.count + 1)")
        streams.append(stream)
        markInputsChanged()
        return stream.id
    }

    @discardableResult
    func duplicateStream(id: UUID) -> UUID? {
        guard canAddStream,
              let index = streams.firstIndex(where: { $0.id == id })
        else { return nil }
        let copy = streams[index].duplicated(name: distinctDuplicateName(for: streams[index].name))
        streams.insert(copy, at: index + 1)
        markInputsChanged()
        return copy.id
    }

    func removeStream(id: UUID) {
        guard canRemoveStream,
              let index = streams.firstIndex(where: { $0.id == id })
        else { return }
        streams.remove(at: index)
        markInputsChanged()
    }

    func moveStreams(from source: IndexSet, to destination: Int) {
        streams.move(fromOffsets: source, toOffset: destination)
        markInputsChanged()
    }

    func canMoveStreamUp(id: UUID) -> Bool {
        guard let index = streams.firstIndex(where: { $0.id == id }) else { return false }
        return index > 0
    }

    func canMoveStreamDown(id: UUID) -> Bool {
        guard let index = streams.firstIndex(where: { $0.id == id }) else { return false }
        return index < streams.count - 1
    }

    func moveStreamUp(id: UUID) {
        guard let index = streams.firstIndex(where: { $0.id == id }), index > 0 else { return }
        streams.swapAt(index, index - 1)
        markInputsChanged()
    }

    func moveStreamDown(id: UUID) {
        guard let index = streams.firstIndex(where: { $0.id == id }), index < streams.count - 1 else { return }
        streams.swapAt(index, index + 1)
        markInputsChanged()
    }

    func addImpurity(to streamID: UUID) -> UUID? {
        guard let index = streams.firstIndex(where: { $0.id == streamID }) else { return nil }
        let selected = Set(streams[index].composition.map(\.component))
        guard let component = ComponentID.allCases.first(where: {
            $0 != .carbonDioxide && !selected.contains($0)
        }) else { return nil }
        let input = CompositionInput(component: component, value: "")
        streams[index].composition.append(input)
        clearAcceptedNormalization(for: index)
        markInputsChanged()
        return input.id
    }

    func updateCompositionValue(streamID: UUID, entryID: UUID, value: String) {
        guard let streamIndex = streams.firstIndex(where: { $0.id == streamID }),
              let entryIndex = streams[streamIndex].composition.firstIndex(where: { $0.id == entryID })
        else { return }
        streams[streamIndex].composition[entryIndex].value = value
        clearAcceptedNormalization(for: streamIndex)
        markInputsChanged()
    }

    func replaceComposition(
        streamID: UUID,
        basis: CompositionUnit,
        composition: [CompositionInput]
    ) {
        guard let index = streams.firstIndex(where: { $0.id == streamID }) else { return }
        streams[index].compositionBasis = basis
        streams[index].composition = composition
        clearAcceptedNormalization(for: index)
        markInputsChanged()
    }

    func updateImpurity(streamID: UUID, entryID: UUID, component: ComponentID) {
        guard component != .carbonDioxide,
              let streamIndex = streams.firstIndex(where: { $0.id == streamID }),
              let entryIndex = streams[streamIndex].composition.firstIndex(where: { $0.id == entryID }),
              streams[streamIndex].composition[entryIndex].component != .carbonDioxide,
              !streams[streamIndex].composition.contains(where: {
                  $0.id != entryID && $0.component == component
              })
        else { return }
        streams[streamIndex].composition[entryIndex].component = component
        clearAcceptedNormalization(for: streamIndex)
        markInputsChanged()
    }

    func removeImpurity(streamID: UUID, entryID: UUID) {
        guard let streamIndex = streams.firstIndex(where: { $0.id == streamID }),
              let entryIndex = streams[streamIndex].composition.firstIndex(where: { $0.id == entryID }),
              streams[streamIndex].composition[entryIndex].component != .carbonDioxide
        else { return }
        streams[streamIndex].composition.remove(at: entryIndex)
        clearAcceptedNormalization(for: streamIndex)
        markInputsChanged()
    }

    func moveImpurities(streamID: UUID, from source: IndexSet, to destination: Int) {
        guard let streamIndex = streams.firstIndex(where: { $0.id == streamID }) else { return }
        streams[streamIndex].composition.move(fromOffsets: source, toOffset: destination)
        if let co2Index = streams[streamIndex].composition.firstIndex(where: {
            $0.component == .carbonDioxide
        }), co2Index != 0 {
            let co2 = streams[streamIndex].composition.remove(at: co2Index)
            streams[streamIndex].composition.insert(co2, at: 0)
        }
        clearAcceptedNormalization(for: streamIndex)
        markInputsChanged()
    }

    func changeCompositionBasis(streamID: UUID, to newBasis: CompositionUnit) {
        guard let index = streams.firstIndex(where: { $0.id == streamID }),
              streams[index].compositionBasis != newBasis
        else { return }
        let stream = streams[index]
        let oldSnapshots = originalComposition(for: stream)
        let moleFractions: [MixtureComponent]
        if let normalizedComposition = stream.normalizedComposition {
            moleFractions = normalizedComposition
        } else {
            do {
                let candidate = try compositionConverter.conversionCandidate(from: oldSnapshots)
                guard candidate.requirement == .validAsEntered else {
                    conversionIssue = issueForConversionFailure(
                        stream: stream,
                        field: .composition,
                        code: .normalizationRequired,
                        message: "Composition basis could not be changed until the available normalization is explicitly accepted."
                    )
                    validate()
                    return
                }
                moleFractions = candidate.convertedComposition
            } catch {
                conversionIssue = issueForConversionFailure(
                    stream: stream,
                    field: .composition,
                    message: "Composition basis could not be changed because the current composition is incomplete, invalid or lacks a reviewed molar mass."
                )
                validate()
                return
            }
        }
        guard let newSnapshots = try? compositionConverter.compositionSnapshots(
            from: moleFractions,
            basis: newBasis
        ) else {
            conversionIssue = issueForConversionFailure(
                stream: stream,
                field: .composition,
                message: "Composition basis could not be changed because the current composition is incomplete, invalid or lacks a reviewed molar mass."
            )
            validate()
            return
        }
        streams[index].compositionBasis = newBasis
        streams[index].composition = newSnapshots.map { snapshot in
            let existingID = streams[index].composition.first {
                $0.component == snapshot.component
            }?.id ?? UUID()
            return CompositionInput(
                id: existingID,
                component: snapshot.component,
                value: Self.formatCompositionValue(snapshot.value, basis: newBasis)
            )
        }
        clearAcceptedNormalization(for: index)
        conversionIssue = nil
        markInputsChanged()
    }

    func applyExplicitNormalization(for streamID: UUID) {
        guard let index = streams.firstIndex(where: { $0.id == streamID }) else { return }
        let snapshots = originalComposition(for: streams[index])
        guard let normalized = try? compositionConverter.normalizedMoleFractions(from: snapshots) else { return }
        streams[index].compositionBeforeNormalization = snapshots
        streams[index].normalizedComposition = normalized
        streams[index].composition = displayComposition(from: normalized, basis: streams[index].compositionBasis)
        markInputsChanged()
    }

    func calculate() {
        guard let request = request() else {
            validate()
            statusMessage = "Review blocking validation issues before calculating."
            return
        }
        let report = engine.validate(request)
        validationReport = report
        guard report.canCalculate else {
            result = nil
            isResultStale = false
            statusMessage = "Review blocking validation issues before calculating."
            return
        }
        let mixedResult = engine.mix(request)
        result = mixedResult
        isResultStale = false
        statusMessage = mixedResult.status == .calculated
            ? "Mixture calculated. Composition and flow aggregation only."
            : "Review blocking validation issues before calculating."
        validationReport = StreamMixingValidationReport(issues: mixedResult.validationIssues)
    }

    func validate() {
        guard let request = request() else {
            validationReport = StreamMixingValidationReport(issues: localValidationIssues())
            return
        }
        var issues = engine.validate(request).issues
        if let conversionIssue {
            issues.insert(conversionIssue, at: 0)
        }
        validationReport = StreamMixingValidationReport(issues: issues)
    }

    func issues(for streamID: UUID) -> [StreamMixingValidationIssue] {
        validationReport.issues.filter { $0.streamID == streamID }
    }

    func outletIssues() -> [StreamMixingValidationIssue] {
        validationReport.issues.filter {
            $0.field == .outletPressure || $0.field == .outletTemperature
        }
    }

    func canNormalize(streamID: UUID) -> Bool {
        validationReport.issues.contains {
            $0.streamID == streamID && $0.code == .normalizationRequired
        }
    }

    func carbonDioxideDisplayValue(for stream: StreamInputState) -> String {
        stream.composition.first { $0.component == .carbonDioxide }?.value ?? ""
    }

    func impurityOptions(streamID: UUID, including current: ComponentID) -> [ComponentID] {
        let selected = streams.first(where: { $0.id == streamID })?.composition.map(\.component) ?? []
        return ComponentID.allCases.filter {
            $0 != .carbonDioxide && ($0 == current || !selected.contains($0))
        }
        .sortedByVisibleImpurityName()
    }

    func formattedCompositionValue(_ moleFraction: Double, basis: CompositionUnit) -> String {
        guard let snapshot = try? compositionConverter.compositionSnapshots(
            from: [MixtureComponent(component: .carbonDioxide, moleFraction: moleFraction)],
            basis: basis
        ).first else { return Self.formatCompositionValue(moleFraction, basis: basis) }
        return Self.formatCompositionValue(snapshot.value, basis: basis)
    }

    func changeStreamPressureUnit(streamID: UUID, to newUnit: PressureDisplayUnit) {
        guard let index = streams.firstIndex(where: { $0.id == streamID }),
              streams[index].pressureDisplayUnit != newUnit
        else { return }
        guard let value = parse(streams[index].pressureText) else {
            conversionIssue = issueForConversionFailure(
                stream: streams[index],
                field: .pressure,
                code: .invalidPressure,
                message: "Pressure unit could not be changed because the current pressure value is not numeric."
            )
            validate()
            return
        }
        let pressurePa = streams[index].pressureDisplayUnit.pascal(from: value)
        streams[index].pressureDisplayUnit = newUnit
        streams[index].pressureText = Self.formatPressure(newUnit.displayValue(from: pressurePa), for: newUnit)
        conversionIssue = nil
        markInputsChanged()
    }

    func changeStreamTemperatureUnit(streamID: UUID, to newUnit: TemperatureDisplayUnit) {
        guard let index = streams.firstIndex(where: { $0.id == streamID }),
              streams[index].temperatureDisplayUnit != newUnit
        else { return }
        guard let value = parse(streams[index].temperatureText) else {
            conversionIssue = issueForConversionFailure(
                stream: streams[index],
                field: .temperature,
                code: .invalidTemperature,
                message: "Temperature unit could not be changed because the current temperature value is not numeric."
            )
            validate()
            return
        }
        let temperatureK = streams[index].temperatureDisplayUnit.kelvin(from: value)
        streams[index].temperatureDisplayUnit = newUnit
        streams[index].temperatureText = Self.formatTemperature(
            newUnit.displayValue(from: temperatureK),
            for: newUnit
        )
        conversionIssue = nil
        markInputsChanged()
    }

    func changeOutletPressureUnit(to newUnit: PressureDisplayUnit) {
        guard outletPressureDisplayUnit != newUnit else { return }
        guard let value = parse(outletPressureText) else {
            conversionIssue = StreamMixingValidationIssue(
                code: .invalidPressure,
                field: .outletPressure,
                message: "Outlet pressure unit could not be changed because the current pressure value is not numeric."
            )
            validate()
            return
        }
        let pressurePa = outletPressureDisplayUnit.pascal(from: value)
        outletPressureDisplayUnit = newUnit
        outletPressureText = Self.formatPressure(newUnit.displayValue(from: pressurePa), for: newUnit)
        conversionIssue = nil
        markInputsChanged()
    }

    func changeOutletTemperatureUnit(to newUnit: TemperatureDisplayUnit) {
        guard outletTemperatureDisplayUnit != newUnit else { return }
        guard let value = parse(outletTemperatureText) else {
            conversionIssue = StreamMixingValidationIssue(
                code: .invalidTemperature,
                field: .outletTemperature,
                message: "Outlet temperature unit could not be changed because the current temperature value is not numeric."
            )
            validate()
            return
        }
        let temperatureK = outletTemperatureDisplayUnit.kelvin(from: value)
        outletTemperatureDisplayUnit = newUnit
        outletTemperatureText = Self.formatTemperature(
            newUnit.displayValue(from: temperatureK),
            for: newUnit
        )
        conversionIssue = nil
        markInputsChanged()
    }

    func changeStreamFlowUnit(streamID: UUID, to newUnit: StreamFlowUnit) {
        guard let index = streams.firstIndex(where: { $0.id == streamID }),
              streams[index].flowUnit != newUnit
        else { return }
        let stream = streams[index]
        guard let value = parse(stream.flowText) else {
            conversionIssue = issueForConversionFailure(
                stream: stream,
                field: .flow,
                code: .invalidFlow,
                message: "Flow unit could not be changed because the current flow value is not numeric."
            )
            validate()
            return
        }
        let composition = canonicalComposition(for: stream)
        do {
            let converted = try flowConverter.convertedFlowValue(
                value,
                from: stream.flowUnit,
                to: newUnit,
                composition: composition
            )
            streams[index].flowUnit = newUnit
            streams[index].flowText = Self.formatFlow(converted, for: newUnit)
            conversionIssue = nil
            markInputsChanged()
        } catch {
            conversionIssue = issueForConversionFailure(
                stream: stream,
                field: .flow,
                code: .invalidFlow,
                message: "Flow unit could not be changed because the current composition cannot support a mass-molar flow conversion."
            )
            validate()
        }
    }

    func loadBuiltInCase(_ builtInCase: BuiltInCase, into streamID: UUID) {
        guard
            let index = streams.firstIndex(where: { $0.id == streamID }),
            let defaultPressurePa = builtInCase.defaultPressurePa,
            let defaultTemperatureK = builtInCase.defaultTemperatureK,
            let compositionPreset = builtInCase.composition
        else {
            return
        }
        let pressureUnit = streams[index].pressureDisplayUnit
        let temperatureUnit = streams[index].temperatureDisplayUnit
        streams[index].name = builtInCase.name
        streams[index].pressureText = Self.formatPressure(
            pressureUnit.displayValue(from: defaultPressurePa),
            for: pressureUnit
        )
        streams[index].temperatureText = Self.formatTemperature(
            temperatureUnit.displayValue(from: defaultTemperatureK),
            for: temperatureUnit
        )
        streams[index].compositionBasis = .molePercent
        streams[index].composition = compositionPreset.map {
            CompositionInput(
                component: $0.component,
                value: Self.formatCompositionValue($0.moleFraction * 100, basis: .molePercent)
            )
        }
        clearAcceptedNormalization(for: index)
        conversionIssue = nil
        markInputsChanged()
    }

    func request() -> StreamMixingRequest? {
        guard let outletPressureValue = parse(outletPressureText),
              let outletTemperatureValue = parse(outletTemperatureText)
        else { return nil }
        let inletStreams = streams.map { stream in
            InletStreamInput(
                id: stream.id,
                name: stream.name,
                flowValue: parse(stream.flowText) ?? .nan,
                flowUnit: stream.flowUnit,
                pressureValue: parse(stream.pressureText) ?? .nan,
                pressureUnit: stream.pressureDisplayUnit.streamMixingPressureUnit,
                temperatureValue: parse(stream.temperatureText) ?? .nan,
                temperatureUnit: stream.temperatureDisplayUnit.streamMixingTemperatureUnit,
                originalComposition: stream.compositionBeforeNormalization
                    ?? originalComposition(for: stream),
                composition: canonicalComposition(for: stream),
                normalizedComposition: stream.normalizedComposition
            )
        }
        return StreamMixingRequest(
            streams: inletStreams,
            outlet: StreamMixingOutletConditionInput(
                pressureValue: outletPressureValue,
                pressureUnit: outletPressureDisplayUnit.streamMixingPressureUnit,
                temperatureValue: outletTemperatureValue,
                temperatureUnit: outletTemperatureDisplayUnit.streamMixingTemperatureUnit
            ),
            clientVersion: Bundle.main.releaseVersion
        )
    }

    private func localValidationIssues() -> [StreamMixingValidationIssue] {
        var issues: [StreamMixingValidationIssue] = []
        if let conversionIssue {
            issues.append(conversionIssue)
        }
        if parse(outletPressureText) == nil {
            issues.append(StreamMixingValidationIssue(
                code: .invalidPressure,
                field: .outletPressure,
                message: "Outlet pressure must be numeric."
            ))
        }
        if parse(outletTemperatureText) == nil {
            issues.append(StreamMixingValidationIssue(
                code: .invalidTemperature,
                field: .outletTemperature,
                message: "Outlet temperature must be numeric."
            ))
        }
        return issues
    }

    private func originalComposition(for stream: StreamInputState) -> [CompositionInputSnapshot] {
        stream.composition.map { entry in
            CompositionInputSnapshot(
                component: entry.component,
                value: parse(entry.value) ?? .nan,
                unit: stream.compositionBasis
            )
        }
    }

    private func canonicalComposition(for stream: StreamInputState) -> [MixtureComponent] {
        if let normalized = stream.normalizedComposition {
            return normalized
        }
        return (try? compositionConverter.conversionCandidate(
            from: originalComposition(for: stream)
        ).convertedComposition) ?? []
    }

    private func displayComposition(
        from composition: [MixtureComponent],
        basis: CompositionUnit
    ) -> [CompositionInput] {
        let snapshots = (try? compositionConverter.compositionSnapshots(
            from: composition,
            basis: basis
        )) ?? []
        return snapshots.map {
            CompositionInput(
                component: $0.component,
                value: Self.formatCompositionValue($0.value, basis: basis)
            )
        }
    }

    private func clearAcceptedNormalization(for index: Int) {
        streams[index].compositionBeforeNormalization = nil
        streams[index].normalizedComposition = nil
    }

    private func issueForConversionFailure(
        stream: StreamInputState,
        field: StreamMixingField,
        code: StreamMixingValidationCode = .invalidComposition,
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

    private func distinctDuplicateName(for name: String) -> String {
        let base = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Stream"
            : name
        var candidate = "\(base) copy"
        var suffix = 2
        let names = Set(streams.map(\.name))
        while names.contains(candidate) {
            candidate = "\(base) copy \(suffix)"
            suffix += 1
        }
        return candidate
    }

    private func parse(_ value: String) -> Double? {
        Double(value.replacingOccurrences(of: ",", with: "."))
    }

    private static func compositionScale(for basis: CompositionUnit) -> Double {
        switch basis {
        case .moleFraction, .massFraction:
            1
        case .molePercent:
            100
        case .partsPerMillion:
            1_000_000
        }
    }

    private static func formatCompositionValue(
        _ value: Double,
        basis: CompositionUnit
    ) -> String {
        switch basis {
        case .moleFraction, .massFraction:
            String(format: "%.12g", value)
        case .molePercent:
            String(format: "%.8g", value)
        case .partsPerMillion:
            String(format: "%.12g", value)
        }
    }

    private static func formatPressure(_ value: Double, for unit: PressureDisplayUnit) -> String {
        switch unit {
        case .barAbsolute:
            String(format: "%.8g", value)
        case .megapascalAbsolute, .psiAbsolute:
            String(format: "%.10g", value)
        }
    }

    private static func formatTemperature(_ value: Double, for unit: TemperatureDisplayUnit) -> String {
        switch unit {
        case .celsius:
            String(format: "%.8g", value)
        case .kelvin, .fahrenheit:
            String(format: "%.10g", value)
        }
    }

    private static func formatFlow(_ value: Double, for unit: StreamFlowUnit) -> String {
        switch unit {
        case .kilogramsPerSecond, .molesPerSecond:
            String(format: "%.12g", value)
        case .kilogramsPerHour, .kilomolesPerHour:
            String(format: "%.10g", value)
        case .tonnesPerHour:
            String(format: "%.12g", value)
        }
    }
}

extension Array where Element == ComponentID {
    func sortedByVisibleImpurityName() -> [ComponentID] {
        sorted {
            $0.symbol.localizedStandardCompare($1.symbol) == .orderedAscending
        }
    }
}

struct StreamInputState: Identifiable, Equatable {
    let id: UUID
    var name: String
    var flowText: String
    var flowUnit: StreamFlowUnit
    var pressureText: String
    var pressureDisplayUnit: PressureDisplayUnit
    var temperatureText: String
    var temperatureDisplayUnit: TemperatureDisplayUnit
    var compositionBasis: CompositionUnit
    var composition: [CompositionInput]
    var compositionBeforeNormalization: [CompositionInputSnapshot]?
    var normalizedComposition: [MixtureComponent]?

    init(
        id: UUID = UUID(),
        name: String,
        flowText: String = "1",
        flowUnit: StreamFlowUnit = .molesPerSecond,
        pressureText: String = "120",
        pressureDisplayUnit: PressureDisplayUnit = .barAbsolute,
        temperatureText: String = "25",
        temperatureDisplayUnit: TemperatureDisplayUnit = .celsius,
        compositionBasis: CompositionUnit = .molePercent,
        composition: [CompositionInput] = [
            CompositionInput(component: .carbonDioxide, value: "100")
        ],
        compositionBeforeNormalization: [CompositionInputSnapshot]? = nil,
        normalizedComposition: [MixtureComponent]? = nil
    ) {
        self.id = id
        self.name = name
        self.flowText = flowText
        self.flowUnit = flowUnit
        self.pressureText = pressureText
        self.pressureDisplayUnit = pressureDisplayUnit
        self.temperatureText = temperatureText
        self.temperatureDisplayUnit = temperatureDisplayUnit
        self.compositionBasis = compositionBasis
        self.composition = composition
        self.compositionBeforeNormalization = compositionBeforeNormalization
        self.normalizedComposition = normalizedComposition
    }

    func duplicated(name: String) -> StreamInputState {
        StreamInputState(
            name: name,
            flowText: flowText,
            flowUnit: flowUnit,
            pressureText: pressureText,
            pressureDisplayUnit: pressureDisplayUnit,
            temperatureText: temperatureText,
            temperatureDisplayUnit: temperatureDisplayUnit,
            compositionBasis: compositionBasis,
            composition: composition.map {
                CompositionInput(component: $0.component, value: $0.value)
            },
            compositionBeforeNormalization: compositionBeforeNormalization,
            normalizedComposition: normalizedComposition
        )
    }
}

extension PressureDisplayUnit {
    var streamMixingPressureUnit: PressureUnit {
        switch self {
        case .barAbsolute:
            .bara
        case .megapascalAbsolute:
            .megapascal
        case .psiAbsolute:
            .psia
        }
    }
}

extension TemperatureDisplayUnit {
    var streamMixingTemperatureUnit: TemperatureUnit {
        switch self {
        case .celsius:
            .celsius
        case .kelvin:
            .kelvin
        case .fahrenheit:
            .fahrenheit
        }
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
