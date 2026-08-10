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
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhaseXpertPhaseDiagrams", isDirectory: true)
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
        response: PhaseEnvelopeResponse
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
        try writePDF(attachment: attachment, record: record, response: response, to: pdfURL)
        try csv(record: record, response: response).write(
            to: csvURL,
            atomically: true,
            encoding: .utf8
        )
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
        guard response.points.allSatisfy({
            $0.temperatureK.isFinite && $0.pressurePa.isFinite && $0.pressurePa > 0
        }),
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
            ["input", "pressure", "\(record.input.pressurePa / 100_000)", "bar(a)"],
            ["input", "temperature", "\(record.input.temperatureK - 273.15)", "°C"],
            ["input", "composition", record.request.composition.map { "\($0.component.symbol):\($0.moleFraction)" }.joined(separator: ";"), "mole fraction"],
            ["status", "preliminary", "validation pending", ""],
            ["data", "temperature", "pressure", "branch"]
        ]
        rows.append(contentsOf: response.points.map {
            ["point", "\($0.temperatureK - 273.15)", "\($0.pressurePa / 100_000)", $0.branch.rawValue]
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
        Operating point: \(record.input.pressurePa / 100_000) bar(a), \(record.input.temperatureK - 273.15) °C.
        Phase returned by source calculation: \(record.response.phase.displayName).
        Provider/model: \(response.model?.name ?? record.response.model.name), model \(response.model?.modelVersion ?? record.response.model.modelVersion), provider \(response.model?.providerVersion ?? record.response.model.providerVersion).
        Calculation ID: \(record.response.calculationID.uuidString).
        Phase-envelope request ID: \(response.requestID.uuidString).
        Straight line segments connect adjacent calculated points for display only. No scientific values are interpolated or estimated.
        """
    }
}

private struct PhaseDiagramExportCanvas: View {
    private struct Sample: Identifiable {
        let id: Int
        let temperatureCelsius: Double
        let pressureBar: Double
        let branch: PhaseEnvelopePoint.Branch
    }

    let record: CalculationRecord
    let response: PhaseEnvelopeResponse

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

    private var saturation: [Sample] {
        samples.filter { $0.branch == .bubble }
    }

    private var critical: Sample? {
        samples.first { $0.branch == .critical }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("PhaseXpert")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(Color.ifePrimary)
                    Text("Pure CO₂ pressure–temperature diagram")
                        .font(.system(size: 28, weight: .semibold))
                    Text("PRELIMINARY — VALIDATION PENDING")
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
                ForEach(saturation) { sample in
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

            Text("Model: Pure CO₂ saturation • Model \(response.model?.modelVersion ?? record.response.model.modelVersion) • Implementation \(response.model?.providerVersion ?? record.response.model.providerVersion)")
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
