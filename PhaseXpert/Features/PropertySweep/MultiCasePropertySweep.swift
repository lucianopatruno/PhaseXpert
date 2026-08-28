import Charts
import Foundation
import Observation
import PDFKit
import PhaseXpertCore
import SwiftUI
import UIKit

enum MultiCaseFixedConditionMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case preserveEachCase = "Preserve each case"
    case commonFixedValue = "Use one common value"
    var id: String { rawValue }
}

struct MultiCaseSweepDefinition: Equatable, Sendable {
    var axis: PropertySweepAxis
    var property: PropertyID
    var startValueSI: Double
    var endValueSI: Double
    var pointCount: Int
    var fixedMode: MultiCaseFixedConditionMode
    var commonFixedValueSI: Double?
}

enum MultiCaseSweepPointState: String, Codable, Sendable {
    case generalCalculated = "General engineering calculation"
    case advancedValidated = "Validated"
    case outsideValidatedRange = "Outside validated range"
    case failed = "Calculation failed"
    case cancelled = "Cancelled"
}

struct MultiCaseSweepPoint: Identifiable, Equatable, Sendable {
    let id: UUID
    let index: Int
    let pressurePa: Double
    let temperatureK: Double
    let response: CalculationResponse?
    let state: MultiCaseSweepPointState
    let validatedProperties: Set<PropertyID>
    let errorMessage: String?

    init(
        id: UUID = UUID(), index: Int, pressurePa: Double, temperatureK: Double,
        response: CalculationResponse?, state: MultiCaseSweepPointState,
        validatedProperties: Set<PropertyID>, errorMessage: String?
    ) {
        self.id = id
        self.index = index
        self.pressurePa = pressurePa
        self.temperatureK = temperatureK
        self.response = response
        self.state = state
        self.validatedProperties = validatedProperties
        self.errorMessage = errorMessage
    }

    func value(for property: PropertyID) -> PropertyValue? {
        response?.properties.first { $0.property == property }
    }

    func calculatorInput(from source: BatchCaseInput) -> BatchCaseInput {
        BatchCaseInput(
            id: "\(source.id):sweep:\(index)", name: "\(source.name) — sweep point",
            origin: source.origin, pressurePa: pressurePa, temperatureK: temperatureK,
            composition: source.composition, originalInput: nil,
            sourceCalculationID: response?.calculationID
        )
    }
}

struct MultiCaseSweepSeries: Identifiable, Equatable, Sendable {
    var id: String { input.id }
    let input: BatchCaseInput
    let points: [MultiCaseSweepPoint]
    let durationMilliseconds: Double

    func summary(property: PropertyID) -> MultiCaseSweepSummary {
        let valid = points.compactMap { point -> (MultiCaseSweepPoint, Double)? in
            guard let value = point.value(for: property), value.hasFiniteCalculatedValue,
                  let number = value.value else { return nil }
            return (point, number)
        }
        let minimum = valid.min { $0.1 < $1.1 }
        let maximum = valid.max { $0.1 < $1.1 }
        return MultiCaseSweepSummary(
            minimumPoint: minimum?.0, minimumValue: minimum?.1,
            maximumPoint: maximum?.0, maximumValue: maximum?.1,
            successfulCount: valid.count,
            validatedCount: points.filter { $0.state == .advancedValidated }.count,
            outsideRangeCount: points.filter { $0.state == .outsideValidatedRange }.count,
            failedCount: points.filter { $0.state == .failed }.count
        )
    }
}

struct MultiCaseSweepSummary: Equatable, Sendable {
    let minimumPoint: MultiCaseSweepPoint?
    let minimumValue: Double?
    let maximumPoint: MultiCaseSweepPoint?
    let maximumValue: Double?
    let successfulCount: Int
    let validatedCount: Int
    let outsideRangeCount: Int
    let failedCount: Int
}

struct MultiCasePropertySweepResult: Identifiable, Equatable, Sendable {
    let id: UUID
    let model: BatchCalculationModel
    let definition: MultiCaseSweepDefinition
    let series: [MultiCaseSweepSeries]
    let generatedAt: Date
    let durationMilliseconds: Double
    let modelDescriptor: ModelDescriptor?
    let applicationIdentity: ApplicationIdentity

    var totalPointCount: Int { series.reduce(0) { $0 + $1.points.count } }
    var completedPointCount: Int {
        series.reduce(0) { count, series in
            count + series.points.filter { $0.state != .cancelled }.count
        }
    }

    func delta(
        caseID: String, referenceCaseID: String, pointIndex: Int
    ) -> Double? {
        guard caseID != referenceCaseID,
              let value = series.first(where: { $0.id == caseID })?.points
                .first(where: { $0.index == pointIndex })?.value(for: definition.property),
              let reference = series.first(where: { $0.id == referenceCaseID })?.points
                .first(where: { $0.index == pointIndex })?.value(for: definition.property),
              value.hasFiniteCalculatedValue, reference.hasFiniteCalculatedValue,
              value.unit == reference.unit,
              let lhs = value.value, let rhs = reference.value else { return nil }
        return lhs - rhs
    }
}

struct MultiCasePropertySweepService: Sendable {
    typealias Progress = @MainActor @Sendable (_ completed: Int, _ total: Int) -> Void
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

    func run(
        cases: [BatchCaseInput], model: BatchCalculationModel,
        definition: MultiCaseSweepDefinition, progress: Progress? = nil
    ) async throws -> MultiCasePropertySweepResult {
        let started = ContinuousClock.now
        let total = cases.count * definition.pointCount
        var completed = 0
        var output: [MultiCaseSweepSeries] = []
        output.reserveCapacity(cases.count)

        guard let baseProvider = registry.provider(id: model.id) else {
            for input in cases {
                let points = syntheticPoints(input: input, definition: definition).map {
                    MultiCaseSweepPoint(index: $0.index, pressurePa: $0.pressurePa,
                                        temperatureK: $0.temperatureK, response: nil,
                                        state: .failed, validatedProperties: [],
                                        errorMessage: "The selected provider is unavailable.")
                }
                output.append(.init(input: input, points: points, durationMilliseconds: 0))
            }
            return result(started: started, model: model, definition: definition, series: output)
        }

        let provider: any ThermodynamicModelProvider = model == .advanced
            ? PointwiseAdvancedSweepProvider(base: baseProvider, property: definition.property)
            : PointwiseGeneralSweepProvider(base: baseProvider)

        // PropertySweepRunner and the pinned native libraries are deliberately
        // entered serially. This preserves PR #72's native-safety assumption.
        for input in cases {
            try Task.checkCancellation()
            let seriesStarted = ContinuousClock.now
            guard input.isComplete,
                  let storedPressure = input.pressurePa,
                  let storedTemperature = input.temperatureK else {
                let points = syntheticPoints(input: input, definition: definition).map {
                    MultiCaseSweepPoint(index: $0.index, pressurePa: $0.pressurePa,
                                        temperatureK: $0.temperatureK, response: nil,
                                        state: .failed, validatedProperties: [],
                                        errorMessage: "The case has incomplete pressure, temperature or composition data.")
                }
                completed += points.count
                await progress?(completed, total)
                output.append(.init(input: input, points: points, durationMilliseconds: elapsedMilliseconds(since: seriesStarted)))
                continue
            }

            let fixedPressure = definition.axis == .temperature && definition.fixedMode == .commonFixedValue
                ? definition.commonFixedValueSI ?? storedPressure : storedPressure
            let fixedTemperature = definition.axis == .pressure && definition.fixedMode == .commonFixedValue
                ? definition.commonFixedValueSI ?? storedTemperature : storedTemperature
            let baseRequest = CalculationRequest(
                modelID: model.id, pressurePa: fixedPressure, temperatureK: fixedTemperature,
                composition: input.composition, requestedProperties: [definition.property],
                clientVersion: clientVersion
            )
            let request = PropertySweepRequest(
                baseRequest: baseRequest, axis: definition.axis,
                startValueSI: definition.startValueSI, endValueSI: definition.endValueSI,
                pointCount: definition.pointCount, property: definition.property
            )
            do {
                let sweep = try await PropertySweepRunner(provider: provider).run(request) { caseCompleted, _ in
                    progress?(completed + caseCompleted, total)
                }
                let points = sweep.samples.map { sample in
                    makePoint(sample: sample, input: input, model: model, property: definition.property)
                }
                completed += points.count
                output.append(.init(input: input, points: points, durationMilliseconds: sweep.durationMilliseconds))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let points = syntheticPoints(input: input, definition: definition).map { generated in
                    makeFailurePoint(generated, input: input, model: model,
                                     property: definition.property, error: error)
                }
                completed += points.count
                await progress?(completed, total)
                output.append(.init(input: input, points: points,
                                    durationMilliseconds: elapsedMilliseconds(since: seriesStarted)))
            }
            await Task.yield()
        }
        return result(started: started, model: model, definition: definition, series: output)
    }

    private func makePoint(
        sample: PropertySweepSample, input: BatchCaseInput,
        model: BatchCalculationModel, property: PropertyID
    ) -> MultiCaseSweepPoint {
        let validated = validatedProperties(input.composition, pressurePa: sample.pressurePa, temperatureK: sample.temperatureK)
        let hasValue = sample.value(for: property)?.hasFiniteCalculatedValue == true
        let state: MultiCaseSweepPointState
        if model == .general { state = hasValue ? .generalCalculated : .failed }
        else if validated.contains(property), hasValue { state = .advancedValidated }
        else if !validated.contains(property) { state = .outsideValidatedRange }
        else { state = .failed }
        return MultiCaseSweepPoint(
            id: sample.id, index: sample.index, pressurePa: sample.pressurePa,
            temperatureK: sample.temperatureK, response: state == .outsideValidatedRange ? nil : sample.response,
            state: state, validatedProperties: validated,
            errorMessage: sample.errorMessage ?? sample.value(for: property)?.message
        )
    }

    private func makeFailurePoint(
        _ generated: GeneratedPoint, input: BatchCaseInput,
        model: BatchCalculationModel, property: PropertyID, error: Error
    ) -> MultiCaseSweepPoint {
        let validated = validatedProperties(input.composition, pressurePa: generated.pressurePa, temperatureK: generated.temperatureK)
        return MultiCaseSweepPoint(
            index: generated.index, pressurePa: generated.pressurePa,
            temperatureK: generated.temperatureK, response: nil,
            state: model == .advanced && !validated.contains(property) ? .outsideValidatedRange : .failed,
            validatedProperties: validated,
            errorMessage: (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        )
    }

    private func validatedProperties(
        _ composition: [MixtureComponent], pressurePa: Double, temperatureK: Double
    ) -> Set<PropertyID> {
        guard let canonical = try? CanonicalComposition(composition) else { return [] }
        let matrix = AdvancedCCSCapabilityMatrix()
        return Set(PropertyID.allCases.filter {
            matrix.decision(for: canonical, property: $0, pressurePa: pressurePa,
                            temperatureK: temperatureK).validationState == .validated
        })
    }

    private struct GeneratedPoint { let index: Int; let pressurePa: Double; let temperatureK: Double }
    private func syntheticPoints(input: BatchCaseInput, definition: MultiCaseSweepDefinition) -> [GeneratedPoint] {
        let fixedPressure = definition.axis == .temperature && definition.fixedMode == .commonFixedValue
            ? definition.commonFixedValueSI ?? input.pressurePa ?? .nan : input.pressurePa ?? .nan
        let fixedTemperature = definition.axis == .pressure && definition.fixedMode == .commonFixedValue
            ? definition.commonFixedValueSI ?? input.temperatureK ?? .nan : input.temperatureK ?? .nan
        return (0..<max(definition.pointCount, 0)).map { index in
            let fraction = definition.pointCount > 1 ? Double(index) / Double(definition.pointCount - 1) : 0
            let coordinate = index == definition.pointCount - 1 ? definition.endValueSI
                : definition.startValueSI + (definition.endValueSI - definition.startValueSI) * fraction
            return GeneratedPoint(index: index,
                                  pressurePa: definition.axis == .pressure ? coordinate : fixedPressure,
                                  temperatureK: definition.axis == .temperature ? coordinate : fixedTemperature)
        }
    }

    private func result(
        started: ContinuousClock.Instant, model: BatchCalculationModel,
        definition: MultiCaseSweepDefinition, series: [MultiCaseSweepSeries]
    ) -> MultiCasePropertySweepResult {
        MultiCasePropertySweepResult(
            id: UUID(), model: model, definition: definition, series: series,
            generatedAt: Date(), durationMilliseconds: elapsedMilliseconds(since: started),
            modelDescriptor: registry.descriptors.first { $0.id == model.id },
            applicationIdentity: applicationIdentity
        )
    }

    private func elapsedMilliseconds(since start: ContinuousClock.Instant) -> Double {
        let elapsed = start.duration(to: .now).components
        return Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15
    }
}

private struct PointwiseAdvancedSweepProvider: ThermodynamicModelProvider {
    let base: any ThermodynamicModelProvider
    let property: PropertyID
    var descriptor: ModelDescriptor { base.descriptor }
    func applicabilityIssues(for composition: [MixtureComponent]) -> [ValidationIssue] {
        base.applicabilityIssues(for: composition)
    }
    func operatingRangeGuidance(for context: OperatingGuidanceContext) -> OperatingRangeGuidance? {
        base.operatingRangeGuidance(for: context)
    }
    func calculate(_ request: CalculationRequest) async throws -> CalculationResponse {
        guard let canonical = try? CanonicalComposition(request.composition),
              AdvancedCCSCapabilityMatrix().decision(
                for: canonical, property: property, pressurePa: request.pressurePa,
                temperatureK: request.temperatureK
              ).validationState == .validated else {
            throw ProviderError.invalidRequest("Outside validated range for \(property.rawValue).")
        }
        return try await base.calculate(request)
    }
    func phaseEnvelope(_ request: PhaseEnvelopeRequest) async throws -> PhaseEnvelopeResponse {
        try await base.phaseEnvelope(request)
    }
}

private struct PointwiseGeneralSweepProvider: ThermodynamicModelProvider {
    let base: any ThermodynamicModelProvider
    var descriptor: ModelDescriptor { base.descriptor }
    func applicabilityIssues(for composition: [MixtureComponent]) -> [ValidationIssue] {
        base.applicabilityIssues(for: composition)
    }
    func operatingRangeGuidance(for context: OperatingGuidanceContext) -> OperatingRangeGuidance? {
        base.operatingRangeGuidance(for: context)
    }
    func calculate(_ request: CalculationRequest) async throws -> CalculationResponse {
        let active = request.composition.filter { $0.moleFraction > 0 }
        if active.count > 1, !active.contains(where: { $0.component == .water }),
           let screening = base as? any PointPhaseScreeningModelProvider {
            return try await screening.calculateScreenedHomogeneous(request)
        }
        return try await base.calculate(request)
    }
    func phaseEnvelope(_ request: PhaseEnvelopeRequest) async throws -> PhaseEnvelopeResponse {
        try await base.phaseEnvelope(request)
    }
}

@MainActor @Observable
final class MultiCasePropertySweepController {
    var model: BatchCalculationModel { didSet { if model != oldValue { invalidate() } } }
    var definition: MultiCaseSweepDefinition { didSet { if definition != oldValue { invalidate() } } }
    private(set) var result: MultiCasePropertySweepResult?
    private(set) var isRunning = false
    private(set) var completedPoints = 0
    private(set) var totalPoints = 0
    private(set) var errorMessage: String?
    private let service: MultiCasePropertySweepService
    private var task: Task<Void, Never>?
    private var runID: UUID?

    init(model: BatchCalculationModel, definition: MultiCaseSweepDefinition,
         service: MultiCasePropertySweepService = MultiCasePropertySweepService()) {
        self.model = model
        self.definition = definition
        self.service = service
    }

    func start(cases: [BatchCaseInput]) {
        cancel()
        result = nil
        errorMessage = nil
        completedPoints = 0
        totalPoints = cases.count * definition.pointCount
        isRunning = true
        let currentRun = UUID()
        runID = currentRun
        let service = service, model = model, definition = definition
        task = Task {
            do {
                let completed = try await service.run(cases: cases, model: model, definition: definition) { [weak self] done, _ in
                    guard self?.runID == currentRun else { return }
                    self?.completedPoints = done
                }
                guard runID == currentRun else { return }
                result = completed
                completedPoints = completed.totalPointCount
                isRunning = false
                task = nil
                runID = nil
            } catch is CancellationError {
                guard runID == currentRun else { return }
                isRunning = false
                task = nil
                runID = nil
            } catch {
                guard runID == currentRun else { return }
                errorMessage = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                isRunning = false
                task = nil
                runID = nil
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        runID = nil
        isRunning = false
    }

    func invalidate() {
        cancel()
        result = nil
        completedPoints = 0
        totalPoints = 0
        errorMessage = nil
    }
}

struct MultiCaseSweepCSVExporter {
    static let componentColumns = ComponentID.allCases
    func data(_ result: MultiCasePropertySweepResult) -> Data {
        var header = ["run_id", "generated_at", "case_id", "case_name", "case_origin",
                      "provider_id", "model_version", "provider_version", "input_fingerprint",
                      "source_calculation_id", "sweep_axis", "fixed_condition_mode", "point_index",
                      "sweep_coordinate_si", "pressure_Pa", "temperature_K"]
        header += Self.componentColumns.map { "mole_fraction_\($0.rawValue)" }
        header += ["property_id", "property_value", "property_unit", "phase", "point_status",
                   "validated_property_ids", "calculation_id", "error", "application_version", "application_build"]
        var rows = [header]
        for series in result.series {
            let composition = Dictionary(uniqueKeysWithValues: series.input.composition.map { ($0.component, $0.moleFraction) })
            for point in series.points {
                let property = point.value(for: result.definition.property)
                let coordinate = result.definition.axis == .pressure ? point.pressurePa : point.temperatureK
                var row = [result.id.uuidString, ISO8601DateFormatter().string(from: result.generatedAt),
                           series.input.id, series.input.name, series.input.origin.rawValue,
                           result.model.id, result.modelDescriptor?.modelVersion ?? "",
                           result.modelDescriptor?.providerVersion ?? "", series.input.fingerprint,
                           series.input.sourceCalculationID?.uuidString ?? "", result.definition.axis.rawValue,
                           result.definition.fixedMode.rawValue, String(point.index), number(coordinate),
                           number(point.pressurePa), number(point.temperatureK)]
                row += Self.componentColumns.map { number(composition[$0]) }
                row += [result.definition.property.rawValue, number(property?.value), property?.unit ?? "",
                        point.response?.phase.rawValue ?? "", point.state.rawValue,
                        point.validatedProperties.map(\.rawValue).sorted().joined(separator: ";"),
                        point.response?.calculationID.uuidString ?? "", point.errorMessage ?? "",
                        result.applicationIdentity.version, result.applicationIdentity.build]
                rows.append(row)
            }
        }
        return Data((rows.map { $0.map(csvEscape).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n").utf8)
    }
    private func number(_ value: Double?) -> String { value?.isFinite == true ? String(format: "%.17g", value!) : "" }
    private func csvEscape(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

struct MultiCaseSweepPDFExporter {
    func data(_ result: MultiCasePropertySweepResult) -> Data {
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        return UIGraphicsPDFRenderer(bounds: page).pdfData { context in
            context.beginPage()
            var y: CGFloat = 45
            func text(_ value: String, size: CGFloat = 9, bold: Bool = false, color: UIColor = .label) {
                (value as NSString).draw(at: CGPoint(x: 38, y: y), withAttributes: [
                    .font: bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size),
                    .foregroundColor: color
                ])
                y += size + 6
            }
            text("PhaseXpert — Multi-case property sweep", size: 19, bold: true, color: .systemBlue)
            text("\(result.model.displayName) [\(result.model.id)] • \(result.definition.property.displayName)", size: 11, bold: true)
            text("\(result.definition.axis.rawValue.capitalized) \(number(result.definition.startValueSI)) to \(number(result.definition.endValueSI)) SI • \(result.definition.pointCount) points/case • \(result.definition.fixedMode.rawValue)")
            text(result.model == .advanced ? "Only independently validated property points are plotted; gaps are outside range or failures." : "General engineering calculations are plotted where successful; failures remain gaps.", color: .secondaryLabel)
            drawChart(result, rect: CGRect(x: 55, y: 360, width: 500, height: 270), context: context.cgContext)
            y = 650
            text("Case summaries", size: 12, bold: true)
            for series in result.series {
                let summary = series.summary(property: result.definition.property)
                text("\(series.input.name): min \(number(summary.minimumValue)), max \(number(summary.maximumValue)); \(summary.successfulCount)/\(series.points.count) successful, \(summary.validatedCount) validated, \(summary.outsideRangeCount) outside, \(summary.failedCount) failed", size: 8)
            }
            text("Model \(result.modelDescriptor?.modelVersion ?? "unavailable") • Provider \(result.modelDescriptor?.providerVersion ?? "unavailable") • Run \(result.id.uuidString)", size: 7, color: .secondaryLabel)
            text("Full point rows, exact compositions, statuses and provenance are retained in the companion CSV.", size: 7, color: .secondaryLabel)
        }
    }

    private func drawChart(_ result: MultiCasePropertySweepResult, rect: CGRect, context: CGContext) {
        let all = result.series.flatMap { series in series.points.compactMap { point -> (Double, Double)? in
            guard let value = point.value(for: result.definition.property), value.hasFiniteCalculatedValue,
                  let y = value.value else { return nil }
            return (result.definition.axis == .pressure ? point.pressurePa : point.temperatureK, y)
        }}
        guard let minX = all.map(\.0).min(), let maxX = all.map(\.0).max(),
              let minY = all.map(\.1).min(), let maxY = all.map(\.1).max() else { return }
        context.setStrokeColor(UIColor.secondaryLabel.cgColor)
        context.stroke(rect)
        let colors: [UIColor] = [.systemBlue, .systemOrange, .systemGreen, .systemPurple, .systemRed,
                                 .systemTeal, .systemPink, .systemIndigo, .systemBrown, .systemCyan]
        for (seriesIndex, series) in result.series.enumerated() {
            context.setStrokeColor(colors[seriesIndex % colors.count].cgColor)
            context.setLineWidth(1.5)
            var drawing = false
            for point in series.points {
                guard let value = point.value(for: result.definition.property), value.hasFiniteCalculatedValue,
                      let rawY = value.value else { drawing = false; continue }
                let rawX = result.definition.axis == .pressure ? point.pressurePa : point.temperatureK
                let x = rect.minX + CGFloat((rawX - minX) / max(maxX - minX, .leastNonzeroMagnitude)) * rect.width
                let y = rect.maxY - CGFloat((rawY - minY) / max(maxY - minY, .leastNonzeroMagnitude)) * rect.height
                if drawing { context.addLine(to: CGPoint(x: x, y: y)); context.strokePath(); context.move(to: CGPoint(x: x, y: y)) }
                else { context.move(to: CGPoint(x: x, y: y)); drawing = true }
            }
        }
    }
    private func number(_ value: Double?) -> String { value?.isFinite == true ? String(format: "%.7g", value!) : "—" }
}

struct MultiCasePropertySweepView: View {
    let cases: [BatchCaseInput]
    @Environment(AppNavigationState.self) private var navigationState
    @State private var controller: MultiCasePropertySweepController
    @State private var startText: String
    @State private var endText: String
    @State private var commonFixedText: String
    @State private var presentation = 0
    @State private var selectedX: Double?
    @State private var selectedPoint: SelectedSweepPoint?
    @State private var referenceCaseID: String?
    @State private var exportURLs: [URL] = []
    @State private var exportError: String?

    init(cases: [BatchCaseInput], initialModel: BatchCalculationModel) {
        let usable = Array(cases.prefix(10))
        let pressures = usable.compactMap(\.pressurePa)
        let operating = pressures.first ?? 5_000_000
        let start = max(100_000, (pressures.min() ?? operating) * 0.8)
        let end = max(start + 100_000, (pressures.max() ?? operating) * 1.2)
        let initialModel = BatchCalculationModel.general
        let properties = Self.availableProperties(cases: usable, model: initialModel)
        let definition = MultiCaseSweepDefinition(
            axis: .pressure, property: properties.contains(.density) ? .density : properties.first ?? .density,
            startValueSI: start, endValueSI: end, pointCount: 20,
            fixedMode: .preserveEachCase, commonFixedValueSI: usable.compactMap(\.temperatureK).first
        )
        self.cases = usable
        _controller = State(initialValue: MultiCasePropertySweepController(model: initialModel, definition: definition))
        _startText = State(initialValue: String(format: "%.7g", start / 100_000))
        _endText = State(initialValue: String(format: "%.7g", end / 100_000))
        _commonFixedText = State(initialValue: String(format: "%.7g", (definition.commonFixedValueSI ?? 293.15) - 273.15))
    }

    var body: some View {
        @Bindable var controller = controller
        Form {
            Section {
                ScientificStatusBanner(
                    title: "General engineering sweep",
                    message: "Every plotted point is a General Properties calculation. Independent validation is annotated where available; failures remain gaps."
                ).listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            Section("Sweep definition") {
                LabeledContent("Calculation model", value: "General Properties")
                    .accessibilityIdentifier("multi-sweep-model")
                Picker("Sweep variable", selection: axisBinding) {
                    Text("Pressure").tag(PropertySweepAxis.pressure)
                    Text("Temperature").tag(PropertySweepAxis.temperature)
                }.pickerStyle(.segmented).accessibilityIdentifier("multi-sweep-axis")
                Picker("Property", selection: propertyBinding) {
                    ForEach(properties, id: \.self) { Text($0.displayName).tag($0) }
                }.accessibilityIdentifier("multi-sweep-property")
                Picker("Non-swept condition", selection: fixedModeBinding) {
                    ForEach(MultiCaseFixedConditionMode.allCases) { Text($0.rawValue).tag($0) }
                }
                Text(controller.definition.fixedMode == .preserveEachCase
                     ? "Each case keeps its own stored \(controller.definition.axis == .pressure ? "temperature" : "pressure")."
                     : "Every case uses the explicitly entered common \(controller.definition.axis == .pressure ? "temperature" : "pressure").")
                    .font(.caption).foregroundStyle(.secondary)
                if controller.definition.fixedMode == .commonFixedValue {
                    LabeledContent(controller.definition.axis == .pressure ? "Common temperature" : "Common pressure") {
                        HStack { TextField("Fixed", text: $commonFixedText).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing); Text(fixedUnit) }
                    }
                }
                sweepTextRow("Start", text: $startText, unit: axisUnit)
                sweepTextRow("End", text: $endText, unit: axisUnit)
                Stepper("Points per case: \(controller.definition.pointCount)", value: pointCountBinding,
                        in: PropertySweepRequest.minimumPointCount...PropertySweepRequest.maximumPointCount)
                Text("\(cases.count) cases • \(cases.count * controller.definition.pointCount) total evaluations")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                if controller.isRunning {
                    ProgressView(value: Double(controller.completedPoints), total: Double(max(controller.totalPoints, 1)))
                    Text("\(controller.completedPoints) of \(controller.totalPoints) points")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Cancel sweep", role: .cancel) { controller.cancel() }
                } else {
                    Button("Run multi-case sweep", systemImage: "chart.xyaxis.line") { run() }
                        .disabled(cases.count < 2 || properties.isEmpty || parsedDefinition == nil)
                        .accessibilityIdentifier("run-multi-case-sweep")
                }
            }
            if let error = controller.errorMessage { Section("Sweep error") { Text(error).foregroundStyle(.red) } }
            if let result = controller.result {
                Section {
                    Picker("Presentation", selection: $presentation) {
                        Text("Chart").tag(0); Text("Data").tag(1)
                    }.pickerStyle(.segmented).accessibilityIdentifier("multi-sweep-presentation")
                    Picker("Delta reference", selection: $referenceCaseID) {
                        Text("None").tag(String?.none)
                        ForEach(result.series) { Text($0.input.name).tag(String?.some($0.id)) }
                    }
                }
                if presentation == 0 { chartSection(result) } else { dataSection(result) }
                summarySection(result)
                Section("Export") {
                    Button("Prepare CSV and PDF", systemImage: "doc.badge.arrow.up") { prepareExports(result) }
                        .accessibilityIdentifier("export-multi-case-sweep")
                    ForEach(exportURLs, id: \.self) { url in
                        ShareLink(item: url) { Label("Share \(url.pathExtension.uppercased())", systemImage: "square.and.arrow.up") }
                    }
                }
            }
        }
        .navigationTitle("Multi-case Sweep")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .ifeDottedBackground()
        .sheet(item: $selectedPoint) { SweepPointDetail(point: $0, result: controller.result!, navigationState: navigationState) }
        .alert("Unable to prepare exports", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(exportError ?? "") }
        .onDisappear { controller.cancel() }
    }

    private static func availableProperties(cases: [BatchCaseInput], model: BatchCalculationModel) -> [PropertyID] {
        let preferred: [PropertyID] = [.density, .dynamicViscosity, .compressibilityFactor, .molarMass,
            .specificVolume, .speedOfSound, .isobaricHeatCapacity, .isochoricHeatCapacity,
            .heatCapacityRatio, .thermalConductivity, .jouleThomsonCoefficient,
            .isothermalCompressibility, .thermalExpansionCoefficient]
        if model == .general {
            let supported = ProviderRegistry().provider(id: model.id)?.descriptor.supportedProperties ?? []
            return preferred.filter { supported.contains($0) }
        }
        let validated = cases.reduce(into: Set<PropertyID>()) { output, input in
            guard let pressure = input.pressurePa, let temperature = input.temperatureK else { return }
            output.formUnion(AdvancedValidationPresentation.validatedProperties(
                composition: input.composition, pressurePa: pressure, temperatureK: temperature
            ))
        }
        return preferred.filter { validated.contains($0) }
    }

    private var properties: [PropertyID] { Self.availableProperties(cases: cases, model: controller.model) }
    private var modelBinding: Binding<BatchCalculationModel> { Binding(get: { controller.model }, set: { model in
        controller.model = model
        let available = Self.availableProperties(cases: cases, model: model)
        guard !available.contains(controller.definition.property), let replacement = available.first else { return }
        var value = controller.definition
        value.property = replacement
        controller.definition = value
    }) }
    private var axisUnit: String { controller.definition.axis == .pressure ? "bar(a)" : "°C" }
    private var fixedUnit: String { controller.definition.axis == .pressure ? "°C" : "bar(a)" }
    private var parsedDefinition: MultiCaseSweepDefinition? {
        guard let start = Double(startText.replacingOccurrences(of: ",", with: ".")),
              let end = Double(endText.replacingOccurrences(of: ",", with: ".")), start < end else { return nil }
        var value = controller.definition
        value.startValueSI = value.axis == .pressure ? start * 100_000 : start + 273.15
        value.endValueSI = value.axis == .pressure ? end * 100_000 : end + 273.15
        if value.fixedMode == .commonFixedValue {
            guard let fixed = Double(commonFixedText.replacingOccurrences(of: ",", with: ".")) else { return nil }
            value.commonFixedValueSI = value.axis == .pressure ? fixed + 273.15 : fixed * 100_000
        }
        return value
    }

    private var axisBinding: Binding<PropertySweepAxis> { Binding(get: { controller.definition.axis }, set: { new in
        var value = controller.definition; value.axis = new
        let stored = new == .pressure ? cases.compactMap(\.pressurePa) : cases.compactMap(\.temperatureK)
        let center = stored.first ?? (new == .pressure ? 5_000_000 : 293.15)
        value.startValueSI = new == .pressure ? max(100_000, (stored.min() ?? center) * 0.8) : max(1, (stored.min() ?? center) - 30)
        value.endValueSI = new == .pressure ? (stored.max() ?? center) * 1.2 : (stored.max() ?? center) + 30
        value.commonFixedValueSI = new == .pressure ? cases.compactMap(\.temperatureK).first : cases.compactMap(\.pressurePa).first
        controller.definition = value
        startText = String(format: "%.7g", new == .pressure ? value.startValueSI / 100_000 : value.startValueSI - 273.15)
        endText = String(format: "%.7g", new == .pressure ? value.endValueSI / 100_000 : value.endValueSI - 273.15)
        commonFixedText = String(format: "%.7g", new == .pressure ? (value.commonFixedValueSI ?? 293.15) - 273.15 : (value.commonFixedValueSI ?? 5_000_000) / 100_000)
    }) }
    private var propertyBinding: Binding<PropertyID> { Binding(get: { controller.definition.property }, set: { var value = controller.definition; value.property = $0; controller.definition = value }) }
    private var fixedModeBinding: Binding<MultiCaseFixedConditionMode> { Binding(get: { controller.definition.fixedMode }, set: { var value = controller.definition; value.fixedMode = $0; controller.definition = value }) }
    private var pointCountBinding: Binding<Int> { Binding(get: { controller.definition.pointCount }, set: { var value = controller.definition; value.pointCount = $0; controller.definition = value }) }

    private func sweepTextRow(_ title: String, text: Binding<String>, unit: String) -> some View {
        LabeledContent(title) { HStack { TextField(title, text: text).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing); Text(unit).foregroundStyle(.secondary) } }
    }
    private func run() { guard let definition = parsedDefinition else { return }; controller.definition = definition; exportURLs = []; controller.start(cases: cases) }

    @ViewBuilder private func chartSection(_ result: MultiCasePropertySweepResult) -> some View {
        Section("Curves") {
            MultiCaseSweepChart(result: result, selectedX: $selectedX) { point in selectedPoint = point }
                .frame(minHeight: 360).accessibilityIdentifier("multi-case-sweep-chart")
        }
    }
    @ViewBuilder private func dataSection(_ result: MultiCasePropertySweepResult) -> some View {
        Section("Sweep data") {
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 16) {
                    GridRow { Text("Case").bold(); Text("P bar(a)").bold(); Text("T °C").bold(); Text(result.definition.property.displayName).bold(); Text("Phase").bold(); Text("Status").bold(); Text("Δ").bold() }
                    ForEach(result.series) { series in
                        ForEach(series.points) { point in
                            GridRow {
                                Button(series.input.name) { selectedPoint = .init(series: series, point: point) }.frame(width: 145, alignment: .leading)
                                Text(String(format: "%.6g", point.pressurePa / 100_000))
                                Text(String(format: "%.6g", point.temperatureK - 273.15))
                                Text(displayValue(point, property: result.definition.property))
                                Text(point.response?.phase.displayName ?? "—")
                                Text(point.state.rawValue)
                                Text(deltaText(result, series: series, point: point))
                            }
                        }
                    }
                }.fixedSize(horizontal: true, vertical: false)
            }.accessibilityIdentifier("multi-case-sweep-data")
        }
    }
    @ViewBuilder private func summarySection(_ result: MultiCasePropertySweepResult) -> some View {
        Section("Per-case summary") {
            ForEach(result.series) { series in
                let summary = series.summary(property: result.definition.property)
                VStack(alignment: .leading, spacing: 4) {
                    Text(series.input.name).font(.headline)
                    Text("Min \(summaryValue(summary.minimumValue, at: summary.minimumPoint, result: result)) • Max \(summaryValue(summary.maximumValue, at: summary.maximumPoint, result: result))")
                    Text("\(summary.successfulCount)/\(series.points.count) successful • \(summary.validatedCount) validated • \(summary.outsideRangeCount) outside • \(summary.failedCount) failed")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
    private func displayValue(_ point: MultiCaseSweepPoint, property: PropertyID) -> String {
        guard let raw = point.value(for: property), let value = EngineeringPropertyFormatter.measurement(for: raw) else { return "—" }
        return "\(String(format: "%.7g", value.value)) \(value.unit)"
    }
    private func deltaText(_ result: MultiCasePropertySweepResult, series: MultiCaseSweepSeries, point: MultiCaseSweepPoint) -> String {
        guard let referenceCaseID, let delta = result.delta(caseID: series.id, referenceCaseID: referenceCaseID, pointIndex: point.index) else { return "—" }
        return String(format: "%+.7g", delta)
    }
    private func summaryValue(_ value: Double?, at point: MultiCaseSweepPoint?, result: MultiCasePropertySweepResult) -> String {
        guard let value, let point else { return "—" }
        let coordinate = result.definition.axis == .pressure ? "\(String(format: "%.6g", point.pressurePa / 100_000)) bar(a)" : "\(String(format: "%.6g", point.temperatureK - 273.15)) °C"
        return "\(String(format: "%.7g", value)) at \(coordinate)"
    }
    private func prepareExports(_ result: MultiCasePropertySweepResult) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PhaseXpert-MultiSweep-\(result.id.uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let csv = directory.appendingPathComponent("PhaseXpert-MultiCase-Sweep.csv")
            let pdf = directory.appendingPathComponent("PhaseXpert-MultiCase-Sweep.pdf")
            try MultiCaseSweepCSVExporter().data(result).write(to: csv, options: .atomic)
            try MultiCaseSweepPDFExporter().data(result).write(to: pdf, options: .atomic)
            exportURLs = [csv, pdf]; exportError = nil
        } catch { exportURLs = []; exportError = error.localizedDescription }
    }
}

private struct SelectedSweepPoint: Identifiable {
    var id: UUID { point.id }
    let series: MultiCaseSweepSeries
    let point: MultiCaseSweepPoint
}

private struct MultiCaseSweepChart: View {
    let result: MultiCasePropertySweepResult
    @Binding var selectedX: Double?
    let inspect: (SelectedSweepPoint) -> Void
    private struct Plot: Identifiable { let id: UUID; let caseID: String; let caseName: String; let index: Int; let segment: Int; let x: Double; let y: Double }
    private var plots: [Plot] {
        result.series.flatMap { series in
            var segment = 0, previous = false
            let seriesPlots: [Plot] = series.points.compactMap { point -> Plot? in
                guard let raw = point.value(for: result.definition.property),
                      let value = EngineeringPropertyFormatter.measurement(for: raw) else { previous = false; return nil }
                if !previous { segment += 1 }; previous = true
                return Plot(id: point.id, caseID: series.id, caseName: series.input.name, index: point.index,
                            segment: segment, x: result.definition.axis == .pressure ? point.pressurePa / 100_000 : point.temperatureK - 273.15,
                            y: value.value)
            }
            return seriesPlots
        }
    }
    private var selectedPlots: [Plot] {
        guard let selectedX else { return [] }
        let nearestIndex = plots.min { abs($0.x - selectedX) < abs($1.x - selectedX) }?.index
        return plots.filter { $0.index == nearestIndex }
    }
    var body: some View {
        VStack(alignment: .leading) {
            Chart {
                ForEach(plots) { point in
                    LineMark(x: .value(axisLabel, point.x), y: .value(result.definition.property.displayName, point.y),
                             series: .value("Series", "\(point.caseID)-\(point.segment)"))
                        .foregroundStyle(by: .value("Case", point.caseName))
                        .symbol(by: .value("Case", point.caseName))
                    PointMark(x: .value(axisLabel, point.x), y: .value(result.definition.property.displayName, point.y))
                        .foregroundStyle(by: .value("Case", point.caseName)).symbol(by: .value("Case", point.caseName))
                }
                if let selectedX { RuleMark(x: .value("Selected", selectedX)).lineStyle(StrokeStyle(dash: [4, 4])) }
            }
            .chartXSelection(value: $selectedX)
            .chartXAxisLabel("\(axisLabel) (\(result.definition.axis == .pressure ? "bar(a)" : "°C"))")
            .chartYAxisLabel(result.definition.property.displayName)
            ForEach(selectedPlots) { plot in
                if let series = result.series.first(where: { $0.id == plot.caseID }),
                   let point = series.points.first(where: { $0.index == plot.index }) {
                    Button("\(plot.caseName): \(String(format: "%.7g", plot.y))") { inspect(.init(series: series, point: point)) }
                        .font(.caption).accessibilityLabel("Inspect \(plot.caseName) sweep point")
                }
            }
            Text(result.model == .advanced ? "Solid segments connect only adjacent validated points; gaps are observed outside-range or failed evaluations." : "Segments connect adjacent successful calculations; failures remain gaps.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var axisLabel: String { result.definition.axis == .pressure ? "Pressure" : "Temperature" }
}

private struct SweepPointDetail: View {
    let point: SelectedSweepPoint
    let result: MultiCasePropertySweepResult
    let navigationState: AppNavigationState
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("Sweep point") {
                    LabeledContent("Case", value: point.series.input.name)
                    LabeledContent("Provider", value: result.model.displayName)
                    LabeledContent("Pressure", value: "\(String(format: "%.7g", point.point.pressurePa / 100_000)) bar(a)")
                    LabeledContent("Temperature", value: "\(String(format: "%.7g", point.point.temperatureK - 273.15)) °C")
                    LabeledContent("Phase", value: point.point.response?.phase.displayName ?? "—")
                    LabeledContent("Status", value: point.point.state.rawValue)
                    LabeledContent(result.definition.property.displayName, value: pointValue)
                    if result.model == .advanced {
                        Text(point.point.validatedProperties.contains(result.definition.property)
                             ? "The selected property is independently validated at this evaluated point."
                             : "The selected property is outside its validated production range at this evaluated point.")
                    }
                    if let error = point.point.errorMessage { Text(error).foregroundStyle(.secondary) }
                }
                Section("Input provenance") { Text(point.series.input.fingerprint).font(.caption.monospaced()) }
                Section { Button("Open point in Calculator") { open() }.accessibilityIdentifier("open-sweep-point-calculator") }
            }
            .navigationTitle(point.series.input.name)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } } }
        }
    }
    private var pointValue: String {
        guard let raw = point.point.value(for: result.definition.property), let value = EngineeringPropertyFormatter.measurement(for: raw) else { return "—" }
        return "\(String(format: "%.8g", value.value)) \(value.unit)"
    }
    private func open() {
        let input = point.point.calculatorInput(from: point.series.input)
        navigationState.openBatchCaseInCalculator(input, model: result.model)
        dismiss()
    }
}
