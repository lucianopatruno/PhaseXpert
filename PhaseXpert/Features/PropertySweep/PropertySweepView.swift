import Charts
import Foundation
import Observation
import PhaseXpertCore
import SwiftUI

struct PropertySweepView: View {
    let record: CalculationRecord
    @State private var viewModel: PropertySweepViewModel

    init(record: CalculationRecord) {
        self.record = record
        _viewModel = State(initialValue: PropertySweepViewModel(record: record))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        Form {
            Section {
                ScientificStatusBanner(
                    title: "Preliminary provider-backed sweep",
                    message: "Every plotted point is a separate calculation by the recorded provider. Failed or unavailable points remain gaps; no scientific values are interpolated."
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section("Sweep definition") {
                Picker("Independent variable", selection: $viewModel.axis) {
                    Text("Pressure").tag(PropertySweepAxis.pressure)
                    Text("Temperature").tag(PropertySweepAxis.temperature)
                }
                .pickerStyle(.segmented)
                .onChange(of: viewModel.axis) { _, _ in viewModel.resetRange() }

                Picker("Property", selection: $viewModel.property) {
                    ForEach(viewModel.availableProperties, id: \.self) {
                        Text($0.displayName).tag($0)
                    }
                }

                LabeledContent("Fixed composition", value: viewModel.compositionText)
                LabeledContent(viewModel.fixedConditionLabel, value: viewModel.fixedConditionText)

                HStack {
                    Text("Start")
                    Spacer()
                    TextField("Start", text: $viewModel.startText)
                        .keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 110)
                    Text(viewModel.axisUnit)
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .leading)
                }
                HStack {
                    Text("End")
                    Spacer()
                    TextField("End", text: $viewModel.endText)
                        .keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 110)
                    Text(viewModel.axisUnit)
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .leading)
                }
                Stepper(
                    "Calculated points: \(viewModel.pointCount)",
                    value: $viewModel.pointCount,
                    in: PropertySweepRequest.minimumPointCount...PropertySweepRequest.maximumPointCount
                )
            }

            Section {
                if viewModel.isRunning {
                    ProgressView(value: viewModel.progress)
                    Text("\(viewModel.completedPoints) of \(viewModel.pointCount) points")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Cancel sweep", role: .cancel) {
                        viewModel.cancel()
                    }
                } else {
                    Button("Run property sweep", systemImage: "chart.xyaxis.line") {
                        viewModel.start()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.availableProperties.isEmpty)
                    .accessibilityIdentifier("run-property-sweep")
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Section("Sweep error") {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            if let result = viewModel.result {
                Section("Sweep result") {
                    LabeledContent("Calculated points", value: "\(result.successfulSampleCount)")
                    LabeledContent("Failed or unavailable", value: "\(result.failedSampleCount)")
                    LabeledContent(
                        "Duration",
                        value: "\(result.durationMilliseconds.formatted(.number.precision(.significantDigits(1...7)))) ms"
                    )

                    PropertySweepChart(
                        result: result,
                        property: viewModel.property,
                        axis: viewModel.axis
                    )
                    .frame(minHeight: 330)

                    if let exportURL = viewModel.exportURL {
                        ShareLink(item: exportURL) {
                            Label("Export sweep CSV", systemImage: "square.and.arrow.up")
                        }
                        .accessibilityIdentifier("export-property-sweep-csv")
                    }

                    DisclosureGroup("Failures and unavailable points") {
                        let failures = viewModel.failureRows
                        if failures.isEmpty {
                            Text("None")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(failures, id: \.id) { sample in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(viewModel.conditionText(for: sample))
                                        .font(.subheadline.weight(.semibold))
                                    Text(viewModel.failureText(for: sample))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    DisclosureGroup("Sweep traceability") {
                        LabeledContent("Sweep ID", value: result.id.uuidString)
                        LabeledContent("Model", value: record.response.model.name)
                        LabeledContent("Model version", value: record.response.model.modelVersion)
                        LabeledContent("Provider version", value: record.response.model.providerVersion)
                        LabeledContent("Source calculation", value: record.response.calculationID.uuidString)
                        LabeledContent("Execution", value: record.response.model.calculationMode.rawValue.capitalized)
                        Text("Each successful sample retains its complete calculation response, solver metadata, warnings, model descriptor and calculation identifier.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Property Sweep")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Color.ifeBackground)
        .onDisappear { viewModel.cancel() }
    }
}

@MainActor
@Observable
final class PropertySweepViewModel {
    let record: CalculationRecord
    let availableProperties: [PropertyID]

    var axis: PropertySweepAxis = .pressure
    var property: PropertyID
    var startText = ""
    var endText = ""
    var pointCount = 21
    var result: PropertySweepResult?
    var errorMessage: String?
    var isRunning = false
    var completedPoints = 0
    var exportURL: URL?

    private let provider: (any ThermodynamicModelProvider)?
    private var task: Task<Void, Never>?

    init(record: CalculationRecord, registry: ProviderRegistry = ProviderRegistry()) {
        self.record = record
        provider = registry.provider(id: record.response.model.id)
        let calculated = record.response.properties
            .filter { $0.hasFiniteCalculatedValue }
            .map(\.property)
        availableProperties = Array(Set(calculated))
            .sorted { $0.displayName < $1.displayName }
        property = availableProperties.contains(.density)
            ? .density
            : availableProperties.first ?? .density
        resetRange()
    }

    var progress: Double {
        guard pointCount > 0 else { return 0 }
        return Double(completedPoints) / Double(pointCount)
    }

    var axisUnit: String {
        axis == .pressure ? "bar(a)" : "°C"
    }

    var fixedConditionLabel: String {
        axis == .pressure ? "Fixed temperature" : "Fixed pressure"
    }

    var fixedConditionText: String {
        if axis == .pressure {
            return "\((record.input.temperatureK - 273.15).formatted(.number.precision(.significantDigits(1...7)))) °C"
        }
        return "\((record.input.pressurePa / 100_000).formatted(.number.precision(.significantDigits(1...7)))) bar(a)"
    }

    var compositionText: String {
        record.request.composition
            .filter { $0.moleFraction > 0 }
            .map {
                "\($0.component.symbol) \(($0.moleFraction * 100).formatted(.number.precision(.significantDigits(1...6)))) mol%"
            }
            .joined(separator: ", ")
    }

    var failureRows: [PropertySweepSample] {
        guard let result else { return [] }
        return result.samples.filter {
            $0.value(for: result.request.property)?.hasFiniteCalculatedValue != true
        }
    }

    func resetRange() {
        let domain = record.response.model.domain
        if axis == .pressure {
            let operating = record.input.pressurePa / 100_000
            let lower = max(domain.minimumPressurePa / 100_000, operating - 50)
            let upper = min(domain.maximumPressurePa / 100_000, operating + 50)
            startText = number(lower)
            endText = number(max(upper, lower + 1))
        } else {
            let operating = record.input.temperatureK - 273.15
            let lower = max(domain.minimumTemperatureK - 273.15, operating - 30)
            let upper = min(domain.maximumTemperatureK - 273.15, operating + 30)
            startText = number(lower)
            endText = number(max(upper, lower + 1))
        }
        result = nil
        exportURL = nil
        errorMessage = nil
    }

    func start() {
        cancel()
        result = nil
        exportURL = nil
        errorMessage = nil
        completedPoints = 0
        isRunning = true

        task = Task { [weak self] in
            guard let self else { return }
            await self.perform()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        if isRunning {
            isRunning = false
            errorMessage = "The property sweep was cancelled."
        }
    }

    func conditionText(for sample: PropertySweepSample) -> String {
        if axis == .pressure {
            return "\(number(sample.pressurePa / 100_000)) bar(a)"
        }
        return "\(number(sample.temperatureK - 273.15)) °C"
    }

    func failureText(for sample: PropertySweepSample) -> String {
        if let errorMessage = sample.errorMessage {
            return errorMessage
        }
        return sample.value(for: property)?.message
            ?? sample.value(for: property)?.status.displayName
            ?? "The provider returned no value."
    }

    private func perform() async {
        guard let provider else {
            errorMessage = "The recorded provider is not available in this build."
            isRunning = false
            return
        }
        guard let start = parse(startText), let end = parse(endText) else {
            errorMessage = "Enter finite numeric sweep limits."
            isRunning = false
            return
        }

        let request = PropertySweepRequest(
            baseRequest: record.request,
            axis: axis,
            startValueSI: axis == .pressure ? start * 100_000 : start + 273.15,
            endValueSI: axis == .pressure ? end * 100_000 : end + 273.15,
            pointCount: pointCount,
            property: property
        )

        do {
            let completed = try await PropertySweepRunner(provider: provider).run(
                request
            ) { [weak self] completed, _ in
                self?.completedPoints = completed
            }
            try Task.checkCancellation()
            result = completed
            exportURL = try PropertySweepCSVExporter().writeTemporaryCSV(
                result: completed,
                record: record
            )
            isRunning = false
            task = nil
        } catch is CancellationError {
            isRunning = false
            task = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? String(describing: error)
            isRunning = false
            task = nil
        }
    }

    private func parse(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    private func number(_ value: Double) -> String {
        value.formatted(.number.locale(Locale(identifier: "en_US_POSIX"))
            .precision(.significantDigits(1...7)))
    }
}

private struct PropertySweepChart: View {
    struct PlotSample: Identifiable {
        let id: UUID
        let x: Double
        let y: Double
        let phase: PhaseRegion
        let segment: Int
    }

    let result: PropertySweepResult
    let property: PropertyID
    let axis: PropertySweepAxis
    @State private var selectedX: Double?

    private var samples: [PlotSample] {
        var segment = 0
        var previousSucceeded = false
        return result.samples.compactMap { sample in
            guard let raw = sample.value(for: property),
                  let measurement = EngineeringPropertyFormatter.measurement(for: raw)
            else {
                previousSucceeded = false
                return nil
            }
            if !previousSucceeded { segment += 1 }
            previousSucceeded = true
            return PlotSample(
                id: sample.id,
                x: axis == .pressure
                    ? sample.pressurePa / 100_000
                    : sample.temperatureK - 273.15,
                y: measurement.value,
                phase: sample.response?.phase ?? .unknown,
                segment: segment
            )
        }
    }

    private var selectedSample: PlotSample? {
        guard let selectedX else { return nil }
        return samples.min { abs($0.x - selectedX) < abs($1.x - selectedX) }
    }

    private var yUnit: String {
        guard let first = result.samples.compactMap({ $0.value(for: property) }).first,
              let measurement = EngineeringPropertyFormatter.measurement(for: first)
        else { return "" }
        return measurement.unit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: IFESpacing.small) {
            Text("\(property.displayName) vs \(axis == .pressure ? "pressure" : "temperature")")
                .font(.headline)

            Chart {
                ForEach(samples) { sample in
                    LineMark(
                        x: .value(axisLabel, sample.x),
                        y: .value(property.displayName, sample.y),
                        series: .value("Continuous calculated segment", sample.segment)
                    )
                    .foregroundStyle(Color.ifePrimary)
                    .interpolationMethod(.linear)

                    PointMark(
                        x: .value(axisLabel, sample.x),
                        y: .value(property.displayName, sample.y)
                    )
                    .foregroundStyle(sample.phase == .twoPhase ? Color.ifeSignal : Color.ifePrimary)
                }

                if let selectedSample {
                    RuleMark(x: .value("Selected", selectedSample.x))
                        .foregroundStyle(Color.secondary)
                        .lineStyle(StrokeStyle(dash: [4, 4]))
                }
            }
            .chartXSelection(value: $selectedX)
            .chartXAxisLabel("\(axisLabel) (\(axis == .pressure ? "bar(a)" : "°C"))")
            .chartYAxisLabel("\(property.displayName)\(yUnit.isEmpty ? "" : " (\(yUnit))")")
            .accessibilityLabel("Provider-calculated \(property.displayName) sweep")

            if let selectedSample {
                LabeledContent(
                    "Selected point",
                    value: "\(selectedSample.x.formatted(.number.precision(.significantDigits(1...7)))) \(axis == .pressure ? "bar(a)" : "°C")"
                )
                LabeledContent(
                    property.displayName,
                    value: "\(selectedSample.y.formatted(.number.precision(.significantDigits(1...7)))) \(yUnit)"
                )
                LabeledContent("Provider phase", value: selectedSample.phase.displayName)
            }

            Text("Straight segments connect adjacent successful provider calculations for visualization only. Gaps represent failed or unavailable points.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var axisLabel: String {
        axis == .pressure ? "Pressure" : "Temperature"
    }
}

private struct PropertySweepCSVExporter {
    func writeTemporaryCSV(
        result: PropertySweepResult,
        record: CalculationRecord
    ) throws -> URL {
        var rows = [
            ["PhaseXpert property sweep"],
            ["sweep_id", result.id.uuidString],
            ["generated_at", ISO8601DateFormatter().string(from: result.generatedAt)],
            ["source_calculation_id", record.response.calculationID.uuidString],
            ["model_id", record.response.model.id],
            ["model_name", record.response.model.name],
            ["model_version", record.response.model.modelVersion],
            ["provider_version", record.response.model.providerVersion],
            ["axis", result.request.axis.rawValue],
            ["property", result.request.property.rawValue],
            ["composition", record.request.composition.map {
                "\($0.component.rawValue):\($0.moleFraction)"
            }.joined(separator: ";")],
            [],
            [
                "index", "pressure_bar_a", "temperature_c", "phase",
                "property_status", "display_value", "display_unit",
                "raw_si_value", "raw_si_unit", "calculation_id",
                "solver_duration_ms", "warnings_or_error"
            ]
        ]

        for sample in result.samples {
            let property = sample.value(for: result.request.property)
            let display = property.flatMap(EngineeringPropertyFormatter.measurement)
            rows.append([
                String(sample.index),
                String(sample.pressurePa / 100_000),
                String(sample.temperatureK - 273.15),
                sample.response?.phase.rawValue ?? "",
                property?.status.rawValue ?? "failed",
                display.map { String($0.value) } ?? "",
                display?.unit ?? "",
                property?.value.map { String($0) } ?? "",
                property?.unit ?? "",
                sample.response?.calculationID.uuidString ?? "",
                sample.response.map { String($0.solver.durationMilliseconds) } ?? "",
                sample.errorMessage
                    ?? property?.message
                    ?? sample.response?.warnings.joined(separator: " | ")
                    ?? ""
            ])
        }

        let csv = rows.map { $0.map(escape).joined(separator: ",") }
            .joined(separator: "\r\n")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhaseXpert-Sweep-\(result.id.uuidString).csv")
        guard let data = csv.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        try data.write(to: url, options: .atomic)
        return url
    }

    private func escape(_ value: String) -> String {
        let quote = "\u{0022}"
        let escaped = value.replacingOccurrences(of: quote, with: quote + quote)
        return quote + escaped + quote
    }
}
