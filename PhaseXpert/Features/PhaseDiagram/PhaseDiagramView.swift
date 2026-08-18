import Charts
import Observation
import PhaseXpertCore
import SwiftUI
import UIKit

@MainActor
@Observable
final class PhaseDiagramViewModel {
    private(set) var response: PhaseEnvelopeResponse?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var scopeMessage: String?
    private(set) var phaseMapRecord: CalculationRecord?
    private(set) var phaseMapResult: PhaseMapResult?
    private(set) var phaseMapIssues: [PhaseMapValidationIssue] = []
    private(set) var phaseMapProgress = PhaseMapProgress(completedCount: 0, totalCount: 0)
    private(set) var isPhaseMapLoading = false
    private(set) var isPhaseMapResultStale = false
    private(set) var phaseMapStatusMessage = "Run a multicomponent calculation to create a Phase Map."
    var phaseMapResolution: PhaseMapResolution = .five {
        didSet { phaseMapInputsChanged() }
    }
    var pressureMinimumText = "" {
        didSet { phaseMapInputsChanged() }
    }
    var pressureMaximumText = "" {
        didSet { phaseMapInputsChanged() }
    }
    var temperatureMinimumText = "" {
        didSet { phaseMapInputsChanged() }
    }
    var temperatureMaximumText = "" {
        didSet { phaseMapInputsChanged() }
    }
    var phaseMapPressureUnit: PressureDisplayUnit = .barAbsolute
    var phaseMapTemperatureUnit: TemperatureDisplayUnit = .celsius

    private let registry: ProviderRegistry
    private let timeoutNanoseconds: UInt64
    private var loadingRecordID: UUID?
    private var calculationTask: Task<PhaseEnvelopeResponse, Error>?
    private var monitorTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var phaseMapTask: Task<Void, Never>?
    private var phaseMapRunID: UUID?

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
            resetPhaseMap()
            return
        }
        guard loadingRecordID != record.id else { return }

        cancelLoading()
        cancelPhaseMapCalculation()
        loadingRecordID = record.id
        response = nil
        errorMessage = nil
        scopeMessage = nil
        isLoading = false
        resetPhaseMap(keepingRecord: false)

        switch PhaseDiagramEligibility.evaluate(composition: record.request.composition) {
        case .pureCarbonDioxide:
            break
        case .multicomponent:
            if record.request.modelID == "teqp-pure-co2-experimental" {
                break
            }
            configurePhaseMap(for: record)
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

    func calculatePhaseMap() {
        cancelPhaseMapCalculation()
        guard let record = phaseMapRecord else { return }
        guard let provider = registry.provider(id: record.request.modelID) else {
            phaseMapIssues = [
                PhaseMapValidationIssue(
                    code: .providerUnavailable,
                    message: "The selected provider is not available for Phase Map calculation."
                )
            ]
            phaseMapStatusMessage = "Review blocking validation issues before calculating."
            return
        }
        guard let request = phaseMapRequest(for: record) else {
            phaseMapStatusMessage = "Review blocking validation issues before calculating."
            return
        }
        let issues = PhaseMapGridBuilder.validationIssues(for: request)
        phaseMapIssues = issues
        guard issues.isEmpty else {
            phaseMapStatusMessage = "Review blocking validation issues before calculating."
            return
        }

        let runID = UUID()
        phaseMapRunID = runID
        let evaluationCount = (try? PhaseMapGridBuilder.points(for: request).count)
            ?? request.resolution.gridPointCount
        phaseMapProgress = PhaseMapProgress(
            completedCount: 0,
            totalCount: evaluationCount
        )
        phaseMapStatusMessage = "Calculating Phase Map…"
        isPhaseMapLoading = true
        isPhaseMapResultStale = false
        let runner = PhaseMapRunner(provider: provider)
        phaseMapTask = Task { [weak self] in
            do {
                let result = try await runner.run(request) { progress in
                    await MainActor.run {
                        guard self?.phaseMapRunID == runID else { return }
                        self?.phaseMapProgress = progress
                    }
                }
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self?.phaseMapRunID == runID else { return }
                    self?.phaseMapResult = result
                    self?.phaseMapStatusMessage = "Phase Map complete: \(result.classifiedCount) classified, \(result.unknownCount) unknown, \(result.failedCount) failed, \(result.nonConvergedCount) non-converged."
                    self?.isPhaseMapLoading = false
                    self?.isPhaseMapResultStale = false
                }
            } catch is CancellationError {
                await MainActor.run {
                    guard self?.phaseMapRunID == runID else { return }
                    self?.isPhaseMapLoading = false
                    self?.phaseMapStatusMessage = "Phase Map calculation cancelled."
                }
            } catch {
                await MainActor.run {
                    guard self?.phaseMapRunID == runID else { return }
                    self?.isPhaseMapLoading = false
                    self?.phaseMapStatusMessage = self?.userMessage(for: error)
                        ?? "Phase Map calculation failed."
                }
            }
        }
    }

    func cancelPhaseMapCalculation() {
        phaseMapTask?.cancel()
        phaseMapTask = nil
        phaseMapRunID = nil
        isPhaseMapLoading = false
    }

    func changePhaseMapPressureUnit(to newUnit: PressureDisplayUnit) {
        guard newUnit != phaseMapPressureUnit else { return }
        guard
            let minimum = parseDouble(pressureMinimumText),
            let maximum = parseDouble(pressureMaximumText)
        else {
            phaseMapIssues = [
                PhaseMapValidationIssue(
                    code: .invalidPressureRange,
                    message: "Pressure unit was not changed because the range values could not be parsed."
                )
            ]
            return
        }
        let minPa = phaseMapPressureUnit.pascal(from: minimum)
        let maxPa = phaseMapPressureUnit.pascal(from: maximum)
        phaseMapPressureUnit = newUnit
        pressureMinimumText = formatted(newUnit.displayValue(from: minPa))
        pressureMaximumText = formatted(newUnit.displayValue(from: maxPa))
        phaseMapInputsChanged()
    }

    func changePhaseMapTemperatureUnit(to newUnit: TemperatureDisplayUnit) {
        guard newUnit != phaseMapTemperatureUnit else { return }
        guard
            let minimum = parseDouble(temperatureMinimumText),
            let maximum = parseDouble(temperatureMaximumText)
        else {
            phaseMapIssues = [
                PhaseMapValidationIssue(
                    code: .invalidTemperatureRange,
                    message: "Temperature unit was not changed because the range values could not be parsed."
                )
            ]
            return
        }
        let minK = phaseMapTemperatureUnit.kelvin(from: minimum)
        let maxK = phaseMapTemperatureUnit.kelvin(from: maximum)
        phaseMapTemperatureUnit = newUnit
        temperatureMinimumText = formatted(newUnit.displayValue(from: minK))
        temperatureMaximumText = formatted(newUnit.displayValue(from: maxK))
        phaseMapInputsChanged()
    }

    var canCalculatePhaseMap: Bool {
        phaseMapRecord != nil && !isPhaseMapLoading && phaseMapRequest(for: phaseMapRecord!) != nil
    }

    private func configurePhaseMap(for record: CalculationRecord) {
        phaseMapRecord = record
        let automaticRange = PhaseMapRange.automatic(
            pressurePa: record.request.pressurePa,
            temperatureK: record.request.temperatureK
        )
        phaseMapPressureUnit = .barAbsolute
        phaseMapTemperatureUnit = .celsius
        pressureMinimumText = formatted(phaseMapPressureUnit.displayValue(from: automaticRange.pressureMinimumPa))
        pressureMaximumText = formatted(phaseMapPressureUnit.displayValue(from: automaticRange.pressureMaximumPa))
        temperatureMinimumText = formatted(phaseMapTemperatureUnit.displayValue(from: automaticRange.temperatureMinimumK))
        temperatureMaximumText = formatted(phaseMapTemperatureUnit.displayValue(from: automaticRange.temperatureMaximumK))
        phaseMapResolution = .five
        phaseMapResult = nil
        phaseMapIssues = []
        phaseMapProgress = PhaseMapProgress(completedCount: 0, totalCount: phaseMapResolution.gridPointCount)
        phaseMapStatusMessage = "Ready to classify 25 discrete flash points."
        isPhaseMapResultStale = false
    }

    private func phaseMapInputsChanged() {
        guard phaseMapRecord != nil else { return }
        if isPhaseMapLoading {
            cancelPhaseMapCalculation()
            phaseMapStatusMessage = "Inputs changed. Phase Map calculation was cancelled."
        } else if phaseMapResult != nil {
            isPhaseMapResultStale = true
            phaseMapStatusMessage = "Inputs changed. Calculate Phase Map again to refresh results."
        }
        validatePhaseMapInputs()
    }

    private func validatePhaseMapInputs() {
        guard let record = phaseMapRecord else { return }
        guard let request = phaseMapRequest(for: record) else { return }
        phaseMapIssues = PhaseMapGridBuilder.validationIssues(for: request)
    }

    private func phaseMapRequest(for record: CalculationRecord) -> PhaseMapRequest? {
        guard
            let pressureMinimum = parseDouble(pressureMinimumText),
            let pressureMaximum = parseDouble(pressureMaximumText),
            let temperatureMinimum = parseDouble(temperatureMinimumText),
            let temperatureMaximum = parseDouble(temperatureMaximumText)
        else {
            phaseMapIssues = [
                PhaseMapValidationIssue(
                    code: .invalidPressureRange,
                    message: "Pressure and temperature ranges must contain numeric values."
                )
            ]
            return nil
        }
        return PhaseMapRequest(
            modelID: record.request.modelID,
            pressurePa: record.request.pressurePa,
            temperatureK: record.request.temperatureK,
            composition: record.request.composition,
            range: PhaseMapRange(
                pressureMinimumPa: phaseMapPressureUnit.pascal(from: pressureMinimum),
                pressureMaximumPa: phaseMapPressureUnit.pascal(from: pressureMaximum),
                temperatureMinimumK: phaseMapTemperatureUnit.kelvin(from: temperatureMinimum),
                temperatureMaximumK: phaseMapTemperatureUnit.kelvin(from: temperatureMaximum)
            ),
            resolution: phaseMapResolution,
            clientVersion: record.request.clientVersion
        )
    }

    private func resetPhaseMap(keepingRecord: Bool = false) {
        if !keepingRecord {
            phaseMapRecord = nil
        }
        phaseMapResult = nil
        phaseMapIssues = []
        phaseMapProgress = PhaseMapProgress(completedCount: 0, totalCount: 0)
        phaseMapStatusMessage = "Run a multicomponent calculation to create a Phase Map."
        isPhaseMapLoading = false
        isPhaseMapResultStale = false
    }

    private func parseDouble(_ text: String) -> Double? {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        if let number = formatter.number(from: text) {
            return number.doubleValue
        }
        return Double(text.replacingOccurrences(of: ",", with: "."))
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.significantDigits(1...7)))
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
        VStack(spacing: 0) {
            if let guidance = phaseDiagramGuidance(for: record) {
                IFECard {
                    VStack(alignment: .leading, spacing: IFESpacing.small) {
                        Text("Phase diagram limits")
                            .font(.headline)
                        ForEach(guidance) { line in
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(line.title)
                                        .font(.subheadline.weight(.semibold))
                                    Text(line.detail)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(
                                    systemName: line.severity == .unsupported
                                        ? "xmark.octagon.fill"
                                        : "checkmark.circle.fill"
                                )
                                .foregroundStyle(
                                    line.severity == .unsupported
                                        ? Color.pxError
                                        : Color.pxSuccess
                                )
                            }
                        }
                    }
                }
                .padding([.horizontal, .top], IFESpacing.medium)
                .accessibilityIdentifier("phase-diagram-limits")
            }

            Group {
                if viewModel.phaseMapRecord != nil {
                    PhaseMapContent(record: record, viewModel: viewModel)
                } else if let scopeMessage = viewModel.scopeMessage {
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
    }

    private func phaseDiagramGuidance(
        for record: CalculationRecord
    ) -> [OperatingGuidanceLine]? {
        guard
            record.request.modelID == "teqp-pure-co2-experimental",
            let provider = ProviderRegistry().provider(id: record.request.modelID)
        else {
            return nil
        }
        let guidance = provider.operatingRangeGuidance(
            for: OperatingGuidanceContext(
                pressurePa: record.request.pressurePa,
                temperatureK: record.request.temperatureK,
                composition: record.request.composition,
                requestedProperties: record.request.requestedProperties
            )
        )
        guard let lines = guidance?.phaseDiagram, !lines.isEmpty else { return nil }
        return lines
    }
}

private struct PhaseMapContent: View {
    let record: CalculationRecord
    let viewModel: PhaseDiagramViewModel

    @State private var selectedPointID: String?

    private var result: PhaseMapResult? {
        viewModel.phaseMapResult
    }

    private var selectedEvaluation: PhaseMapEvaluation? {
        guard let selectedPointID, let result else {
            return result?.operatingPoint ?? result?.evaluations.first
        }
        return result.evaluations.first { $0.id == selectedPointID }
            ?? result.operatingPoint
            ?? result.evaluations.first
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        ScrollView {
            VStack(alignment: .leading, spacing: IFESpacing.medium) {
                ScientificStatusBanner(
                    title: "Preliminary multicomponent Phase Map",
                    message: "Classifies discrete provider flash points. This is not a thermodynamic phase envelope, does not trace bubble or dew boundaries, and narrow phase regions can be missed."
                )

                IFECard {
                    VStack(alignment: .leading, spacing: IFESpacing.small) {
                        Text("Phase Map")
                            .font(.title2.bold())
                        Text("Multicomponent composition at user-selected pressure and temperature ranges.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        LabeledContent("Operating pressure", value: "\(number(record.request.pressurePa / 100_000)) bar(a)")
                        LabeledContent("Operating temperature", value: "\(number(record.request.temperatureK - 273.15)) °C")
                        LabeledContent("Composition") {
                            Text(compositionSummary(record.request.composition))
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }

                IFECard {
                    VStack(alignment: .leading, spacing: IFESpacing.regular) {
                        Text("Grid setup")
                            .font(.headline)

                        Picker("Resolution", selection: $viewModel.phaseMapResolution) {
                            ForEach(PhaseMapResolution.allCases) { resolution in
                                Text("\(resolution.rawValue)×\(resolution.rawValue)")
                                    .tag(resolution)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("phase-map-resolution-picker")

                        PhaseMapRangeEditor(
                            title: "Pressure range",
                            minimumText: $viewModel.pressureMinimumText,
                            maximumText: $viewModel.pressureMaximumText,
                            unitLabel: viewModel.phaseMapPressureUnit.rawValue,
                            unitMenu: {
                                ForEach(PressureDisplayUnit.allCases) { unit in
                                    Button(unit.rawValue) {
                                        viewModel.changePhaseMapPressureUnit(to: unit)
                                    }
                                }
                            }
                        )

                        PhaseMapRangeEditor(
                            title: "Temperature range",
                            minimumText: $viewModel.temperatureMinimumText,
                            maximumText: $viewModel.temperatureMaximumText,
                            unitLabel: viewModel.phaseMapTemperatureUnit.rawValue,
                            unitMenu: {
                                ForEach(TemperatureDisplayUnit.allCases) { unit in
                                    Button(unit.rawValue) {
                                        viewModel.changePhaseMapTemperatureUnit(to: unit)
                                    }
                                }
                            }
                        )

                        Text("The 5×5 grid includes the operating point as the central point. Even grids evaluate the operating point separately.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    viewModel.calculatePhaseMap()
                } label: {
                    Label("Calculate Phase Map", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canCalculatePhaseMap)
                .controlSize(.large)
                .accessibilityIdentifier("calculate-phase-map")

                PhaseMapStatusSection(viewModel: viewModel)

                if let result {
                    PhaseMapResultsSection(
                        result: result,
                        pressureUnit: viewModel.phaseMapPressureUnit,
                        temperatureUnit: viewModel.phaseMapTemperatureUnit,
                        selectedPointID: $selectedPointID,
                        selectedEvaluation: selectedEvaluation,
                        isStale: viewModel.isPhaseMapResultStale
                    )
                }
            }
            .padding(IFESpacing.medium)
        }
        .accessibilityIdentifier("phase-map-available")
        .onDisappear {
            viewModel.cancelPhaseMapCalculation()
        }
    }

    private func compositionSummary(_ composition: [MixtureComponent]) -> String {
        composition
            .filter { $0.moleFraction > 0 }
            .map { "\($0.component.symbol) \(number($0.moleFraction * 100)) mol%" }
            .joined(separator: ", ")
    }
}

private struct PhaseMapRangeEditor<UnitMenu: View>: View {
    let title: String
    @Binding var minimumText: String
    @Binding var maximumText: String
    let unitLabel: String
    @ViewBuilder let unitMenu: () -> UnitMenu

    var body: some View {
        VStack(alignment: .leading, spacing: IFESpacing.small) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Menu(unitLabel) {
                    unitMenu()
                }
                .accessibilityIdentifier("\(title)-unit-menu")
            }
            VStack(spacing: IFESpacing.small) {
                TextField("Minimum", text: $minimumText)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("\(title)-minimum")
                TextField("Maximum", text: $maximumText)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("\(title)-maximum")
            }
        }
    }
}

private struct PhaseMapStatusSection: View {
    let viewModel: PhaseDiagramViewModel

    var body: some View {
        IFECard {
            VStack(alignment: .leading, spacing: IFESpacing.small) {
                if viewModel.isPhaseMapLoading {
                    ProgressView(
                        value: Double(viewModel.phaseMapProgress.completedCount),
                        total: Double(max(viewModel.phaseMapProgress.totalCount, 1))
                    )
                    Text("\(viewModel.phaseMapProgress.completedCount) of \(viewModel.phaseMapProgress.totalCount) flash points evaluated")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(viewModel.phaseMapStatusMessage)
                    .font(.subheadline)
                if viewModel.isPhaseMapResultStale {
                    Label("Displayed Phase Map is stale after input changes.", systemImage: "clock.badge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(Color.pxWarning)
                        .accessibilityIdentifier("phase-map-stale")
                }
                ForEach(viewModel.phaseMapIssues) { issue in
                    Label(issue.message, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Color.pxError)
                }
            }
        }
        .accessibilityIdentifier("phase-map-status")
    }
}

private struct PhaseMapResultsSection: View {
    let result: PhaseMapResult
    let pressureUnit: PressureDisplayUnit
    let temperatureUnit: TemperatureDisplayUnit
    @Binding var selectedPointID: String?
    let selectedEvaluation: PhaseMapEvaluation?
    let isStale: Bool

    private var xDomain: ClosedRange<Double> {
        paddedDomain(values: result.evaluations.map { temperatureUnit.displayValue(from: $0.point.temperatureK) })
    }

    private var yDomain: ClosedRange<Double> {
        paddedDomain(values: result.evaluations.map { pressureUnit.displayValue(from: $0.point.pressurePa) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: IFESpacing.medium) {
            IFECard {
                VStack(alignment: .leading, spacing: IFESpacing.small) {
                    Text("Completion summary")
                        .font(.headline)
                    LabeledContent("Resolution", value: "\(result.request.resolution.rawValue)×\(result.request.resolution.rawValue)")
                    LabeledContent("Evaluations", value: "\(result.evaluations.count)")
                    LabeledContent("Classified", value: "\(result.classifiedCount)")
                    LabeledContent("Unknown", value: "\(result.unknownCount)")
                    LabeledContent("Failed", value: "\(result.failedCount)")
                    LabeledContent("Non-converged", value: "\(result.nonConvergedCount)")
                }
            }

            IFECard {
                VStack(alignment: .leading, spacing: IFESpacing.small) {
                    Text("Pressure-temperature classification")
                        .font(.headline)
                    Text("Markers use both color and shape; gray points are unknown, failed, non-converged or unsupported.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Chart {
                        ForEach(result.evaluations) { evaluation in
                            PointMark(
                                x: .value(
                                    "Temperature (\(temperatureUnit.rawValue))",
                                    temperatureUnit.displayValue(from: evaluation.point.temperatureK)
                                ),
                                y: .value(
                                    "Pressure (\(pressureUnit.rawValue))",
                                    pressureUnit.displayValue(from: evaluation.point.pressurePa)
                                )
                            )
                            .foregroundStyle(PhaseMapMarkerStyle.style(for: evaluation).color)
                            .symbol(PhaseMapMarkerStyle.style(for: evaluation).chartSymbol)
                            .symbolSize(evaluation.point.isOperatingPoint ? 110 : 70)
                            .accessibilityLabel(PhaseMapMarkerStyle.style(for: evaluation).accessibilityDescription)
                        }
                        if let operatingPoint = result.operatingPoint {
                            PointMark(
                                x: .value(
                                    "Temperature (\(temperatureUnit.rawValue))",
                                    temperatureUnit.displayValue(from: operatingPoint.point.temperatureK)
                                ),
                                y: .value(
                                    "Pressure (\(pressureUnit.rawValue))",
                                    pressureUnit.displayValue(from: operatingPoint.point.pressurePa)
                                )
                            )
                            .foregroundStyle(Color.red)
                            .symbolSize(220)
                            .symbol {
                                Circle()
                                    .stroke(Color.red, lineWidth: 2.5)
                                    .frame(width: 20, height: 20)
                            }
                        }
                    }
                    .chartXScale(domain: xDomain)
                    .chartYScale(domain: yDomain)
                    .chartXAxisLabel("Temperature (\(temperatureUnit.rawValue))")
                    .chartYAxisLabel("Pressure (\(pressureUnit.rawValue))")
                    .frame(minHeight: 360)
                    .accessibilityIdentifier("phase-map-chart")
                    .accessibilityLabel("Multicomponent Phase Map with operating point highlighted by a red ring")

                    PhaseMapLegend()

                    Picker("Point", selection: Binding(
                        get: { selectedPointID ?? result.operatingPoint?.id ?? result.evaluations.first?.id },
                        set: { selectedPointID = $0 }
                    )) {
                        ForEach(result.evaluations) { evaluation in
                            Text(pointLabel(evaluation))
                                .tag(Optional(evaluation.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("phase-map-point-picker")

                    if let selectedEvaluation {
                        Divider()
                        PhaseMapPointExplanation(
                            evaluation: selectedEvaluation,
                            pressureUnit: pressureUnit,
                            temperatureUnit: temperatureUnit
                        )
                    }
                }
            }

            IFECard {
                IFEExpandableRow("Phase Map assumptions and traceability") {
                    VStack(alignment: .leading, spacing: IFESpacing.small) {
                        ForEach(result.warnings, id: \.self) { warning in
                            Text(warning)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("Provider metadata does not declare solid, dense or supercritical classification support. Those markers appear only when the active provider explicitly returns the corresponding classification.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        LabeledContent("Request ID", value: result.request.requestID.uuidString)
                        LabeledContent("Model", value: result.model.name)
                        LabeledContent("Provider version", value: result.model.providerVersion)
                        LabeledContent("Pressure range") {
                            Text("\(number(pressureUnit.displayValue(from: result.request.range.pressureMinimumPa))) to \(number(pressureUnit.displayValue(from: result.request.range.pressureMaximumPa))) \(pressureUnit.rawValue)")
                                .multilineTextAlignment(.trailing)
                        }
                        LabeledContent("Temperature range") {
                            Text("\(number(temperatureUnit.displayValue(from: result.request.range.temperatureMinimumK))) to \(number(temperatureUnit.displayValue(from: result.request.range.temperatureMaximumK))) \(temperatureUnit.rawValue)")
                                .multilineTextAlignment(.trailing)
                        }
                        LabeledContent("Calculated at") {
                            Text(result.calculatedAt.formatted(.dateTime.year().month().day().hour().minute().second()))
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }
        }
        .opacity(isStale ? 0.72 : 1)
        .accessibilityIdentifier("phase-map-results")
    }

    private func pointLabel(_ evaluation: PhaseMapEvaluation) -> String {
        let prefix = evaluation.point.isOperatingPoint ? "Operating point" : evaluation.classification.displayName
        return "\(prefix): \(number(temperatureUnit.displayValue(from: evaluation.point.temperatureK))) \(temperatureUnit.rawValue), \(number(pressureUnit.displayValue(from: evaluation.point.pressurePa))) \(pressureUnit.rawValue)"
    }

    private func paddedDomain(values: [Double]) -> ClosedRange<Double> {
        let finite = values.filter(\.isFinite)
        guard let minimum = finite.min(), let maximum = finite.max() else { return 0...1 }
        let span = max(maximum - minimum, 1)
        let padding = span * 0.08
        return (minimum - padding)...(maximum + padding)
    }
}

private struct PhaseMapLegend: View {
    private let items: [(String, PhaseMapMarkerStyle)] = [
        ("Solid", .style(for: .solid)),
        ("Gas", .style(for: .gas)),
        ("Liquid", .style(for: .liquid)),
        ("Multiphase", .style(for: .multiphase)),
        ("Dense", .style(for: .dense)),
        ("Supercritical", .style(for: .supercritical)),
        ("Unknown", .unknown),
        ("Failed/non-converged/unsupported", .failed)
    ]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], alignment: .leading) {
            ForEach(items, id: \.0) { item in
                Label {
                    Text(item.0)
                } icon: {
                    Image(systemName: item.1.systemImage)
                        .foregroundStyle(item.1.color)
                }
                .font(.caption)
                .accessibilityLabel(item.1.accessibilityDescription)
            }
        }
        .accessibilityIdentifier("phase-map-legend")
    }
}

private struct PhaseMapPointExplanation: View {
    let evaluation: PhaseMapEvaluation
    let pressureUnit: PressureDisplayUnit
    let temperatureUnit: TemperatureDisplayUnit

    var body: some View {
        VStack(alignment: .leading, spacing: IFESpacing.small) {
            Text(evaluation.point.isOperatingPoint ? "Operating-point flash" : "Selected flash point")
                .font(.subheadline.weight(.semibold))
            LabeledContent("Classification", value: evaluation.classification.displayName)
            LabeledContent("Pressure", value: "\(number(pressureUnit.displayValue(from: evaluation.point.pressurePa))) \(pressureUnit.rawValue)")
            LabeledContent("Temperature", value: "\(number(temperatureUnit.displayValue(from: evaluation.point.temperatureK))) \(temperatureUnit.rawValue)")
            if let failureReason = evaluation.failureReason ?? evaluation.classification.detail {
                Label(failureReason, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Color.pxUnavailable)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct PhaseMapMarkerStyle {
    let chartSymbol: BasicChartSymbolShape
    let systemImage: String
    let color: Color
    let accessibilityDescription: String

    static let failed = PhaseMapMarkerStyle(
        chartSymbol: .circle,
        systemImage: "circle.fill",
        color: .pxUnavailable,
        accessibilityDescription: "Solid gray circle for failed, non-converged or unsupported flash points"
    )

    static let unknown = PhaseMapMarkerStyle(
        chartSymbol: .diamond,
        systemImage: "questionmark.diamond",
        color: .pxUnavailable,
        accessibilityDescription: "Gray diamond for unknown flash points"
    )

    static func style(for evaluation: PhaseMapEvaluation) -> PhaseMapMarkerStyle {
        if evaluation.classification.classification == .unknown {
            return unknown
        }
        if evaluation.failureReason != nil || !evaluation.classification.isSupported {
            return failed
        }
        return style(for: evaluation.classification.classification)
    }

    static func style(for classification: PhaseMapClassification) -> PhaseMapMarkerStyle {
        switch classification {
        case .solid:
            PhaseMapMarkerStyle(
                chartSymbol: .cross,
                systemImage: "xmark",
                color: .pxSuccess,
                accessibilityDescription: "Green cross for Solid"
            )
        case .gas:
            PhaseMapMarkerStyle(
                chartSymbol: .circle,
                systemImage: "circle.fill",
                color: .blue,
                accessibilityDescription: "Blue circle for Gas"
            )
        case .liquid:
            PhaseMapMarkerStyle(
                chartSymbol: .square,
                systemImage: "square.fill",
                color: .cyan,
                accessibilityDescription: "Cyan square for Liquid"
            )
        case .multiphase:
            PhaseMapMarkerStyle(
                chartSymbol: .plus,
                systemImage: "plus",
                color: .pink,
                accessibilityDescription: "Pink plus for Multiphase"
            )
        case .dense:
            PhaseMapMarkerStyle(
                chartSymbol: .diamond,
                systemImage: "diamond.fill",
                color: .orange,
                accessibilityDescription: "Orange diamond for Dense"
            )
        case .supercritical:
            PhaseMapMarkerStyle(
                chartSymbol: .triangle,
                systemImage: "triangle.fill",
                color: .purple,
                accessibilityDescription: "Purple triangle for Supercritical"
            )
        case .unknown:
            unknown
        case .failed:
            failed
        }
    }
}

struct PhaseMapOperatingPointRenderingPlan: Equatable {
    let drawsUnderlyingClassificationMarker: Bool
    let drawsRedRingOverlay: Bool
    let ringDrawsAfterClassificationMarker: Bool

    static let standard = PhaseMapOperatingPointRenderingPlan(
        drawsUnderlyingClassificationMarker: true,
        drawsRedRingOverlay: true,
        ringDrawsAfterClassificationMarker: true
    )
}

private func number(_ value: Double) -> String {
    value.formatted(.number.precision(.significantDigits(1...7)))
}

private struct PhaseBoundaryChart: View {
    let record: CalculationRecord
    let response: PhaseEnvelopeResponse

    @State private var selectedTemperatureCelsius: Double?
    @State private var exportErrorMessage: String?
    @State private var isPreparingExport = false
    @State private var exportLifecycle = PhaseDiagramExportLifecycle()
    @State private var showsShareSheet = false

    private var plotData: PhaseBoundaryPlotData {
        PhaseBoundarySeriesBuilder.plotData(for: response)
    }

    private var operatingTemperatureCelsius: Double {
        record.input.temperatureK - 273.15
    }

    private var operatingPressureBar: Double {
        record.input.pressurePa / 100_000
    }

    private var xDomain: ClosedRange<Double> {
        paddedDomain(values: plottedPoints.map(\.temperatureCelsius) + [
            operatingTemperatureCelsius
        ])
    }

    private var yDomain: ClosedRange<Double> {
        paddedDomain(values: plottedPoints.map(\.pressureBar) + [
            operatingPressureBar
        ])
    }

    private var plottedPoints: [PhaseBoundaryPlotPoint] {
        plotData.segments.flatMap(\.points) + plotData.criticalPoints
    }

    private var selectedSample: PhaseBoundaryPlotPoint? {
        guard let selectedTemperatureCelsius else { return nil }
        return plotData.segments.flatMap(\.points).min {
            abs($0.temperatureCelsius - selectedTemperatureCelsius)
                < abs($1.temperatureCelsius - selectedTemperatureCelsius)
        }
    }

    private var isMixtureEnvelope: Bool {
        response.boundaryKind == .mixtureEnvelope
    }

    private var bannerTitle: String {
        isMixtureEnvelope ? "Validated methane phase envelope" : "Preliminary pure CO₂ boundary"
    }

    private var bannerMessage: String {
        isMixtureEnvelope
            ? "EOS-CG-2021 bubble/dew curve inside the experimentally validated Petropoulou VLE temperature bounds."
            : "Calculated saturation values are preliminary and validation pending."
    }

    private var modelTitle: String {
        isMixtureEnvelope ? "CO₂+CH₄ phase-envelope model" : "Pure CO₂ saturation model"
    }

    private var chartSubtitle: String {
        isMixtureEnvelope
            ? "CO₂+CH₄ bubble and dew branches with operating point"
            : "Pure CO₂ saturation boundary with operating point"
    }

    private var boundaryNote: String {
        isMixtureEnvelope
            ? "Bubble and dew branches enclose the validated two-phase interval for the fixed composition. The operating phase shown above comes from the source calculation."
            : "A pure-fluid saturation boundary is a line, not an enclosed two-phase envelope. The operating phase shown above comes from the source calculation."
    }

    private var traceabilityBoundaryType: String {
        isMixtureEnvelope ? "Mixture bubble/dew envelope" : "Pure-fluid saturation"
    }

    private var traceabilityModelName: String {
        isMixtureEnvelope ? "CO₂+CH₄ EOS-CG-2021 VLE" : "Pure CO₂ saturation"
    }

    private func seriesName(for branch: PhaseEnvelopePoint.Branch) -> String {
        switch branch {
        case .bubble:
            isMixtureEnvelope ? "Bubble branch" : "CO₂ saturation boundary"
        case .dew:
            "Dew branch"
        case .critical:
            "Critical point"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: IFESpacing.medium) {
                ScientificStatusBanner(
                    title: bannerTitle,
                    message: bannerMessage
                )

                IFECard {
                    if exportLifecycle.artifacts != nil {
                        Button {
                            exportLifecycle.beginSharing()
                            showsShareSheet = true
                        } label: {
                            Label("Share PDF and CSV", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity, alignment: .leading)
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
                            .disabled(!canExportCompleteDiagram)
                            .accessibilityIdentifier("prepare-phase-diagram-export")
                        }
                    }
                }

                IFECard {
                    VStack(alignment: .leading, spacing: IFESpacing.small) {
                        Text(modelTitle)
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
                        LabeledContent(
                            "Boundary points",
                            value: "\(plotData.receivedPointCount) received, \(plotData.validPointCount) valid, \(plotData.plottedPointCount) plotted"
                        )
                        if plotData.hasGaps {
                            Label(
                                "Boundary contains gaps; invalid or discontinuous points are not joined.",
                                systemImage: "exclamationmark.triangle"
                            )
                            .font(.caption)
                            .foregroundStyle(Color.pxWarning)
                        }
                        Text(boundaryNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                IFECard {
                    VStack(alignment: .leading, spacing: IFESpacing.small) {
                        Text("Pressure–temperature diagram")
                            .font(.headline)
                        Text(chartSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Chart {
                            ForEach(plotData.segments) { segment in
                                ForEach(segment.points) { sample in
                                    LineMark(
                                        x: .value("Temperature (°C)", sample.temperatureCelsius),
                                        y: .value("Pressure (bar(a))", sample.pressureBar),
                                        series: .value("Segment", segment.id)
                                    )
                                    .foregroundStyle(by: .value(
                                        "Series",
                                        seriesName(for: segment.branch)
                                    ))
                                    .interpolationMethod(.linear)
                                }
                            }

                            ForEach(plotData.criticalPoints) { critical in
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
                            "Bubble branch": Color.pxChartBoundary,
                            "Dew branch": Color.ifeBlue,
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
                            isMixtureEnvelope
                                ? "Carbon dioxide methane bubble and dew phase envelope with operating point"
                                : "Pure carbon dioxide saturation boundary with critical point and operating point"
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
                            value: traceabilityBoundaryType
                        )
                        LabeledContent(
                            "Calculated points",
                            value: "\(plotData.receivedPointCount) received, \(plotData.validPointCount) valid, \(plotData.plottedPointCount) plotted"
                        )
                        LabeledContent("Composition") {
                            Text(record.request.composition.map {
                                "\($0.component.symbol) \(number($0.moleFraction * 100)) mol%"
                            }.joined(separator: ", "))
                            .multilineTextAlignment(.trailing)
                        }
                        if let model = response.model {
                            LabeledContent("Model", value: traceabilityModelName)
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
                            LabeledContent(
                                "Method",
                                value: isMixtureEnvelope
                                    ? "CO₂+CH₄ bubble/dew calculation"
                                    : "Pure CO₂ saturation calculation"
                            )
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
        .onChange(of: record.id) { _, _ in
            exportLifecycle.calculationChanged()
        }
        .onDisappear {
            exportLifecycle.cleanupIfIdle()
        }
        .sheet(isPresented: $showsShareSheet) {
            PhaseDiagramShareSheet(items: exportLifecycle.artifacts?.files ?? []) {
                showsShareSheet = false
                exportLifecycle.completeSharing()
            }
        }
    }

    private func prepareDiagramExport() {
        guard !isPreparingExport else { return }
        isPreparingExport = true
        exportErrorMessage = nil

        Task { @MainActor in
            await Task.yield()
            do {
                try exportLifecycle.prepareReplacement {
                    try PhaseDiagramImageExporter().writeTemporaryReportFiles(
                        for: record,
                        response: response
                    )
                }
            } catch {
                exportErrorMessage = error.localizedDescription
            }
            isPreparingExport = false
        }
    }

    private var canExportCompleteDiagram: Bool {
        response.isAvailable
            && response.boundaryKind == .pureFluidSaturation
            && response.solver?.converged != false
            && plotData.validPointCount == response.points.count
            && !plotData.segments.isEmpty
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

private struct PhaseDiagramShareSheet: UIViewControllerRepresentable {
    let items: [URL]
    let onComplete: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            onComplete()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
