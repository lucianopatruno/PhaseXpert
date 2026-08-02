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
            isLoading = false
            return
        }
        guard loadingRecordID != record.id else { return }

        cancelLoading()
        loadingRecordID = record.id
        response = nil
        errorMessage = nil
        isLoading = true

        guard let provider = registry.provider(id: record.request.modelID) else {
            isLoading = false
            errorMessage = "The model used by this calculation is not installed."
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
            self.errorMessage = "CoolProp did not finish the phase-boundary calculation within 30 seconds. The provider calculation continues in the background; the diagram will appear automatically if it completes."
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
            return "The phase-boundary calculation failed unexpectedly."
        }
        return switch providerError {
        case let .modelUnavailable(message),
             let .invalidRequest(message),
             let .malformedResponse(message):
            message
        case let .unsupportedComponent(component):
            "\(component.symbol) is not supported by the selected phase model."
        case .timeout:
            "The phase-boundary calculation timed out."
        case .cancelled:
            "The phase-boundary calculation was cancelled."
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
        if viewModel.isLoading {
            VStack(spacing: IFESpacing.medium) {
                ProgressView()
                Text("Calculating provider phase boundary…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("phase-diagram-loading")
        } else if let error = viewModel.errorMessage {
            ContentUnavailableView(
                "Phase diagram failed",
                systemImage: "exclamationmark.triangle",
                description: Text(error)
            )
            .accessibilityIdentifier("phase-diagram-error")
        } else if let response = viewModel.response, response.isAvailable {
            PhaseBoundaryChart(record: record, response: response)
        } else {
            ContentUnavailableView(
                "Phase diagram unavailable",
                systemImage: "chart.xyaxis.line",
                description: Text(
                    viewModel.response?.warnings.joined(separator: " ")
                        ?? "The selected provider did not return a real phase boundary."
                )
            )
            .accessibilityIdentifier("phase-diagram-unavailable")
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
    @State private var exportedDiagramURL: URL?
    @State private var exportErrorMessage: String?
    @State private var xVisibleLength: Double = 1
    @State private var yVisibleLength: Double = 1
    @State private var xScrollPosition: Double = 0
    @State private var yScrollPosition: Double = 0

    private var samples: [Sample] {
        response.points.enumerated().map { index, point in
            Sample(
                id: index,
                temperatureCelsius: point.temperatureK - 273.15,
                pressureBar: point.pressurePa / 100_000,
                branch: point.branch
            )
        }
    }

    private var bubble: [Sample] { samples.filter { $0.branch == .bubble } }
    private var dew: [Sample] { samples.filter { $0.branch == .dew } }

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
                    title: response.boundaryKind == .mixtureEnvelope
                        ? (response.solver?.converged == false
                            ? "Preliminary mixture phase-boundary trace"
                            : "Preliminary mixture phase envelope")
                        : "Preliminary pure CO₂ boundary",
                    message: response.warnings.joined(separator: " ")
                )

                IFECard {
                    if let exportedDiagramURL {
                        ShareLink(
                            item: exportedDiagramURL,
                            preview: SharePreview(
                                "PhaseXpert phase diagram",
                                image: Image(systemName: "photo")
                            )
                        ) {
                            Label("Share diagram image", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .accessibilityIdentifier("share-phase-diagram-image")
                    } else if let exportErrorMessage {
                        Label(exportErrorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    } else {
                        HStack {
                            ProgressView()
                            Text("Preparing diagram image…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                IFECard {
                    VStack(alignment: .leading, spacing: IFESpacing.small) {
                        Text(record.response.model.name)
                            .font(.headline)
                        LabeledContent(
                            "Operating pressure",
                            value: "\(number(operatingPressureBar)) bar(a)"
                        )
                        LabeledContent(
                            "Operating temperature",
                            value: "\(number(operatingTemperatureCelsius)) °C"
                        )
                        LabeledContent("Provider phase", value: record.response.phase.displayName)
                        Text(
                            response.boundaryKind == .mixtureEnvelope
                                ? "Bubble and dew branches are provider-calculated for the recorded composition. The operating phase shown above comes from the source calculation."
                                : "A pure-fluid saturation boundary is a line, not an enclosed two-phase envelope. The operating phase shown above comes from the provider calculation."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                IFECard {
                    VStack(alignment: .leading, spacing: IFESpacing.small) {
                        HStack {
                            Text("Pressure–temperature diagram")
                                .font(.headline)
                            Spacer()
                            viewportControls
                        }

                        Chart {
                            ForEach(bubble) { sample in
                                LineMark(
                                    x: .value("Temperature (°C)", sample.temperatureCelsius),
                                    y: .value("Pressure (bar(a))", sample.pressureBar)
                                )
                                .foregroundStyle(by: .value(
                                    "Series",
                                    response.boundaryKind == .mixtureEnvelope
                                        ? "Bubble branch"
                                        : "CO₂ saturation boundary"
                                ))
                                .interpolationMethod(.linear)
                            }

                            ForEach(dew) { sample in
                                LineMark(
                                    x: .value("Temperature (°C)", sample.temperatureCelsius),
                                    y: .value("Pressure (bar(a))", sample.pressureBar)
                                )
                                .foregroundStyle(by: .value("Series", "Dew branch"))
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
                            "CO₂ saturation boundary": Color.ifePrimary,
                            "Bubble branch": Color.ifePrimary,
                            "Dew branch": Color.ifeSignal,
                            "Critical point": Color.ifeSignal,
                            "Operating point": Color.ifeText
                        ])
                        .chartXScale(domain: xDomain)
                        .chartYScale(domain: yDomain)
                        .chartScrollableAxes([.horizontal, .vertical])
                        .chartXVisibleDomain(length: xVisibleLength)
                        .chartYVisibleDomain(length: yVisibleLength)
                        .chartScrollPosition(x: $xScrollPosition)
                        .chartScrollPosition(y: $yScrollPosition)
                        .chartXSelection(value: $selectedTemperatureCelsius)
                        .chartXAxisLabel("Temperature (°C)")
                        .chartYAxisLabel("Pressure (bar(a))")
                        .frame(minHeight: 360)
                        .accessibilityLabel(
                            response.boundaryKind == .mixtureEnvelope
                                ? "Carbon dioxide mixture bubble and dew phase envelope with operating point"
                                : "Pure carbon dioxide saturation boundary with critical point and operating point"
                        )

                        if let selectedSample {
                            Divider()
                            LabeledContent(
                                "Selected boundary temperature",
                                value: "\(number(selectedSample.temperatureCelsius)) °C"
                            )
                            LabeledContent(
                                selectedSample.branch == .dew
                                    ? "Selected dew pressure"
                                    : "Selected bubble pressure",
                                value: "\(number(selectedSample.pressureBar)) bar(a)"
                            )
                        }
                    }
                }

                Text(
                    "Straight line segments connect adjacent provider-calculated points within each branch for display only. No scientific values are interpolated or estimated."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, IFESpacing.small)

                IFECard {
                    IFEExpandableRow("Phase-boundary traceability") {
                        LabeledContent(
                            "Boundary type",
                            value: response.boundaryKind == .pureFluidSaturation
                                ? "Pure-fluid saturation"
                                : (response.solver?.converged == false
                                    ? "Open provider bubble/dew trace"
                                    : "Mixture bubble/dew envelope")
                        )
                        LabeledContent("Calculated points", value: "\(response.points.count)")
                        LabeledContent("Composition") {
                            Text(record.request.composition.map {
                                "\($0.component.symbol) \(number($0.moleFraction * 100)) mol%"
                            }.joined(separator: ", "))
                            .multilineTextAlignment(.trailing)
                        }
                        if let model = response.model {
                            LabeledContent("Model", value: model.name)
                            LabeledContent("Model version", value: model.modelVersion)
                            LabeledContent("Provider version", value: model.providerVersion)
                        }
                        if let generatedAt = response.generatedAt {
                            LabeledContent("Generated at") {
                                Text(generatedAt.formatted(
                                    .dateTime.year().month().day().hour().minute().second()
                                ))
                            }
                        }
                        if let solver = response.solver {
                            LabeledContent("Method", value: solver.method)
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
        .onAppear(perform: resetViewport)
        .task(id: response.requestID) {
            do {
                exportedDiagramURL = try PhaseDiagramImageExporter().writeTemporaryPNG(
                    for: record,
                    response: response
                )
                exportErrorMessage = nil
            } catch {
                exportedDiagramURL = nil
                exportErrorMessage = error.localizedDescription
            }
        }
        .onChange(of: response.requestID) { _, _ in resetViewport() }
        .accessibilityIdentifier("phase-diagram-available")
    }

    private var viewportControls: some View {
        HStack(spacing: 4) {
            Button("Zoom in", systemImage: "plus.magnifyingglass") {
                xVisibleLength = max(xVisibleLength * 0.75, (xDomain.upperBound - xDomain.lowerBound) * 0.1)
                yVisibleLength = max(yVisibleLength * 0.75, (yDomain.upperBound - yDomain.lowerBound) * 0.1)
            }
            .labelStyle(.iconOnly)

            Button("Zoom out", systemImage: "minus.magnifyingglass") {
                xVisibleLength = min(xVisibleLength / 0.75, xDomain.upperBound - xDomain.lowerBound)
                yVisibleLength = min(yVisibleLength / 0.75, yDomain.upperBound - yDomain.lowerBound)
            }
            .labelStyle(.iconOnly)

            Button("Reset chart", systemImage: "arrow.counterclockwise") {
                resetViewport()
            }
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.bordered)
    }

    private func resetViewport() {
        xVisibleLength = xDomain.upperBound - xDomain.lowerBound
        yVisibleLength = yDomain.upperBound - yDomain.lowerBound
        xScrollPosition = xDomain.lowerBound
        yScrollPosition = yDomain.lowerBound
        selectedTemperatureCelsius = nil
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
