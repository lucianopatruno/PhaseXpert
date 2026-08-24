import Foundation
import Observation
import PDFKit
import PhaseXpertCore
import SwiftUI
import UIKit

enum BatchCalculationModel: String, CaseIterable, Identifiable, Sendable {
    case general = "coolprop-heos"
    case advanced = "teqp-pure-co2-experimental"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .general: "General Properties"
        case .advanced: "Advanced CCS Properties"
        }
    }
}

enum BatchCaseOrigin: String, Codable, Sendable {
    case builtIn = "Built-in"
    case saved = "Saved"
}

struct BatchCaseInput: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let origin: BatchCaseOrigin
    let pressurePa: Double?
    let temperatureK: Double?
    let composition: [MixtureComponent]
    let originalInput: CalculationInputSnapshot?
    let sourceCalculationID: UUID?

    var isComplete: Bool {
        pressurePa?.isFinite == true && pressurePa! > 0
            && temperatureK?.isFinite == true && temperatureK! > 0
            && !composition.isEmpty
    }

    var fingerprint: String {
        let components = composition.map {
            "\($0.component.rawValue)=\(String(format: "%.17g", $0.moleFraction))"
        }.joined(separator: ";")
        return [id, String(format: "%.17g", pressurePa ?? .nan),
                String(format: "%.17g", temperatureK ?? .nan), components]
            .joined(separator: "|")
    }

    static func builtIn(_ value: BuiltInCase) -> BatchCaseInput {
        BatchCaseInput(
            id: "builtin:\(value.id)", name: value.name, origin: .builtIn,
            pressurePa: value.defaultPressurePa, temperatureK: value.defaultTemperatureK,
            composition: value.composition ?? [], originalInput: nil, sourceCalculationID: nil
        )
    }

    static func saved(id: UUID, name: String, record: CalculationRecord?) -> BatchCaseInput {
        BatchCaseInput(
            id: "saved:\(id.uuidString)", name: name, origin: .saved,
            pressurePa: record?.input.pressurePa, temperatureK: record?.input.temperatureK,
            composition: record?.request.composition ?? [], originalInput: record?.input,
            sourceCalculationID: record?.response.calculationID
        )
    }
}

enum BatchResultState: String, Codable, Sendable {
    case calculated = "Calculated"
    case outsideValidatedRange = "Outside validated range"
    case unsupported = "Unsupported"
    case failed = "Calculation failed"
    case cancelled = "Cancelled"
}

struct BatchCaseResult: Identifiable, Equatable, Sendable {
    let id: String
    let input: BatchCaseInput
    let model: BatchCalculationModel
    let state: BatchResultState
    let record: CalculationRecord?
    let modelDescriptor: ModelDescriptor?
    let applicationIdentity: ApplicationIdentity
    let validatedProperties: Set<PropertyID>
    let message: String?
    let completedAt: Date
    let durationMilliseconds: Double

    var calculatedProperties: [PropertyValue] { record?.response.properties ?? [] }
    var phase: PhaseRegion { record?.response.phase ?? .unavailable }
    var isSuccessful: Bool { state == .calculated }

    func property(_ id: PropertyID) -> PropertyValue? {
        calculatedProperties.first { $0.property == id }
    }

    func validationLabel(for property: PropertyID) -> String {
        if model == .general { return "General engineering calculation" }
        if validatedProperties.contains(property) { return "Validated" }
        return self.property(property)?.hasFiniteCalculatedValue == true
            ? "Not independently validated"
            : "Unsupported"
    }
}

struct CaseBatchCalculationService: Sendable {
    let registry: ProviderRegistry
    let clientVersion: String
    let applicationIdentity: ApplicationIdentity

    init(
        registry: ProviderRegistry = ProviderRegistry(),
        clientVersion: String = Bundle.main.releaseVersion,
        applicationIdentity: ApplicationIdentity = Bundle.main.applicationIdentity
    ) {
        self.registry = registry
        self.clientVersion = clientVersion
        self.applicationIdentity = applicationIdentity
    }

    func calculate(_ input: BatchCaseInput, model: BatchCalculationModel) async -> BatchCaseResult {
        let clock = ContinuousClock()
        let started = clock.now
        func result(
            _ state: BatchResultState,
            record: CalculationRecord? = nil,
            validated: Set<PropertyID> = [],
            message: String? = nil
        ) -> BatchCaseResult {
            let elapsed = started.duration(to: clock.now).components
            return BatchCaseResult(
                id: input.id, input: input, model: model, state: state, record: record,
                modelDescriptor: registry.descriptors.first { $0.id == model.id },
                applicationIdentity: applicationIdentity,
                validatedProperties: validated, message: message, completedAt: Date(),
                durationMilliseconds: Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15
            )
        }

        guard !Task.isCancelled else { return result(.cancelled) }
        guard input.isComplete, let pressurePa = input.pressurePa, let temperatureK = input.temperatureK else {
            return result(.failed, message: "The case does not contain a complete composition, pressure and temperature snapshot.")
        }
        guard let provider = registry.provider(id: model.id) else {
            return result(.unsupported, message: "The selected calculation model is unavailable on this device.")
        }

        let validated = model == .advanced
            ? Set(AdvancedValidationPresentation.validatedProperties(
                composition: input.composition, pressurePa: pressurePa, temperatureK: temperatureK
            ))
            : []
        guard model != .advanced || !validated.isEmpty else {
            return result(
                .outsideValidatedRange,
                message: "No Advanced CCS production property is validated for this exact composition and state. General Properties was not substituted."
            )
        }

        let request = CalculationRequest(
            modelID: model.id, pressurePa: pressurePa, temperatureK: temperatureK,
            composition: input.composition, clientVersion: clientVersion
        )
        do {
            let response = try await provider.calculate(request)
            guard !Task.isCancelled else { return result(.cancelled) }
            let inputSnapshot = input.originalInput ?? CalculationInputSnapshot(
                pressureValue: pressurePa / 100_000, pressureUnit: .bara, pressurePa: pressurePa,
                temperatureValue: temperatureK - 273.15, temperatureUnit: .celsius,
                temperatureK: temperatureK,
                originalComposition: input.composition.map {
                    CompositionInputSnapshot(component: $0.component, value: $0.moleFraction * 100, unit: .molePercent)
                }
            )
            let record = CalculationRecord(
                request: request, input: inputSnapshot, response: response, application: applicationIdentity
            )
            return result(.calculated, record: record, validated: validated)
        } catch is CancellationError {
            return result(.cancelled)
        } catch {
            return result(.failed, validated: validated, message: String(describing: error))
        }
    }
}

@MainActor @Observable
final class CaseBatchComparisonController {
    private(set) var results: [BatchCaseResult] = []
    private(set) var isCalculating = false
    private(set) var completedCount = 0
    private(set) var resultModel: BatchCalculationModel?
    var selectedModel: BatchCalculationModel = .general {
        didSet { if selectedModel != oldValue { invalidateResults() } }
    }
    private var calculationTask: Task<Void, Never>?
    private var activeRunID: UUID?
    private let service: CaseBatchCalculationService

    init(service: CaseBatchCalculationService = CaseBatchCalculationService()) { self.service = service }

    func calculate(_ inputs: [BatchCaseInput]) {
        cancel()
        results = []
        completedCount = 0
        resultModel = selectedModel
        isCalculating = true
        let runID = UUID()
        activeRunID = runID
        let service = service
        let model = selectedModel
        calculationTask = Task {
            // The pinned native engines own library state that is not safe for
            // simultaneous calls. Keep the batch asynchronous but serialize
            // provider entry while yielding between independent cases.
            for input in inputs {
                guard !Task.isCancelled else { break }
                let result = await service.calculate(input, model: model)
                guard !Task.isCancelled, activeRunID == runID else { break }
                results.append(result)
                completedCount += 1
                await Task.yield()
            }
            guard activeRunID == runID else { return }
            results.sort { lhs, rhs in
                let li = inputs.firstIndex { $0.id == lhs.id } ?? .max
                let ri = inputs.firstIndex { $0.id == rhs.id } ?? .max
                return li < ri
            }
            isCalculating = false
            calculationTask = nil
            activeRunID = nil
        }
    }

    func cancel() {
        calculationTask?.cancel()
        calculationTask = nil
        activeRunID = nil
        isCalculating = false
    }

    func invalidateResults() {
        cancel()
        results = []
        completedCount = 0
        resultModel = nil
    }
}

enum BatchComparisonSort: String, CaseIterable, Identifiable {
    case selection = "Selection order"
    case name = "Case name"
    case pressure = "Pressure"
    case temperature = "Temperature"
    case density = "Density"
    var id: String { rawValue }
}

struct BatchComparisonCSVExporter {
    static let componentColumns = ComponentID.allCases

    func data(results: [BatchCaseResult]) -> Data {
        let propertyIDs: [PropertyID] = [.density, .molarMass, .specificVolume, .compressibilityFactor,
                                         .dynamicViscosity, .speedOfSound, .isobaricHeatCapacity,
                                         .isochoricHeatCapacity, .heatCapacityRatio]
        var headers = ["case_id", "case_name", "case_origin", "model_id", "model_name", "model_version", "provider_version",
                       "application_version", "application_build", "calculation_id",
                       "temperature_K", "pressure_Pa", "phase", "result_status", "error",
                       "input_fingerprint", "source_calculation_id"]
        headers += Self.componentColumns.map { "mole_fraction_\($0.rawValue)" }
        for property in propertyIDs {
            headers += ["\(property.rawValue)_value", "\(property.rawValue)_unit", "\(property.rawValue)_status", "\(property.rawValue)_validation"]
        }
        var rows = [headers]
        for result in results {
            var row = [result.input.id, result.input.name, result.input.origin.rawValue, result.model.id,
                       result.model.displayName, result.modelDescriptor?.modelVersion ?? "",
                       result.modelDescriptor?.providerVersion ?? "", result.applicationIdentity.version,
                       result.applicationIdentity.build, result.record?.response.calculationID.uuidString ?? "",
                       number(result.input.temperatureK), number(result.input.pressurePa),
                       result.phase.rawValue, result.state.rawValue, result.message ?? "", result.input.fingerprint,
                       result.input.sourceCalculationID?.uuidString ?? ""]
            let composition = Dictionary(uniqueKeysWithValues: result.input.composition.map { ($0.component, $0.moleFraction) })
            row += Self.componentColumns.map { number(composition[$0]) }
            for propertyID in propertyIDs {
                let property = result.property(propertyID)
                row += [number(property?.value), property?.unit ?? "", property?.status.rawValue ?? "unavailable",
                        result.validationLabel(for: propertyID)]
            }
            rows.append(row)
        }
        let csv = rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
        return Data(csv.utf8)
    }

    private func number(_ value: Double?) -> String {
        value?.isFinite == true ? String(format: "%.17g", value!) : ""
    }
    private func escape(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

struct BatchComparisonPDFExporter {
    func data(results: [BatchCaseResult], model: BatchCalculationModel, date: Date = Date()) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        return renderer.pdfData { context in
            var y: CGFloat = 54
            func line(_ text: String, font: UIFont = .systemFont(ofSize: 10), color: UIColor = .label) {
                if y > 742 { context.beginPage(); y = 54 }
                (text as NSString).draw(at: CGPoint(x: 42, y: y), withAttributes: [.font: font, .foregroundColor: color])
                y += font.lineHeight + 5
            }
            context.beginPage()
            line("PhaseXpert — Case batch comparison", font: .boldSystemFont(ofSize: 20), color: .systemBlue)
            line("Generated: \(date.formatted(date: .abbreviated, time: .shortened))")
            line("Selected model: \(model.displayName) [\(model.id)]", font: .boldSystemFont(ofSize: 11))
            line(model == .advanced ? "Advanced CCS validation is property-specific; — means unsupported or outside the validated property domain." : "General engineering calculation; Advanced validation shields do not apply.", color: .secondaryLabel)
            for result in results {
                y += 7
                line(result.input.name, font: .boldSystemFont(ofSize: 13))
                line("\(result.input.origin.rawValue) • \(result.state.rawValue) • \(number(result.input.temperatureK)) K • \(number(result.input.pressurePa)) Pa • Phase: \(result.phase.displayName)")
                line("Model \(result.modelDescriptor?.modelVersion ?? "unavailable") • Provider \(result.modelDescriptor?.providerVersion ?? "unavailable") • App \(result.applicationIdentity.version) (\(result.applicationIdentity.build))", font: .systemFont(ofSize: 8), color: .secondaryLabel)
                line("Composition: \(compositionSummary(result.input.composition))", font: .systemFont(ofSize: 8), color: .secondaryLabel)
                line("Input fingerprint: \(result.input.fingerprint)", font: .systemFont(ofSize: 8), color: .secondaryLabel)
                if let message = result.message { line("Detail: \(message)", color: .systemRed) }
                let values = result.calculatedProperties.filter(\.hasFiniteCalculatedValue)
                if !values.isEmpty {
                    line(values.map { "\($0.property.displayName)=\(number($0.value)) \($0.unit) [\(result.validationLabel(for: $0.property))]" }.joined(separator: "  |  "), font: .systemFont(ofSize: 9))
                }
            }
            y += 10
            line("Each row retains its immutable input snapshot and selected provider. No provider fallback or composition substitution is performed.", color: .secondaryLabel)
        }
    }
    private func number(_ value: Double?) -> String { value?.isFinite == true ? String(format: "%.8g", value!) : "—" }
}

struct CaseBatchComparisonWorkflowView: View {
    let cases: [BatchCaseInput]
    @Environment(AppNavigationState.self) private var navigationState
    @State private var selectedIDs: Set<String> = []
    @State private var controller = CaseBatchComparisonController()
    @State private var showResults = false

    var body: some View {
        @Bindable var controller = controller
        List {
            Section {
                Picker("Calculation model", selection: $controller.selectedModel) {
                    ForEach(BatchCalculationModel.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: { Text("One model for every case") }
              footer: { Text("PhaseXpert never substitutes another provider when a selected model is unsupported.") }
            Section("Select 2–20 cases") {
                ForEach(cases) { item in
                    Button { toggle(item.id) } label: { selectionRow(item) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("batch-case-\(item.id)")
                }
            }
            Section {
                if controller.isCalculating {
                    ProgressView(value: Double(controller.completedCount), total: Double(selectedIDs.count))
                    Button("Cancel", role: .cancel) { controller.cancel() }
                } else {
                    Button("Calculate selected cases") {
                        controller.calculate(selectedCases)
                        showResults = true
                    }
                    .disabled(selectedIDs.count < 2)
                    .accessibilityIdentifier("calculate-batch-cases")
                }
            }
        }
        .navigationTitle("Compare Cases")
        .navigationDestination(isPresented: $showResults) {
            BatchComparisonResultsView(controller: controller, selectedCount: selectedIDs.count)
        }
    }

    private var selectedCases: [BatchCaseInput] { cases.filter { selectedIDs.contains($0.id) } }
    private func toggle(_ id: String) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) }
        else if selectedIDs.count < 20 { selectedIDs.insert(id) }
    }
    private func selectionRow(_ item: BatchCaseInput) -> some View {
        HStack {
            Image(systemName: selectedIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selectedIDs.contains(item.id) ? Color.ifePrimary : .secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(.headline)
                Text("\(item.origin.rawValue) • \(formatC(item.temperatureK)) • \(formatBar(item.pressurePa))")
                    .font(.caption).foregroundStyle(.secondary)
                Text(compositionSummary(item.composition)).font(.caption2).foregroundStyle(.secondary)
            }
        }.accessibilityElement(children: .combine)
         .accessibilityValue(selectedIDs.contains(item.id) ? "Selected" : "Not selected")
    }
}

struct BatchComparisonResultsView: View {
    @Bindable var controller: CaseBatchComparisonController
    let selectedCount: Int
    @Environment(AppNavigationState.self) private var navigationState
    @State private var sort: BatchComparisonSort = .selection
    @State private var referenceID: String?
    @State private var detail: BatchCaseResult?
    @State private var exportURLs: [URL] = []
    @State private var exportError: String?

    var body: some View {
        List {
            Section { summary }
            Section("Controls") {
                Picker("Sort", selection: $sort) { ForEach(BatchComparisonSort.allCases) { Text($0.rawValue).tag($0) } }
                Picker("Delta reference", selection: $referenceID) {
                    Text("None").tag(String?.none)
                    ForEach(controller.results) { Text($0.input.name).tag(String?.some($0.id)) }
                }
            }
            Section("Engineering comparison") {
                ScrollView(.horizontal) { comparisonGrid.fixedSize(horizontal: true, vertical: false) }
                    .accessibilityIdentifier("batch-comparison-table")
            }
            Section("Cases") {
                ForEach(sortedResults) { result in
                    Button { detail = result } label: {
                        VStack(alignment: .leading) {
                            Text(result.input.name).font(.headline)
                            Text(result.state.rawValue).foregroundStyle(result.state == .calculated ? .primary : .secondary)
                            if result.model == .advanced, !result.validatedProperties.isEmpty {
                                Text("Validated: \(AdvancedValidationPresentation.propertyList(Array(result.validatedProperties)))").font(.caption)
                            }
                        }
                    }
                }
            }
            Section("Export and share") {
                Button("Prepare CSV and PDF", systemImage: "doc.badge.arrow.up") { prepareExports() }
                    .disabled(controller.results.isEmpty)
                    .accessibilityIdentifier("export-batch-comparison")
                ForEach(exportURLs, id: \.self) { url in ShareLink(item: url) { Label("Share \(url.pathExtension.uppercased())", systemImage: "square.and.arrow.up") } }
            }
        }
        .navigationTitle("Comparison Results")
        .sheet(item: $detail) { BatchCaseResultDetailView(result: $0) }
        .alert("Unable to prepare exports", isPresented: Binding(
            get: { exportError != nil }, set: { if !$0 { exportError = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(exportError ?? "") }
    }

    private var summary: some View {
        let successes = controller.results.filter(\.isSuccessful).count
        let outside = controller.results.filter { $0.state == .outsideValidatedRange }.count
        let failed = controller.results.filter { $0.state == .failed || $0.state == .unsupported }.count
        return VStack(alignment: .leading) {
            Text("\(controller.completedCount) of \(selectedCount) completed").font(.headline)
            Text("\(successes) successful • \(outside) outside validated range • \(failed) failed")
            if controller.isCalculating { ProgressView(value: Double(controller.completedCount), total: Double(selectedCount)) }
        }
    }

    private var sortedResults: [BatchCaseResult] {
        switch sort {
        case .selection: controller.results
        case .name: controller.results.sorted { $0.input.name.localizedStandardCompare($1.input.name) == .orderedAscending }
        case .pressure: controller.results.sorted { ($0.input.pressurePa ?? .infinity) < ($1.input.pressurePa ?? .infinity) }
        case .temperature: controller.results.sorted { ($0.input.temperatureK ?? .infinity) < ($1.input.temperatureK ?? .infinity) }
        case .density: controller.results.sorted { ($0.property(.density)?.value ?? .infinity) < ($1.property(.density)?.value ?? .infinity) }
        }
    }

    private var visibleProperties: [PropertyID] {
        let preferred: [PropertyID] = [.density, .molarMass, .specificVolume, .compressibilityFactor, .dynamicViscosity, .speedOfSound, .isobaricHeatCapacity, .isochoricHeatCapacity, .heatCapacityRatio]
        return preferred.filter { id in controller.results.contains { $0.property(id)?.hasFiniteCalculatedValue == true } }
    }

    private var comparisonGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
            GridRow { Text("Case").bold(); ForEach(sortedResults) { Text($0.input.name).bold().frame(width: 150, alignment: .leading) } }
            gridRow("Model") { $0.model.displayName }
            gridRow("T") { formatC($0.input.temperatureK) }
            gridRow("P") { formatBar($0.input.pressurePa) }
            gridRow("Phase") { $0.phase.displayName }
            gridRow("Status") { $0.state.rawValue }
            ForEach(visibleProperties, id: \.self) { property in
                gridRow(property.displayName) { formattedProperty($0, property: property) }
            }
        }.padding(.vertical, 4)
    }

    private func gridRow(_ title: String, value: @escaping (BatchCaseResult) -> String) -> some View {
        GridRow { Text(title).bold(); ForEach(sortedResults) { Text(value($0)).frame(width: 150, alignment: .leading) } }
    }
    private func formattedProperty(_ result: BatchCaseResult, property: PropertyID) -> String {
        guard let value = result.property(property), value.hasFiniteCalculatedValue, let number = value.value else { return "—" }
        let delta: String
        if let referenceID, let reference = controller.results.first(where: { $0.id == referenceID }),
           let ref = reference.property(property), ref.hasFiniteCalculatedValue, let refValue = ref.value,
           ref.unit == value.unit {
            delta = " (Δ \(String(format: "%+.5g", number - refValue)))"
        } else { delta = "" }
        let badge: String
        if result.model == .advanced {
            badge = result.validatedProperties.contains(property) ? " ✓" : " · not validated"
        } else { badge = "" }
        return "\(String(format: "%.6g", number)) \(value.unit)\(delta)\(badge)"
    }
    private func prepareExports() {
        let directory = FileManager.default.temporaryDirectory
        let csv = directory.appendingPathComponent("PhaseXpert-Case-Comparison.csv")
        let pdf = directory.appendingPathComponent("PhaseXpert-Case-Comparison.pdf")
        do {
            try BatchComparisonCSVExporter().data(results: controller.results).write(to: csv, options: .atomic)
            try BatchComparisonPDFExporter().data(results: controller.results, model: controller.resultModel ?? controller.selectedModel).write(to: pdf, options: .atomic)
            exportURLs = [csv, pdf]
            exportError = nil
        } catch {
            exportURLs = []
            exportError = error.localizedDescription
        }
    }
}

private struct BatchCaseResultDetailView: View {
    let result: BatchCaseResult
    @Environment(AppNavigationState.self) private var navigationState
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("Input snapshot") {
                    LabeledContent("Case", value: result.input.name)
                    LabeledContent("Origin", value: result.input.origin.rawValue)
                    LabeledContent("Model", value: result.model.displayName)
                    LabeledContent("Temperature", value: formatC(result.input.temperatureK))
                    LabeledContent("Pressure", value: formatBar(result.input.pressurePa))
                    Text(compositionSummary(result.input.composition))
                }
                Section("Result") {
                    LabeledContent("Status", value: result.state.rawValue)
                    LabeledContent("Phase", value: result.phase.displayName)
                    if let message = result.message { Text(message).foregroundStyle(.secondary) }
                    ForEach(result.calculatedProperties, id: \.property) { property in
                        LabeledContent(property.property.displayName, value: property.hasFiniteCalculatedValue ? "\(String(format: "%.8g", property.value!)) \(property.unit) • \(result.validationLabel(for: property.property))" : property.status.displayName)
                    }
                }
                Section("Provenance") { Text(result.input.fingerprint).font(.caption.monospaced()) }
                Section { Button("Open in Calculator") { openInCalculator() } }
            }.navigationTitle(result.input.name)
        }
    }
    private func openInCalculator() {
        navigationState.openBatchCaseInCalculator(result.input, model: result.model)
        dismiss()
    }
}

private func formatC(_ kelvin: Double?) -> String { kelvin?.isFinite == true ? "\(String(format: "%.3g", kelvin! - 273.15)) °C" : "Missing T" }
private func formatBar(_ pascal: Double?) -> String { pascal?.isFinite == true ? "\(String(format: "%.4g", pascal! / 100_000)) bar(a)" : "Missing P" }
private func compositionSummary(_ composition: [MixtureComponent]) -> String {
    composition.isEmpty ? "Missing composition" : composition.map { "\($0.component.symbol) \(String(format: "%.5g", $0.moleFraction * 100)) mol%" }.joined(separator: " • ")
}
