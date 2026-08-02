import Charts
import Foundation
import PhaseXpertCore
import SwiftUI
import UIKit

struct PhaseDiagramReportAttachment: Sendable {
    let pngData: Data
    let response: PhaseEnvelopeResponse
}

enum PhaseDiagramExportError: LocalizedError {
    case unavailable(String)
    case renderingFailed

    var errorDescription: String? {
        switch self {
        case let .unavailable(message): message
        case .renderingFailed:
            "PhaseXpert could not render the calculated phase diagram."
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

    private func validate(
        record: CalculationRecord,
        response: PhaseEnvelopeResponse
    ) throws {
        guard response.isAvailable,
              response.boundaryKind != nil,
              !response.points.isEmpty
        else {
            throw PhaseDiagramExportError.unavailable(
                "The selected provider did not return an exportable phase boundary."
            )
        }
        if response.boundaryKind == .mixtureEnvelope {
            guard response.points.filter({ $0.branch == .bubble }).count >= 2,
                  response.points.filter({ $0.branch == .dew }).count >= 2
            else {
                throw PhaseDiagramExportError.unavailable(
                    "The selected provider did not return both mixture-envelope branches."
                )
            }
        }
        guard response.points.allSatisfy({
            $0.temperatureK.isFinite && $0.pressurePa.isFinite && $0.pressurePa > 0
        }),
        record.input.temperatureK.isFinite,
        record.input.pressurePa.isFinite
        else {
            throw PhaseDiagramExportError.unavailable(
                "The phase diagram contains a non-finite calculated value."
            )
        }
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

    private var dew: [Sample] {
        samples.filter { $0.branch == .dew }
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
                    Text(response.boundaryKind == .mixtureEnvelope
                        ? "CO₂ mixture pressure–temperature envelope"
                        : "Pure CO₂ pressure–temperature diagram")
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
                "Dew branch": Color.ifeSignal,
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

            Text("Model: \(response.model?.name ?? record.response.model.name) • Model \(response.model?.modelVersion ?? record.response.model.modelVersion) • Provider \(response.model?.providerVersion ?? record.response.model.providerVersion)")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
            Text("Calculation ID: \(record.response.calculationID.uuidString) • Envelope request ID: \(response.requestID.uuidString)")
                .font(.system(size: 15).monospaced())
                .foregroundStyle(.secondary)
            Text("Composition: \(record.request.composition.map { "\($0.component.symbol) \(number($0.moleFraction * 100)) mol%" }.joined(separator: ", "))")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
            Text("Straight line segments connect adjacent provider-calculated points within each branch for display only. No scientific values are interpolated or estimated.")
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
