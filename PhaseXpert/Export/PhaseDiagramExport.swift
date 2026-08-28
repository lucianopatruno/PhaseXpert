import Charts
import Foundation
import PhaseXpertCore
import SwiftUI
import UIKit

struct PhaseDiagramReportAttachment: Sendable {
    let pngData: Data
    let response: PhaseEnvelopeResponse
}

struct PhaseDiagramExportArtifacts: Identifiable {
    let id = UUID()
    let files: [URL]
}

struct PhaseBoundaryPlotPoint: Identifiable, Equatable {
    let id: Int
    let originalIndex: Int
    let temperatureCelsius: Double
    let pressureBar: Double
    let branch: PhaseEnvelopePoint.Branch

    init(originalIndex: Int, point: PhaseEnvelopePoint) {
        self.id = originalIndex
        self.originalIndex = originalIndex
        self.temperatureCelsius = point.temperatureK - 273.15
        self.pressureBar = point.pressurePa / 100_000
        self.branch = point.branch
    }
}

struct PhaseBoundaryLineSegment: Identifiable, Equatable {
    let id: String
    let branch: PhaseEnvelopePoint.Branch
    let points: [PhaseBoundaryPlotPoint]
}

struct PhaseBoundaryPlotData: Equatable {
    let receivedPointCount: Int
    let validPointCount: Int
    let plottedPointCount: Int
    let segments: [PhaseBoundaryLineSegment]
    let criticalPoints: [PhaseBoundaryPlotPoint]

    var hasGaps: Bool {
        validPointCount != receivedPointCount
            || segments.count > Set(segments.map(\.branch)).count
    }
}

enum PhaseBoundarySeriesBuilder {
    static func plotData(for response: PhaseEnvelopeResponse) -> PhaseBoundaryPlotData {
        var validPointCount = 0
        var segments: [PhaseBoundaryLineSegment] = []
        var criticalPoints: [PhaseBoundaryPlotPoint] = []
        var currentBranch: PhaseEnvelopePoint.Branch?
        var currentPoints: [PhaseBoundaryPlotPoint] = []
        var segmentOrdinal = 0

        func finishSegment() {
            guard let branch = currentBranch, currentPoints.count >= 2 else {
                currentBranch = nil
                currentPoints = []
                return
            }
            segments.append(PhaseBoundaryLineSegment(
                id: "\(branch.rawValue)-\(segmentOrdinal)",
                branch: branch,
                points: currentPoints
            ))
            segmentOrdinal += 1
            currentBranch = nil
            currentPoints = []
        }

        for (index, point) in response.points.enumerated() {
            guard isFiniteBoundaryPoint(point) else {
                finishSegment()
                continue
            }

            validPointCount += 1
            let plotPoint = PhaseBoundaryPlotPoint(originalIndex: index, point: point)

            if point.branch == .critical {
                finishSegment()
                criticalPoints.append(plotPoint)
                continue
            }

            if currentBranch == nil {
                currentBranch = point.branch
            } else if currentBranch != point.branch {
                finishSegment()
                currentBranch = point.branch
            }
            currentPoints.append(plotPoint)
        }
        finishSegment()

        return PhaseBoundaryPlotData(
            receivedPointCount: response.points.count,
            validPointCount: validPointCount,
            plottedPointCount: segments.reduce(0) { $0 + $1.points.count } + criticalPoints.count,
            segments: segments,
            criticalPoints: criticalPoints
        )
    }

    static func isFiniteBoundaryPoint(_ point: PhaseEnvelopePoint) -> Bool {
        point.temperatureK.isFinite && point.pressurePa.isFinite && point.pressurePa > 0
    }
}

enum PhaseDiagramExportError: LocalizedError {
    case unavailable(String)
    case renderingFailed

    var errorDescription: String? {
        switch self {
        case let .unavailable(message): message
        case .renderingFailed:
            "PhaseXpert did not render the calculated phase diagram."
        }
    }
}

@MainActor
struct PhaseDiagramImageExporter {
    func attachment(
        for record: CalculationRecord,
        response: PhaseEnvelopeResponse
    ) throws -> PhaseDiagramReportAttachment {
        try validate(record: record, response: response)

        let canvas = PhaseDiagramExportCanvas(record: record, response: response)
            .frame(width: 1_200, height: 900)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 1

        guard let data = renderer.uiImage?.pngData() else {
            throw PhaseDiagramExportError.renderingFailed
        }
        return PhaseDiagramReportAttachment(pngData: data, response: response)
    }

    func writeTemporaryPNG(
        for record: CalculationRecord,
        response: PhaseEnvelopeResponse
    ) throws -> URL {
        let attachment = try attachment(for: record, response: response)
        let store = PhaseDiagramTemporaryExportStore()
        try store.cleanStaleArtifacts()
        let directory = store.directory
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent(
            "PhaseXpert-Phase-Diagram-\(record.response.calculationID.uuidString.prefix(8)).png"
        )
        try attachment.pngData.write(to: url, options: .atomic)
        return url
    }

    func writeTemporaryReportFiles(
        for record: CalculationRecord,
        response: PhaseEnvelopeResponse,
        csvWriter: ((CalculationRecord, PhaseEnvelopeResponse) throws -> String)? = nil
    ) throws -> PhaseDiagramExportArtifacts {
        let attachment = try attachment(for: record, response: response)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhaseXpertPhaseDiagrams", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let prefix = "PhaseXpert-Phase-Diagram-\(record.response.calculationID.uuidString.prefix(8))"
        let pdfURL = directory.appendingPathComponent("\(prefix).pdf")
        let csvURL = directory.appendingPathComponent("\(prefix).csv")
        do {
            try writePDF(attachment: attachment, record: record, response: response, to: pdfURL)
            try (csvWriter?(record, response) ?? csv(record: record, response: response)).write(
                to: csvURL,
                atomically: true,
                encoding: .utf8
            )
        } catch {
            try? FileManager.default.removeItem(at: pdfURL)
            try? FileManager.default.removeItem(at: csvURL)
            throw error
        }
        return PhaseDiagramExportArtifacts(files: [pdfURL, csvURL])
    }

    private func validate(
        record: CalculationRecord,
        response: PhaseEnvelopeResponse
    ) throws {
        guard PhaseDiagramEligibility.isPureCarbonDioxide(
            composition: record.request.composition
        ) else {
            throw PhaseDiagramExportError.unavailable(
                PhaseDiagramEligibility.pureCarbonDioxideScopeMessage
            )
        }
        guard response.isAvailable,
              response.boundaryKind != nil,
              !response.points.isEmpty
        else {
            throw PhaseDiagramExportError.unavailable(
                "The CO₂ phase diagram is not ready for export."
            )
        }
        if response.boundaryKind == .mixtureEnvelope {
            throw PhaseDiagramExportError.unavailable(
                PhaseDiagramEligibility.pureCarbonDioxideScopeMessage
            )
        }
        let plotData = PhaseBoundarySeriesBuilder.plotData(for: response)
        guard plotData.validPointCount == response.points.count,
              !plotData.segments.isEmpty,
              response.solver?.converged != false,
              record.input.temperatureK.isFinite,
        record.input.pressurePa.isFinite
        else {
            throw PhaseDiagramExportError.unavailable(
                "The CO₂ phase diagram is not ready for export."
            )
        }
    }

    private func writePDF(
        attachment: PhaseDiagramReportAttachment,
        record: CalculationRecord,
        response: PhaseEnvelopeResponse,
        to url: URL
    ) throws {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        try renderer.writePDF(to: url) { context in
            context.beginPage()
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.preferredFont(forTextStyle: .title2)
            ]
            let bodyAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.preferredFont(forTextStyle: .footnote)
            ]
            "Pure CO₂ pressure–temperature diagram".draw(
                at: CGPoint(x: 36, y: 32),
                withAttributes: titleAttributes
            )
            "PRELIMINARY — VALIDATION PENDING".draw(
                at: CGPoint(x: 36, y: 62),
                withAttributes: bodyAttributes
            )
            if let image = UIImage(data: attachment.pngData) {
                image.draw(in: CGRect(x: 36, y: 92, width: 540, height: 405))
            }
            provenance(record: record, response: response).draw(
                in: CGRect(x: 36, y: 520, width: 540, height: 220),
                withAttributes: bodyAttributes
            )
        }
    }

    private func csv(record: CalculationRecord, response: PhaseEnvelopeResponse) -> String {
        var rows = [
            ["section", "name", "value", "unit"],
            ["provenance", "calculation_id", record.response.calculationID.uuidString, ""],
            ["provenance", "phase_envelope_request_id", response.requestID.uuidString, ""],
            ["provenance", "model", response.model?.name ?? record.response.model.name, ""],
            ["provenance", "model_version", response.model?.modelVersion ?? record.response.model.modelVersion, ""],
            ["provenance", "provider_version", response.model?.providerVersion ?? record.response.model.providerVersion, ""],
            ["input", "pressure_entered", "\(record.input.pressureValue)", record.input.pressureDisplayUnitLabel],
            ["input", "pressure_si", "\(record.input.pressurePa)", "Pa"],
            ["input", "temperature_entered", "\(record.input.temperatureValue)", record.input.temperatureUnit.rawValue],
            ["input", "temperature_si", "\(record.input.temperatureK)", "K"],
            ["input", "composition", record.request.composition.map { "\($0.component.symbol):\($0.moleFraction)" }.joined(separator: ";"), "mole fraction"],
            ["status", "preliminary", "validation pending", ""],
            ["data", "segment_id", "temperature_c", "pressure_bar", "branch", "original_index"]
        ]
        let plotData = PhaseBoundarySeriesBuilder.plotData(for: response)
        for segment in plotData.segments {
            rows.append(contentsOf: segment.points.map {
                ["point", segment.id, "\($0.temperatureCelsius)", "\($0.pressureBar)", segment.branch.rawValue, "\($0.originalIndex)"]
            })
        }
        rows.append(contentsOf: plotData.criticalPoints.map {
            ["critical", "critical", "\($0.temperatureCelsius)", "\($0.pressureBar)", $0.branch.rawValue, "\($0.originalIndex)"]
        })
        return rows.map { row in
            row.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
                .joined(separator: ",")
        }.joined(separator: "\n") + "\n"
    }

    private func provenance(
        record: CalculationRecord,
        response: PhaseEnvelopeResponse
    ) -> String {
        """
        Axis units: Temperature (°C), Pressure (bar(a)).
        Operating point: \(record.input.pressureValue) \(record.input.pressureDisplayUnitLabel) (\(record.input.pressurePa) Pa), \(record.input.temperatureValue) \(record.input.temperatureUnit.rawValue) (\(record.input.temperatureK) K).
        Phase returned by source calculation: \(record.response.phase.displayName).
        Provider/model: \(response.model?.name ?? record.response.model.name), model \(response.model?.modelVersion ?? record.response.model.modelVersion), provider \(response.model?.providerVersion ?? record.response.model.providerVersion).
        Calculation ID: \(record.response.calculationID.uuidString).
        Phase-envelope request ID: \(response.requestID.uuidString).
        Straight line segments connect adjacent calculated points for display only. No scientific values are interpolated or estimated.
        """
    }
}

struct PhaseDiagramTemporaryExportStore {
    let directory: URL
    private let fileManager: FileManager

    init(
        baseDirectory: URL = FileManager.default.temporaryDirectory,
        fileManager: FileManager = .default
    ) {
        self.directory = baseDirectory.appendingPathComponent(
            "PhaseXpertPhaseDiagrams",
            isDirectory: true
        )
        self.fileManager = fileManager
    }

    func cleanStaleArtifacts() throws {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        for file in try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) where isOwnedArtifact(file) {
            try fileManager.removeItem(at: file)
        }
    }

    func remove(_ artifacts: PhaseDiagramExportArtifacts?) {
        guard let artifacts else { return }
        for file in artifacts.files where isOwnedArtifact(file) {
            try? fileManager.removeItem(at: file)
        }
    }

    private func isOwnedArtifact(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return name.hasPrefix("PhaseXpert-Phase-Diagram-")
            && ["pdf", "csv", "png"].contains(url.pathExtension.lowercased())
    }
}

@MainActor
final class PhaseDiagramExportLifecycle {
    private let store: PhaseDiagramTemporaryExportStore
    private(set) var artifacts: PhaseDiagramExportArtifacts?
    private(set) var isSharing = false

    init(store: PhaseDiagramTemporaryExportStore = PhaseDiagramTemporaryExportStore()) {
        self.store = store
    }

    func prepareReplacement(
        createArtifacts: () throws -> PhaseDiagramExportArtifacts
    ) throws {
        guard !isSharing else { return }
        store.remove(artifacts)
        artifacts = nil
        try store.cleanStaleArtifacts()
        artifacts = try createArtifacts()
    }

    func beginSharing() {
        guard artifacts != nil else { return }
        isSharing = true
    }

    func completeSharing() {
        isSharing = false
        cleanupIfIdle()
    }

    func cleanupIfIdle() {
        guard !isSharing else { return }
        store.remove(artifacts)
        artifacts = nil
    }

    func calculationChanged() {
        cleanupIfIdle()
    }
}

private struct PhaseDiagramExportCanvas: View {
    let record: CalculationRecord
    let response: PhaseEnvelopeResponse

    private var plotData: PhaseBoundaryPlotData {
        PhaseBoundarySeriesBuilder.plotData(for: response)
    }

    private var isMixtureEnvelope: Bool {
        response.boundaryKind == .mixtureEnvelope
    }

    private var title: String {
        isMixtureEnvelope
            ? "CO₂+CH₄ pressure–temperature envelope"
            : "Pure CO₂ pressure–temperature diagram"
    }

    private var statusText: String {
        isMixtureEnvelope ? "LIMITED VALIDATED VLE RANGE" : "PRELIMINARY — VALIDATION PENDING"
    }

    private var modelName: String {
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
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("PhaseXpert")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(Color.ifePrimary)
                    Text(title)
                        .font(.system(size: 28, weight: .semibold))
                    Text(statusText)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(Color.ifePrimary)
                }
                Spacer()
                Image("IFELogoEnglish")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 250, height: 90, alignment: .trailing)
            }

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
                    .symbolSize(180)
                    .foregroundStyle(by: .value("Series", "Critical point"))
                }
                PointMark(
                    x: .value("Temperature (°C)", record.input.temperatureK - 273.15),
                    y: .value("Pressure (bar(a))", record.input.pressurePa / 100_000)
                )
                .symbolSize(200)
                .foregroundStyle(by: .value("Series", "Operating point"))
            }
            .chartForegroundStyleScale([
                "CO₂ saturation boundary": Color.ifePrimary,
                "Bubble branch": Color.ifePrimary,
                "Dew branch": Color.ifeBlue,
                "Critical point": Color.ifeSignal,
                "Operating point": Color.ifeText
            ])
            .chartXAxisLabel("Temperature (°C)")
            .chartYAxisLabel("Pressure (bar(a))")
            .font(.system(size: 18))
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Text("Operating point: \(number(record.input.pressurePa / 100_000)) bar(a), \(number(record.input.temperatureK - 273.15)) °C")
                Spacer()
                Text("\(response.points.count) calculated points")
            }
            .font(.system(size: 18, weight: .medium))

            Text("Model: \(modelName) • Version \(response.model?.modelVersion ?? record.response.model.modelVersion) • Provider \(response.model?.providerVersion ?? record.response.model.providerVersion)")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
            Text("Calculation ID: \(record.response.calculationID.uuidString) • Envelope request ID: \(response.requestID.uuidString)")
                .font(.system(size: 15).monospaced())
                .foregroundStyle(.secondary)
            Text("Composition: \(record.request.composition.map { "\($0.component.symbol) \(number($0.moleFraction * 100)) mol%" }.joined(separator: ", "))")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
            Text("Straight line segments connect adjacent calculated points for display only. No scientific values are interpolated or estimated.")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
        }
        .padding(50)
        .background(Color.white)
        .foregroundStyle(Color.black)
    }

    private func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...4)))
    }
}
