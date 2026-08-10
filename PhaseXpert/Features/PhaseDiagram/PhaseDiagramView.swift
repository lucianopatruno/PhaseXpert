import Charts
import Observation
import PhaseXpertCore
import SwiftUI

@MainActor
@Observable
final class PhaseDiagramViewModel {
    private(set) var response: PhaseEnvelopeResponse?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var scopeMessage: String?

    private let registry: ProviderRegistry
    private let timeoutNanoseconds: UInt64
    private var loadingRecordID: UUID?
    private var calculationTask: Task<PhaseEnvelopeResponse, Error>?
    private var monitorTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    init(
        registry: ProviderRegistry = ProviderRegistry(),
        timeoutNanoseconds: UInt64 = 30_000_000_000
    ) {
        self.registry = registry
        self.timeoutNanoseconds = timeoutNanoseconds
    }

    func load(for record: CalculationRecord?) {
        guard let record else {
            cancelLoading()
            loadingRecordID = nil
            response = nil
            errorMessage = nil
            scopeMessage = nil
            isLoading = false
            return
        }
        guard loadingRecordID != record.id else { return }

        cancelLoading()
        loadingRecordID = record.id
        response = nil
        errorMessage = nil
        scopeMessage = nil
        isLoading = false

        switch PhaseDiagramEligibility.evaluate(composition: record.request.composition) {
        case .pureCarbonDioxide:
            break
        case .multicomponent:
            scopeMessage = PhaseDiagramEligibility.pureCarbonDioxideScopeMessage
            return
        case .invalidComposition:
            errorMessage = "The CO₂ phase diagram cannot be shown for this calculation."
            return
        }

        isLoading = true

        guard let provider = registry.provider(id: record.request.modelID) else {
            isLoading = false
            errorMessage = "The CO₂ phase diagram cannot be shown for this calculation."
            return
        }

        let recordID = record.id
        let request = PhaseEnvelopeRequest(
            modelID: record.request.modelID,
            composition: record.request.composition
        )
        let calculation = Task.detached(priority: .userInitiated) {
            try await provider.phaseEnvelope(request)
        }
        calculationTask = calculation

        monitorTask = Task { [weak self] in
            do {
                let envelope = try await calculation.value
                guard !Task.isCancelled, let self,
                      self.loadingRecordID == recordID else { return }
                self.timeoutTask?.cancel()
                self.response = envelope
                self.errorMessage = nil
                self.isLoading = false
            } catch is CancellationError {
                // A replacement record owns the visible state.
            } catch {
                guard !Task.isCancelled, let self,
                      self.loadingRecordID == recordID else { return }
                self.timeoutTask?.cancel()
                self.errorMessage = self.userMessage(for: error)
                self.isLoading = false
            }
        }

        let timeoutNanoseconds = self.timeoutNanoseconds
        timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled, let self,
                  self.loadingRecordID == recordID,
                  self.response == nil else { return }
            self.isLoading = false
            self.errorMessage = "The CO₂ phase diagram is taking longer than expected. It will appear automatically if the calculation completes."
        }
    }

    private func cancelLoading() {
        monitorTask?.cancel()
        timeoutTask?.cancel()
        calculationTask?.cancel()
        monitorTask = nil
        timeoutTask = nil
        calculationTask = nil
    }

    private func userMessage(for error: Error) -> String {
        guard let providerError = error as? ProviderError else {
            return "The CO₂ phase diagram cannot be shown for this calculation."
        }
        return switch providerError {
        case .modelUnavailable,
             .invalidRequest,
             .malformedResponse,
             .unsupportedComponent:
            "The CO₂ phase diagram cannot be shown for this calculation."
        case .timeout:
            "The CO₂ phase diagram is taking longer than expected."
        case .cancelled:
            "The CO₂ phase diagram request was cancelled."
        }
    }
}

struct PhaseDiagramView: View {
    @Environment(AppNavigationState.self) private var navigationState
    @State private var viewModel = PhaseDiagramViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if let record = navigationState.latestCalculationRecord {
                    diagramContent(for: record)
                } else {
                    ContentUnavailableView(
                        "No operating point",
                        systemImage: "chart.xyaxis.line",
                        description: Text(
                            "Run a calculation, then open its phase diagram. No estimated curve is displayed."
                        )
                    )
                    .accessibilityIdentifier("phase-diagram-no-calculation")
                }
            }
            .background(Color.ifeBackground.ignoresSafeArea())
            .navigationTitle("Phase Diagram")
            .task(id: navigationState.latestCalculationRecord?.id) {
                viewModel.load(for: navigationState.latestCalculationRecord)
            }
        }
    }

    @ViewBuilder
    private func diagramContent(for record: CalculationRecord) -> some View {
        if let scopeMessage = viewModel.scopeMessage {
            ContentUnavailableView {
                Label(PhaseDiagramEligibility.title, systemImage: "chart.xyaxis.line")
            } description: {
                VStack(spacing: IFESpacing.small) {
                    Text(scopeMessage)
                    Text(PhaseDiagramEligibility.mixturePropertySupportMessage)
                }
            }
            .accessibilityIdentifier("phase-diagram-pure-co2-scope")
        } else if viewModel.isLoading {
            VStack(spacing: IFESpacing.medium) {
                ProgressView()
                Text("Calculating CO₂ phase diagram…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("phase-diagram-loading")
        } else if let error = viewModel.errorMessage {
            ContentUnavailableView(
                PhaseDiagramEligibility.title,
                systemImage: "exclamationmark.triangle",
                description: Text(error)
            )
            .accessibilityIdentifier("phase-diagram-error")
        } else if let response = viewModel.response, response.isAvailable {
            PhaseBoundaryChart(record: record, response: response)
        } else {
            ContentUnavailableView(
                PhaseDiagramEligibility.title,
                systemImage: "chart.xyaxis.line",
                description: Text(
                    viewModel.response?.warnings.joined(separator: " ")
                        ?? "Run a pure CO₂ calculation to view the CO₂ phase diagram."
                )
            )
            .accessibilityIdentifier("phase-diagram-empty")
        }
    }
}

private struct PhaseBoundaryChart: View {
    struct Sample: Identifiable {
        let id: Int
        let temperatureCelsius: Double
        let pressureBar: Double
        let branch: PhaseEnvelopePoint.Branch
    }

    let record: CalculationRecord
    let response: PhaseEnvelopeResponse

    @State private var selectedTemperatureCelsius: Double?
    @State private var exportArtifacts: PhaseDiagramExportArtifacts?
    @State private var exportErrorMessage: String?
    @State private var isPreparingExport = false

    private var samples: [Sample] {
        response.points.enumerated().compactMap { index, point in
            guard point.temperatureK.isFinite,
                  point.pressurePa.isFinite,
                  point.pressurePa > 0
            else { return nil }
            return Sample(
                id: index,
                temperatureCelsius: point.temperatureK - 273.15,
                pressureBar: point.pressurePa / 100_000,
                branch: point.branch
            )
        }
    }

    private var bubble: [Sample] { samples.filter { $0.branch == .bubble } }
    private var critical: Sample? {
        guard let point = response.points.first(where: { $0.branch == .critical }) else {
            return nil
        }
        return Sample(
            id: response.points.count,
            temperatureCelsius: point.temperatureK - 273.15,
            pressureBar: point.pressurePa / 100_000,
            branch: .critical
        )
    }

    private var operatingTemperatureCelsius: Double {
        record.input.temperatureK - 273.15
    }

    private var operatingPressureBar: Double {
        record.input.pressurePa / 100_000
    }

    private var xDomain: ClosedRange<Double> {
        paddedDomain(values: samples.map(\.temperatureCelsius) + [
            critical?.temperatureCelsius,
            operatingTemperatureCelsius
        ].compactMap { $0 })
    }

    private var yDomain: ClosedRange<Double> {
        paddedDomain(values: samples.map(\.pressureBar) + [
            critical?.pressureBar,
            operatingPressureBar
        ].compactMap { $0 })
    }

    private var selectedSample: Sample? {
        guard let selectedTemperatureCelsius else { return nil }
        return samples.filter { $0.branch != .critical }.min {
            abs($0.temperatureCelsius - selectedTemperatureCelsius)
                < abs($1.temperatureCelsius - selectedTemperatureCelsius)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: IFESpacing.medium) {
                ScientificStatusBanner(
                    title: "Preliminary pure CO₂ boundary",
                    message: "Calculated saturation values are preliminary and validation pending."
                )

                IFECard {
                    if let exportArtifacts {
                        ForEach(exportArtifacts.files, id: \.self) { fileURL in
                            ShareLink(item: fileURL) {
                                Label(
                                    fileURL.pathExtension.lowercased() == "pdf"
                                        ? "Share PDF report"
                                        : "Share CSV data",
                                    systemImage: fileURL.pathExtension.lowercased() == "pdf"
                                        ? "doc.richtext"
                                        : "tablecells"
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .accessibilityIdentifier("share-phase-diagram-artifacts")
                    } else if isPreparingExport {
                        HStack {
                            ProgressView()
                            Text("Preparing diagram export…")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: IFESpacing.small) {
                            if let exportErrorMessage {
                                Label(
                                    exportErrorMessage,
                                    systemImage: "exclamationmark.triangle"
                                )
                                .foregroundStyle(.secondary)
                            }
                            Button("Prepare PDF and CSV", systemImage: "doc.badge.arrow.up") {
                                prepareDiagramExport()
                            }
                            .accessibilityIdentifier("prepare-phase-diagram-export")
                        }
                    }
                }

                IFECard {
                    VStack(alignment: .leading, spacing: IFESpacing.small) {
                        Text("Pure CO₂ saturation model")
                            .font(.headline)
                        LabeledContent(
                            "Operating pressure",
                            value: "\(number(operatingPressureBar)) bar(a)"
                        )
                        LabeledContent(
                            "Operating temperature",
                            value: "\(number(operatingTemperatureCelsius)) °C"
                        )
                        LabeledContent("Calculated phase", value: record.response.phase.displayName)
                        Text(
                            "A pure-fluid saturation boundary is a line, not an enclosed two-phase envelope. The operating phase shown above comes from the source calculation."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                IFECard {
                    VStack(alignment: .leading, spacing: IFESpacing.small) {
                        Text("Pressure–temperature diagram")
                            .font(.headline)
                        Text("Pure CO₂ saturation boundary with operating point")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Chart {
                            ForEach(bubble) { sample in
                                LineMark(
                                    x: .value("Temperature (°C)", sample.temperatureCelsius),
                                    y: .value("Pressure (bar(a))", sample.pressureBar)
                                )
                                .foregroundStyle(by: .value(
                                    "Series",
                                    "CO₂ saturation boundary"
                                ))
                                .interpolationMethod(.linear)
                            }

                            if let critical {
                                PointMark(
                                    x: .value("Temperature (°C)", critical.temperatureCelsius),
                                    y: .value("Pressure (bar(a))", critical.pressureBar)
                                )
                                .symbolSize(70)
                                .foregroundStyle(by: .value("Series", "Critical point"))
                            }

                            PointMark(
                                x: .value("Temperature (°C)", operatingTemperatureCelsius),
                                y: .value("Pressure (bar(a))", operatingPressureBar)
                            )
                            .symbolSize(90)
                            .foregroundStyle(by: .value("Series", "Operating point"))

                            if let selectedSample {
                                RuleMark(x: .value(
                                    "Selected temperature",
                                    selectedSample.temperatureCelsius
                                ))
                                .foregroundStyle(Color.secondary.opacity(0.5))
                                .lineStyle(StrokeStyle(dash: [4, 4]))
                            }
                        }
                        .chartForegroundStyleScale([
                            "CO₂ saturation boundary": Color.pxChartBoundary,
                            "Critical point": Color.pxChartCritical,
                            "Operating point": Color.pxChartOperatingPoint
                        ])
                        .chartXScale(domain: xDomain)
                        .chartYScale(domain: yDomain)
                        .chartXSelection(value: $selectedTemperatureCelsius)
                        .chartXAxisLabel("Temperature (°C)")
                        .chartYAxisLabel("Pressure (bar(a))")
                        .frame(minHeight: 360)
                        .accessibilityIdentifier("phase-boundary-chart")
                        .accessibilityLabel(
                            "Pure carbon dioxide saturation boundary with critical point and operating point"
                        )

                        if let selectedSample {
                            Divider()
                            LabeledContent(
                                "Selected boundary temperature",
                                value: "\(number(selectedSample.temperatureCelsius)) °C"
                            )
                            LabeledContent(
                                "Selected saturation pressure",
                                value: "\(number(selectedSample.pressureBar)) bar(a)"
                            )
                            Button("Reset view", systemImage: "arrow.counterclockwise") {
                                selectedTemperatureCelsius = nil
                            }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("reset-phase-diagram-view")
                        }
                    }
                }

                Text(
                    "Straight line segments connect adjacent calculated points for display only. No scientific values are interpolated or estimated."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, IFESpacing.small)

                IFECard {
                    IFEExpandableRow("Phase-boundary traceability") {
                        LabeledContent(
                            "Boundary type",
                            value: "Pure-fluid saturation"
                        )
                        LabeledContent("Calculated points", value: "\(response.points.count)")
                        LabeledContent("Composition") {
                            Text(record.request.composition.map {
                                "\($0.component.symbol) \(number($0.moleFraction * 100)) mol%"
                            }.joined(separator: ", "))
                            .multilineTextAlignment(.trailing)
                        }
                        if let model = response.model {
                            LabeledContent("Model", value: "Pure CO₂ saturation")
                            LabeledContent("Model version", value: model.modelVersion)
                            LabeledContent("Implementation version", value: model.providerVersion)
                        }
                        if let generatedAt = response.generatedAt {
                            LabeledContent("Generated at") {
                                Text(generatedAt.formatted(
                                    .dateTime.year().month().day().hour().minute().second()
                                ))
                            }
                        }
                        if let solver = response.solver {
                            LabeledContent("Method", value: "Pure CO₂ saturation calculation")
                            LabeledContent(
                                "Converged",
                                value: solver.converged ? "Yes" : "No"
                            )
                            LabeledContent(
                                "Duration",
                                value: "\(number(solver.durationMilliseconds)) ms"
                            )
                        }
                    }
                }
            }
            .padding(IFESpacing.medium)
        }
        .accessibilityIdentifier("phase-diagram-available")
    }

    private func prepareDiagramExport() {
        guard !isPreparingExport else { return }
        isPreparingExport = true
        exportErrorMessage = nil

        Task { @MainActor in
            await Task.yield()
            do {
                exportArtifacts = try PhaseDiagramImageExporter().writeTemporaryReportFiles(
                    for: record,
                    response: response
                )
            } catch {
                exportArtifacts = nil
                exportErrorMessage = error.localizedDescription
            }
            isPreparingExport = false
        }
    }

    private func paddedDomain(values: [Double]) -> ClosedRange<Double> {
        let finite = values.filter(\.isFinite)
        guard let minimum = finite.min(), let maximum = finite.max() else { return 0...1 }
        let span = max(maximum - minimum, 1)
        let padding = span * 0.08
        return (minimum - padding)...(maximum + padding)
    }

    private func number(_ value: Double) -> String {
        value.formatted(.number.precision(.significantDigits(1...7)))
    }
}
