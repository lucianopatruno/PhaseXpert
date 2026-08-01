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
        let composition = record.request.composition.filter { $0.moleFraction > 1e-12 }
        guard composition.count == 1,
              composition[0].component == .carbonDioxide,
              abs(composition[0].moleFraction - 1) <= 1e-9
        else {
            throw PhaseDiagramExportError.unavailable(
                "Phase-diagram export is available only for a real pure CO₂ boundary."
            )
        }
        guard response.isAvailable,
              response.boundaryKind == .pureFluidSaturation,
              !response.points.isEmpty
        else {
            throw PhaseDiagramExportError.unavailable(
                "The selected provider did not return an exportable pure CO₂ boundary."
            )
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
                    .foregroundStyle(by: .value("Series", "CO₂ saturation boundary"))
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

            Text("Model: \(response.model?.name ?? record.response.model.name) • Model \(response.model?.modelVersion ?? record.response.model.modelVersion) • Provider \(response.model?.providerVersion ?? record.response.model.providerVersion)")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
            Text("Straight line segments connect provider-calculated points. No estimated or decorative boundary is generated.")
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
