import Charts
import PhaseXpertCore
import SwiftUI
import UIKit

/// Writes the Phase Map as a one-page A4 landscape vector PDF with the case
/// information, the chart and a legend.
@MainActor
struct PhaseMapPDFExporter {
    static let pageSize = CGSize(width: 842, height: 595)

    func writeTemporaryPDF(
        result: PhaseMapResult,
        pressureUnit: PressureDisplayUnit,
        temperatureUnit: TemperatureDisplayUnit,
        application: ApplicationIdentity? = nil
    ) throws -> PhaseDiagramExportArtifacts {
        guard !result.evaluations.isEmpty else {
            throw PhaseDiagramExportError.unavailable("Calculate a Phase Map before preparing the PDF.")
        }

        let page = Self.pageSize
        let canvas = PhaseMapReportCanvas(
            result: result,
            pressureUnit: pressureUnit,
            temperatureUnit: temperatureUnit,
            application: application
        )
        .frame(width: page.width, height: page.height)
        let renderer = ImageRenderer(content: canvas)

        let store = PhaseDiagramTemporaryExportStore()
        try store.cleanStaleArtifacts()
        try FileManager.default.createDirectory(
            at: store.directory,
            withIntermediateDirectories: true
        )
        let url = store.directory.appendingPathComponent(
            "PhaseXpert-Phase-Map-\(result.request.requestID.uuidString.prefix(8)).pdf"
        )

        var didWrite = false
        renderer.render { size, renderInContext in
            var mediaBox = CGRect(origin: .zero, size: size)
            guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else { return }
            context.beginPDFPage(nil)
            renderInContext(context)
            context.endPDFPage()
            context.closePDF()
            didWrite = true
        }
        guard didWrite else {
            throw PhaseDiagramExportError.renderingFailed
        }
        return PhaseDiagramExportArtifacts(files: [url])
    }
}

struct PhaseMapReportCanvas: View {
    let result: PhaseMapResult
    let pressureUnit: PressureDisplayUnit
    let temperatureUnit: TemperatureDisplayUnit
    let application: ApplicationIdentity?
    private let usesRegionMap: Bool
    private let regionImage: UIImage?

    init(
        result: PhaseMapResult,
        pressureUnit: PressureDisplayUnit,
        temperatureUnit: TemperatureDisplayUnit,
        application: ApplicationIdentity?
    ) {
        self.result = result
        self.pressureUnit = pressureUnit
        self.temperatureUnit = temperatureUnit
        self.application = application
        let usesRegionMap = PhaseMapRegionImage.usesRegionMap(for: result)
        self.usesRegionMap = usesRegionMap
        self.regionImage = usesRegionMap ? PhaseMapRegionImage.image(for: result) : nil
    }

    // MARK: Layout

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            caseInformation
            HStack(alignment: .top, spacing: 18) {
                chart
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                legendPanel
                    .frame(width: 196)
            }
            .frame(maxHeight: .infinity)
            footer
        }
        .padding(28)
        .background(Color.white)
        .foregroundStyle(Color.black)
        .environment(\.colorScheme, .light)
    }

    private var header: some View {
        HStack(alignment: .center) {
            Image("IFELogoEnglish")
                .resizable()
                .scaledToFit()
                .frame(width: 130, height: 44, alignment: .leading)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Phase Map")
                    .font(.system(size: 24, weight: .bold))
                Text("Preliminary multicomponent pressure–temperature classification")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.gray)
            }
        }
    }

    private var caseInformation: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 3) {
                infoRow("Case", caseLabel)
                infoRow("Model", "\(result.model.name) \(result.model.modelVersion)")
                infoRow("Composition", compositionText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                infoRow("Operating point", "\(pressureText(result.request.pressurePa))  ·  \(temperatureText(result.request.temperatureK))")
                infoRow("Map range", rangeText)
                infoRow("Grid", gridText)
                infoRow("Calculated", result.calculatedAt.formatted(date: .abbreviated, time: .shortened))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 10))
    }

    private func infoRow(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(.system(size: 10))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var chart: some View {
        Chart {
            if !usesRegionMap {
                ForEach(result.evaluations) { evaluation in
                    PointMark(
                        x: .value("Temperature (\(temperatureUnit.rawValue))", temperatureUnit.displayValue(from: evaluation.point.temperatureK)),
                        y: .value("Pressure (\(pressureUnit.rawValue))", pressureUnit.displayValue(from: evaluation.point.pressurePa))
                    )
                    .foregroundStyle(PhaseMapMarkerStyle.style(for: evaluation).color)
                    .symbol(PhaseMapMarkerStyle.style(for: evaluation).chartSymbol)
                    .symbolSize(evaluation.point.isOperatingPoint ? 110 : 80)
                }
            }
            if let operatingPoint = result.operatingPoint {
                PointMark(
                    x: .value("Temperature (\(temperatureUnit.rawValue))", temperatureUnit.displayValue(from: operatingPoint.point.temperatureK)),
                    y: .value("Pressure (\(pressureUnit.rawValue))", pressureUnit.displayValue(from: operatingPoint.point.pressurePa))
                )
                .foregroundStyle(Color.red)
                .symbolSize(220)
                .symbol {
                    operatingPointSymbol
                }
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 8)) }
        .chartYAxis { AxisMarks(values: .automatic(desiredCount: 8)) }
        .chartPlotStyle { plot in
            plot
                .background {
                    if let regionImage {
                        Image(uiImage: regionImage)
                            .resizable()
                            .interpolation(.high)
                    }
                }
                .border(Color.black.opacity(0.4), width: 0.75)
        }
        .chartXAxisLabel("Temperature (\(temperatureUnit.rawValue))")
        .chartYAxisLabel("Pressure (\(pressureUnit.rawValue))")
    }

    @ViewBuilder
    private var operatingPointSymbol: some View {
        if usesRegionMap {
            PhaseMapOperatingPointCross()
        } else {
            Circle().stroke(Color.red, lineWidth: 2.5).frame(width: 20, height: 20)
        }
    }

    private var legendPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Legend")
                .font(.system(size: 12, weight: .bold))
            ForEach(PhaseMapLegendEntry.entries(for: result)) { entry in
                HStack(spacing: 6) {
                    legendSwatch(entry.style)
                    Text(LocalizedStringKey(entry.label))
                        .font(.system(size: 10))
                    Spacer(minLength: 2)
                    Text(entry.count.formatted())
                        .font(.system(size: 10))
                        .foregroundStyle(Color.gray)
                }
            }
            HStack(spacing: 6) {
                operatingPointSymbol
                    .scaleEffect(0.7)
                    .frame(width: 16, height: 16)
                Text("Operating point")
                    .font(.system(size: 10))
            }
            if usesRegionMap {
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.25))
                        .overlay(Rectangle().stroke(Color.black.opacity(0.55), lineWidth: 1.5))
                        .frame(width: 16, height: 11)
                    Text("Classification boundary")
                        .font(.system(size: 10))
                }
            }
            Divider()
            Text(usesRegionMap
                 ? "Regions are drawn between evaluated flash points. Each flash point keeps the classification returned by the provider; nothing is interpolated."
                 : "Each marker is one evaluated flash point. Marker colour and shape both identify the classification.")
                .font(.system(size: 8.5))
                .foregroundStyle(Color.gray)
            Divider()
            VStack(alignment: .leading, spacing: 2) {
                summaryRow("Flash points", result.evaluations.count)
                summaryRow("Classified", result.classifiedCount)
                summaryRow("Unknown", result.unknownCount)
                summaryRow("Failed", result.failedCount)
                summaryRow("Non-converged", result.nonConvergedCount)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color(white: 0.96), in: RoundedRectangle(cornerRadius: 6))
    }

    private func legendSwatch(_ style: PhaseMapMarkerStyle) -> some View {
        Group {
            if usesRegionMap {
                RoundedRectangle(cornerRadius: 2).fill(style.color)
            } else {
                Image(systemName: style.systemImage)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(style.color)
            }
        }
        .frame(width: 16, height: 11)
    }

    private func summaryRow(_ title: LocalizedStringKey, _ value: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value.formatted())
        }
        .font(.system(size: 9))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("PRELIMINARY — validation pending. Not a thermodynamic phase envelope.")
                .font(.system(size: 8.5, weight: .semibold))
            ForEach(result.warnings, id: \.self) { warning in
                Text(warning)
                    .font(.system(size: 8))
                    .foregroundStyle(Color.gray)
            }
            Text(footerIdentity)
                .font(.system(size: 8))
                .foregroundStyle(Color.gray)
        }
    }

    // MARK: Text

    private var footerIdentity: String {
        var parts = ["Request ID: \(result.request.requestID.uuidString)"]
        if let application {
            parts.append("PhaseXpert \(application.version) (\(application.build))")
        }
        return parts.joined(separator: "  ·  ")
    }

    private var caseLabel: String {
        let composition = SavedCaseNameFormatter.compositionLabel(for: result.request.composition)
        return "\(composition) — \(pressureText(result.request.pressurePa)), \(temperatureText(result.request.temperatureK))"
    }

    private var compositionText: String {
        let active = result.request.composition
            .filter { $0.moleFraction.isFinite && $0.moleFraction > 0 }
            .sorted { $0.moleFraction > $1.moleFraction }
        guard !active.isEmpty else { return "—" }
        return active
            .map { "\($0.component.symbol) \(number($0.moleFraction * 100)) mol%" }
            .joined(separator: "  ·  ")
    }

    private var rangeText: String {
        let range = result.request.range
        let pressure = "\(number(pressureUnit.displayValue(from: range.pressureMinimumPa)))–\(number(pressureUnit.displayValue(from: range.pressureMaximumPa))) \(pressureUnit.rawValue)"
        let temperature = "\(number(temperatureUnit.displayValue(from: range.temperatureMinimumK)))–\(number(temperatureUnit.displayValue(from: range.temperatureMaximumK))) \(temperatureUnit.rawValue)"
        return "\(pressure)  ·  \(temperature)"
    }

    private var gridText: String {
        let size = result.request.resolution.rawValue
        return "\(size) × \(size) (\(result.evaluations.count.formatted()) flash points)"
    }

    private func pressureText(_ pascal: Double) -> String {
        "\(number(pressureUnit.displayValue(from: pascal))) \(pressureUnit.rawValue)"
    }

    private func temperatureText(_ kelvin: Double) -> String {
        "\(number(temperatureUnit.displayValue(from: kelvin))) \(temperatureUnit.rawValue)"
    }

    private func number(_ value: Double) -> String {
        value.formatted(.number.precision(.significantDigits(1...6)))
    }

    // MARK: Axis domains

    private var xDomain: ClosedRange<Double> {
        let values = result.evaluations.map { temperatureUnit.displayValue(from: $0.point.temperatureK) }
        return usesRegionMap ? halfStepDomain(values) : paddedDomain(values)
    }

    private var yDomain: ClosedRange<Double> {
        let values = result.evaluations.map { pressureUnit.displayValue(from: $0.point.pressurePa) }
        return usesRegionMap ? halfStepDomain(values) : paddedDomain(values)
    }

    /// Matches the region raster, which extends half a grid step beyond the outer nodes.
    private func halfStepDomain(_ values: [Double]) -> ClosedRange<Double> {
        let finite = values.filter(\.isFinite)
        guard let minimum = finite.min(), let maximum = finite.max(), maximum > minimum else { return 0...1 }
        let half = (maximum - minimum) / Double(result.request.resolution.rawValue - 1) / 2
        return (minimum - half)...(maximum + half)
    }

    private func paddedDomain(_ values: [Double]) -> ClosedRange<Double> {
        let finite = values.filter(\.isFinite)
        guard let minimum = finite.min(), let maximum = finite.max() else { return 0...1 }
        let padding = max(maximum - minimum, 1) * 0.08
        return (minimum - padding)...(maximum + padding)
    }
}
