import CoreGraphics
import CoreText
import Foundation
import PhaseXpertCore
import UIKit

/// Printable, provider-independent rendering of an immutable saved calculation.
///
/// Core Graphics and Core Text are used instead of screen capture so the PDF
/// remains searchable, paginates long records and is independent of appearance.
struct PDFCalculationExportRenderer: CalculationExportRendering {
    let format = CalculationExportFormat.pdf
    let phaseDiagram: PhaseDiagramReportAttachment?

    init(phaseDiagram: PhaseDiagramReportAttachment? = nil) {
        self.phaseDiagram = phaseDiagram
    }

    func render(_ snapshot: SavedCaseExportSnapshot) throws -> Data {
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output as CFMutableData) else {
            throw CalculationExportError.pdfRenderingFailed(
                "PhaseXpert could not create a PDF data consumer."
            )
        }

        var mediaBox = PDFReportLayout.pageRect
        let metadata = [
            kCGPDFContextTitle as String: "PhaseXpert calculation report — \(snapshot.name)",
            kCGPDFContextAuthor as String: "IFE Flow Technology Department",
            kCGPDFContextCreator as String: "PhaseXpert",
            kCGPDFContextSubject as String: "Thermophysical calculation record and scientific provenance"
        ] as CFDictionary
        guard let context = CGContext(
            consumer: consumer,
            mediaBox: &mediaBox,
            metadata
        ) else {
            throw CalculationExportError.pdfRenderingFailed(
                "PhaseXpert could not create the PDF graphics context."
            )
        }

        let body = PDFReportContent(snapshot: snapshot).attributedString()
        let framesetter = CTFramesetterCreateWithAttributedString(body)
        var textLocation = 0
        var pageNumber = 0

        repeat {
            pageNumber += 1
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(PDFReportLayout.pageRect)
            drawHeader(in: context, pageNumber: pageNumber)

            let path = CGPath(
                rect: PDFReportLayout.contentRect,
                transform: nil
            )
            let frame = CTFramesetterCreateFrame(
                framesetter,
                CFRange(location: textLocation, length: 0),
                path,
                nil
            )
            CTFrameDraw(frame, context)
            let visibleRange = CTFrameGetVisibleStringRange(frame)
            guard visibleRange.length > 0 else {
                context.endPDFPage()
                context.closePDF()
                throw CalculationExportError.pdfRenderingFailed(
                    "PhaseXpert could not paginate the report content."
                )
            }
            textLocation += visibleRange.length

            drawFooter(in: context, pageNumber: pageNumber)
            context.endPDFPage()
        } while textLocation < body.length

        if let phaseDiagram {
            guard PhaseDiagramEligibility.isPureCarbonDioxide(
                composition: snapshot.calculation.request.composition
            ),
            phaseDiagram.response.boundaryKind == .pureFluidSaturation else {
                throw CalculationExportError.pdfRenderingFailed(
                    PhaseDiagramEligibility.pureCarbonDioxideScopeMessage
                )
            }
            pageNumber += 1
            try drawPhaseDiagramPage(
                phaseDiagram,
                in: context,
                pageNumber: pageNumber
            )
        }

        context.closePDF()
        return output as Data
    }

    private func drawPhaseDiagramPage(
        _ attachment: PhaseDiagramReportAttachment,
        in context: CGContext,
        pageNumber: Int
    ) throws {
        guard let image = UIImage(data: attachment.pngData)?.cgImage else {
            throw CalculationExportError.pdfRenderingFailed(
                "PhaseXpert could not decode the calculated phase-diagram image."
            )
        }

        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(PDFReportLayout.pageRect)
        drawHeader(in: context, pageNumber: pageNumber)

        drawLine(
            "Calculated phase diagram",
            font: PDFReportFonts.section,
            color: PDFReportPalette.primary,
            position: CGPoint(x: PDFReportLayout.margin, y: 748),
            context: context
        )

        let target = CGRect(x: PDFReportLayout.margin, y: 205, width: 515, height: 515)
        let imageAspect = CGFloat(image.width) / CGFloat(image.height)
        let targetAspect = target.width / target.height
        let renderedRect: CGRect
        if imageAspect > targetAspect {
            let height = target.width / imageAspect
            renderedRect = CGRect(x: target.minX, y: target.midY - height / 2, width: target.width, height: height)
        } else {
            let width = target.height * imageAspect
            renderedRect = CGRect(x: target.midX - width / 2, y: target.minY, width: width, height: target.height)
        }
        context.saveGState()
        context.interpolationQuality = .high
        context.draw(image, in: renderedRect)
        context.restoreGState()

        let response = attachment.response
        drawLine(
            "Boundary: pure-fluid CO₂ saturation • \(response.points.count) calculated points",
            font: PDFReportFonts.body,
            color: PDFReportPalette.bodyText,
            position: CGPoint(x: PDFReportLayout.margin, y: 176),
            context: context
        )
        if let model = response.model {
            drawLine(
                "Model: pure CO₂ saturation • Version \(model.modelVersion) • Provider \(model.providerVersion)",
                font: PDFReportFonts.small,
                color: PDFReportPalette.secondaryText,
                position: CGPoint(x: PDFReportLayout.margin, y: 158),
                context: context
            )
        }
        if let solver = response.solver {
            drawLine(
                "Method: \(solver.method) • Converged: \(solver.converged ? "Yes" : "No") • Duration: \(reportNumber(solver.durationMilliseconds)) ms",
                font: PDFReportFonts.small,
                color: PDFReportPalette.secondaryText,
                position: CGPoint(x: PDFReportLayout.margin, y: 140),
                context: context
            )
        }
        drawLine(
            "Envelope request ID: \(response.requestID.uuidString)",
            font: PDFReportFonts.small,
            color: PDFReportPalette.secondaryText,
            position: CGPoint(x: PDFReportLayout.margin, y: 122),
            context: context
        )
        drawLine(
            "PRELIMINARY — VALIDATION PENDING. No scientific values are interpolated or estimated.",
            font: PDFReportFonts.small,
            color: PDFReportPalette.warning,
            position: CGPoint(x: PDFReportLayout.margin, y: 100),
            context: context
        )
        drawFooter(in: context, pageNumber: pageNumber)
        context.endPDFPage()
    }

    private func reportNumber(_ value: Double) -> String {
        value.formatted(
            .number
                .locale(Locale(identifier: "en_US_POSIX"))
                .grouping(.automatic)
                .precision(.fractionLength(0...6))
        )
    }

    private func drawHeader(in context: CGContext, pageNumber: Int) {
        context.saveGState()
        context.setFillColor(PDFReportPalette.primary)
        context.fill(
            CGRect(
                x: 0,
                y: PDFReportLayout.pageRect.maxY - 18,
                width: PDFReportLayout.pageRect.width,
                height: 18
            )
        )

        drawLine(
            pageNumber == 1
                ? "PhaseXpert"
                : "PhaseXpert — Calculation report",
            font: PDFReportFonts.header,
            color: PDFReportPalette.primary,
            position: CGPoint(x: PDFReportLayout.margin, y: 800),
            context: context
        )
        drawLine(
            "Developed by the IFE Flow Technology Department",
            font: PDFReportFonts.small,
            color: PDFReportPalette.secondaryText,
            position: CGPoint(x: PDFReportLayout.margin, y: 784),
            context: context
        )
        drawIFELogo(in: context)

        context.setStrokeColor(PDFReportPalette.rule)
        context.setLineWidth(0.6)
        context.move(to: CGPoint(x: PDFReportLayout.margin, y: 776))
        context.addLine(
            to: CGPoint(
                x: PDFReportLayout.pageRect.maxX - PDFReportLayout.margin,
                y: 776
            )
        )
        context.strokePath()
        context.restoreGState()
    }

    private func drawIFELogo(in context: CGContext) {
        guard let logo = UIImage(named: "IFELogoEnglish")?.cgImage else {
            return
        }

        let bounds = PDFReportLayout.logoBounds
        let aspectRatio = CGFloat(logo.width) / CGFloat(logo.height)
        let width = min(bounds.width, bounds.height * aspectRatio)
        let height = width / aspectRatio
        let rect = CGRect(
            x: bounds.maxX - width,
            y: bounds.midY - height / 2,
            width: width,
            height: height
        )

        context.saveGState()
        context.interpolationQuality = .high
        context.draw(logo, in: rect)
        context.restoreGState()
    }

    private func drawFooter(in context: CGContext, pageNumber: Int) {
        context.saveGState()
        context.setStrokeColor(PDFReportPalette.rule)
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: PDFReportLayout.margin, y: 48))
        context.addLine(
            to: CGPoint(
                x: PDFReportLayout.pageRect.maxX - PDFReportLayout.margin,
                y: 48
            )
        )
        context.strokePath()

        drawLine(
            "Generated locally by PhaseXpert • Page \(pageNumber)",
            font: PDFReportFonts.footer,
            color: PDFReportPalette.secondaryText,
            position: CGPoint(x: PDFReportLayout.margin, y: 31),
            context: context
        )
        context.restoreGState()
    }

    private func drawLine(
        _ text: String,
        font: CTFont,
        color: CGColor,
        position: CGPoint,
        context: CGContext
    ) {
        let attributed = NSAttributedString(
            string: text,
            attributes: PDFReportText.attributes(font: font, color: color)
        )
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = position
        CTLineDraw(line, context)
    }
}

private enum PDFReportLayout {
    static let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
    static let margin: CGFloat = 44
    static let contentRect = CGRect(
        x: margin,
        y: 58,
        width: pageRect.width - 2 * margin,
        height: 706
    )
    static let logoBounds = CGRect(
        x: pageRect.maxX - margin - 150,
        y: 781,
        width: 150,
        height: 42
    )
}

private enum PDFReportPalette {
    // IFEPrimary light-appearance colour from the PhaseXpert asset catalogue.
    static var primary: CGColor { CGColor(
        srgbRed: 0.161,
        green: 0.192,
        blue: 0.447,
        alpha: 1
    ) }
    static var bodyText: CGColor { CGColor(
        srgbRed: 0.08,
        green: 0.08,
        blue: 0.10,
        alpha: 1
    ) }
    static var secondaryText: CGColor { CGColor(
        srgbRed: 0.36,
        green: 0.36,
        blue: 0.40,
        alpha: 1
    ) }
    static var warning: CGColor { CGColor(
        srgbRed: 0.42,
        green: 0.21,
        blue: 0.02,
        alpha: 1
    ) }
    static var rule: CGColor { CGColor(
        srgbRed: 0.78,
        green: 0.79,
        blue: 0.84,
        alpha: 1
    ) }
}

private enum PDFReportFonts {
    static var header: CTFont {
        CTFontCreateWithName("Helvetica-Bold" as CFString, 16, nil)
    }
    static var title: CTFont {
        CTFontCreateWithName("Helvetica-Bold" as CFString, 22, nil)
    }
    static var subtitle: CTFont {
        CTFontCreateWithName("Helvetica" as CFString, 10, nil)
    }
    static var section: CTFont {
        CTFontCreateWithName("Helvetica-Bold" as CFString, 13, nil)
    }
    static var label: CTFont {
        CTFontCreateWithName("Helvetica-Bold" as CFString, 9.5, nil)
    }
    static var body: CTFont {
        CTFontCreateWithName("Helvetica" as CFString, 9.5, nil)
    }
    static var small: CTFont {
        CTFontCreateWithName("Helvetica" as CFString, 8.5, nil)
    }
    static var footer: CTFont {
        CTFontCreateWithName("Helvetica" as CFString, 7.5, nil)
    }
}

private enum PDFReportText {
    static func attributes(
        font: CTFont,
        color: CGColor
    ) -> [NSAttributedString.Key: Any] {
        [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
        ]
    }
}

private struct PDFReportContent {
    let snapshot: SavedCaseExportSnapshot

    func attributedString() -> NSAttributedString {
        let document = NSMutableAttributedString(string: "")
        let record = snapshot.calculation
        let input = record.input
        let request = record.request
        let response = record.response
        let model = response.model
        let solver = response.solver

        append(
            "Calculation report\n",
            to: document,
            font: PDFReportFonts.title,
            color: PDFReportPalette.primary
        )
        append(
            "\(snapshot.name)\n",
            to: document,
            font: PDFReportFonts.section,
            color: PDFReportPalette.bodyText
        )
        append(
            "Immutable saved calculation and scientific provenance\n\n",
            to: document,
            font: PDFReportFonts.subtitle,
            color: PDFReportPalette.secondaryText
        )

        section("Scientific status", in: document)
        if response.warnings.isEmpty {
            paragraph(
                "No provider warning was recorded with this calculation.",
                in: document,
                color: PDFReportPalette.secondaryText
            )
        } else {
            for warning in response.warnings {
                bullet(warning, in: document, color: PDFReportPalette.warning)
            }
        }
        paragraph(
            "Exporting this report does not validate the calculation. Preliminary, unavailable, outside-range, extrapolated and failed statuses retain their recorded meaning.",
            in: document,
            color: PDFReportPalette.warning
        )

        section("Saved case", in: document)
        row("Name", snapshot.name, in: document)
        row("Description", snapshot.notes.isEmpty ? "—" : snapshot.notes, in: document)
        row("Saved case ID", snapshot.savedCaseID.uuidString, in: document)
        row("Saved at", date(snapshot.savedAt), in: document)
        row("Last updated", date(snapshot.lastUpdatedAt), in: document)
        row("Report exported at", date(snapshot.exportedAt), in: document)

        section("Operating point", in: document)
        row(
            "Pressure — displayed",
            "\(number(input.pressureValue)) \(input.pressureDisplayUnitLabel)",
            in: document
        )
        row(
            "Pressure — SI",
            "\(number(input.pressurePa)) Pa",
            in: document
        )
        row(
            "Temperature — displayed",
            "\(number(input.temperatureValue)) \(input.temperatureUnit.rawValue)",
            in: document
        )
        row(
            "Temperature — SI",
            "\(number(input.temperatureK)) K",
            in: document
        )

        section("Composition as entered", in: document)
        for entry in input.originalComposition {
            row(
                "\(entry.component.symbol) — \(entry.component.name)",
                "\(number(entry.value)) \(compositionUnit(entry.unit))",
                in: document
            )
        }
        row(
            "Normalization explicitly used",
            input.normalizedComposition == nil ? "No" : "Yes",
            in: document
        )
        if let normalized = input.normalizedComposition {
            subsection("Normalized composition", in: document)
            for entry in normalized {
                row(
                    "\(entry.component.symbol) — \(entry.component.name)",
                    "\(number(entry.moleFraction * 100)) mol%",
                    in: document
                )
            }
        }

        subsection("Composition sent to provider", in: document)
        for entry in request.composition {
            row(
                "\(entry.component.symbol) — \(entry.component.name)",
                "\(number(entry.moleFraction * 100)) mol%",
                in: document
            )
        }

        section("Calculated results", in: document)
        row("Phase or region", phase(response.phase), in: document)
        row(
            "Recorded scientific-result flag",
            response.isScientificResult ? "Yes" : "No",
            in: document
        )
        for property in response.properties {
            let renderedValue: String
            if let value = property.value {
                renderedValue = property.unit.isEmpty
                    ? number(value)
                    : "\(number(value)) \(property.unit)"
            } else {
                renderedValue = "—"
            }
            row(
                propertyName(property.property),
                "\(renderedValue) [\(status(property.status))]",
                in: document
            )
            if let message = property.message, !message.isEmpty {
                paragraph(
                    "Status detail: \(message)",
                    in: document,
                    color: PDFReportPalette.secondaryText
                )
            }
        }

        section("Model and provider", in: document)
        row("Model", model.name, in: document)
        row("Model ID", model.id, in: document)
        row("Model version", model.modelVersion, in: document)
        row("Provider version", model.providerVersion, in: document)
        row("Coefficient/library version", model.coefficientSetVersion ?? "—", in: document)
        row("Availability at calculation", model.availability.rawValue, in: document)
        row("Execution", model.calculationMode.rawValue, in: document)
        row("Scientific basis", model.scientificBasis, in: document)
        row("Equation or method", model.equationOrMethod, in: document)
        row(
            "Recorded domain",
            "\(number(model.domain.minimumPressurePa / 100_000))–\(number(model.domain.maximumPressurePa / 100_000)) bar(a); \(number(model.domain.minimumTemperatureK - 273.15))–\(number(model.domain.maximumTemperatureK - 273.15)) °C",
            in: document
        )
        if !model.requiredResources.isEmpty {
            row("Required resources", model.requiredResources.joined(separator: ", "), in: document)
        }
        if !model.limitations.isEmpty {
            subsection("Recorded limitations", in: document)
            for limitation in model.limitations {
                bullet(limitation, in: document)
            }
        }

        section("Numerical execution", in: document)
        row("Method", solver.method, in: document)
        row("Converged", solver.converged ? "Yes" : "No", in: document)
        row(
            "Iterations",
            solver.iterationCount.map { String($0) } ?? "Not reported",
            in: document
        )
        row(
            "Absolute tolerance",
            solver.absoluteTolerance.map(number) ?? "Not reported",
            in: document
        )
        row(
            "Relative tolerance",
            solver.relativeTolerance.map(number) ?? "Not reported",
            in: document
        )
        row(
            "Duration",
            "\(number(solver.durationMilliseconds)) ms",
            in: document
        )

        section("Traceability", in: document)
        row("Calculation ID", response.calculationID.uuidString, in: document)
        row("Request ID", request.requestID.uuidString, in: document)
        row("Calculated at", date(response.calculatedAt), in: document)
        row("Requested model ID", request.modelID, in: document)
        row("Client version recorded in request", request.clientVersion, in: document)
        row(
            "Application version and build",
            "\(record.application.version) (\(record.application.build))",
            in: document
        )
        row("Export schema version", String(snapshot.schemaVersion), in: document)

        section("Scientific references", in: document)
        if model.references.isEmpty {
            paragraph("No reference was recorded.", in: document)
        } else {
            for reference in model.references {
                var citation = "\(reference.authors) (\(reference.year)). \(reference.title)."
                if let identifier = reference.doiOrURL, !identifier.isEmpty {
                    citation += " \(identifier)"
                }
                bullet(citation, in: document)
            }
        }

        section("Privacy and intended use", in: document)
        paragraph(
            "This PDF was generated locally from the saved calculation record. PhaseXpert sends no report data automatically. Data leaves the device only through a destination selected in the iOS share sheet.",
            in: document
        )
        paragraph(
            "PhaseXpert is a scientific calculation aid. Use only within the recorded model scope and validation status. Independent engineering review remains the responsibility of the user.",
            in: document,
            color: PDFReportPalette.warning
        )

        return document
    }

    private func section(_ title: String, in document: NSMutableAttributedString) {
        append(
            "\n\(title)\n",
            to: document,
            font: PDFReportFonts.section,
            color: PDFReportPalette.primary
        )
    }

    private func subsection(_ title: String, in document: NSMutableAttributedString) {
        append(
            "\n\(title)\n",
            to: document,
            font: PDFReportFonts.label,
            color: PDFReportPalette.primary
        )
    }

    private func row(
        _ label: String,
        _ value: String,
        in document: NSMutableAttributedString
    ) {
        append(
            "\(label): ",
            to: document,
            font: PDFReportFonts.label,
            color: PDFReportPalette.bodyText
        )
        append(
            "\(value)\n",
            to: document,
            font: PDFReportFonts.body,
            color: PDFReportPalette.bodyText
        )
    }

    private func bullet(
        _ value: String,
        in document: NSMutableAttributedString,
        color: CGColor = PDFReportPalette.bodyText
    ) {
        append(
            "• \(value)\n",
            to: document,
            font: PDFReportFonts.body,
            color: color
        )
    }

    private func paragraph(
        _ value: String,
        in document: NSMutableAttributedString,
        color: CGColor = PDFReportPalette.bodyText
    ) {
        append(
            "\(value)\n",
            to: document,
            font: PDFReportFonts.body,
            color: color
        )
    }

    private func append(
        _ value: String,
        to document: NSMutableAttributedString,
        font: CTFont,
        color: CGColor
    ) {
        document.append(
            NSAttributedString(
                string: value,
                attributes: PDFReportText.attributes(font: font, color: color)
            )
        )
    }

    private func number(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = " "
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 10
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private func date(_ value: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]
        return formatter.string(from: value)
    }

    private func pressureUnit(_ unit: PressureUnit) -> String {
        switch unit {
        case .bara: "bar(a)"
        case .barg: "bar gauge"
        default: unit.rawValue
        }
    }

    private func compositionUnit(_ unit: CompositionUnit) -> String {
        switch unit {
        case .molePercent: "mol%"
        case .partsPerMillion: "ppm"
        case .moleFraction: "mole fraction"
        case .massFraction: "mass fraction"
        }
    }

    private func phase(_ value: PhaseRegion) -> String {
        switch value {
        case .gas: "Gas"
        case .liquid: "Liquid"
        case .dense: "Dense phase"
        case .supercritical: "Supercritical"
        case .twoPhase: "Two phase"
        case .solid: "Solid"
        case .unknown: "Unknown"
        case .unavailable: "Unavailable"
        }
    }

    private func status(_ value: PropertyStatus) -> String {
        switch value {
        case .calculated: "Calculated"
        case .unavailable: "Unavailable"
        case .outsideValidatedRange: "Outside validated range"
        case .extrapolated: "Extrapolated"
        case .failed: "Calculation failed"
        }
    }

    private func propertyName(_ property: PropertyID) -> String {
        switch property {
        case .density: "Density"
        case .dynamicViscosity: "Dynamic viscosity"
        case .molarMass: "Molar mass"
        case .compressibilityFactor: "Compressibility factor, Z"
        case .specificVolume: "Specific volume"
        case .enthalpy: "Enthalpy"
        case .entropy: "Entropy"
        case .internalEnergy: "Internal energy"
        case .isobaricHeatCapacity: "Isobaric heat capacity, Cp"
        case .isochoricHeatCapacity: "Isochoric heat capacity, Cv"
        case .heatCapacityRatio: "Heat-capacity ratio, Cp/Cv"
        case .speedOfSound: "Speed of sound"
        case .thermalConductivity: "Thermal conductivity"
        case .jouleThomsonCoefficient: "Joule-Thomson coefficient"
        case .isothermalCompressibility: "Isothermal compressibility"
        case .thermalExpansionCoefficient: "Thermal expansion coefficient"
        case .vapourFraction: "Vapour fraction"
        }
    }
}

struct PDFComparisonExportRenderer {
    func render(_ snapshot: ComparisonExportSnapshot) throws -> Data {
        let comparison = CalculationComparison(
            reference: snapshot.reference.calculation,
            compared: snapshot.compared.calculation
        )
        let text = ReportingPDFText()
        text.title("Saved-case comparison report")
        text.paragraph("Compared case minus reference case. Numerical differences do not establish which model or result is more accurate.", color: PDFReportPalette.warning)
        text.section("Cases and immutable identifiers")
        text.comparisonRow("Saved case", snapshot.reference.name, snapshot.compared.name)
        text.comparisonRow("Saved case ID", snapshot.reference.savedCaseID.uuidString, snapshot.compared.savedCaseID.uuidString)
        text.comparisonRow("Calculation ID", comparison.reference.response.calculationID.uuidString, comparison.compared.response.calculationID.uuidString)
        text.comparisonRow("Request ID", comparison.reference.request.requestID.uuidString, comparison.compared.request.requestID.uuidString)
        text.comparisonRow("Calculated at", ReportingExportValidator.date(comparison.reference.response.calculatedAt), ReportingExportValidator.date(comparison.compared.response.calculatedAt))
        text.section("Operating point")
        text.differenceRow("Pressure", reference: comparison.reference.input.pressurePa / 100_000, compared: comparison.compared.input.pressurePa / 100_000, difference: comparison.pressureDifferenceBar, unit: "bar(a)")
        text.differenceRow("Temperature", reference: comparison.reference.input.temperatureK - 273.15, compared: comparison.compared.input.temperatureK - 273.15, difference: comparison.temperatureDifferenceCelsius, unit: "°C")
        text.section("Composition")
        text.comparisonRow("Mixture", ReportingExportValidator.composition(comparison.reference) + " mol%", ReportingExportValidator.composition(comparison.compared) + " mol%")
        text.row("Composition match", comparison.usesSameComposition ? "Same" : "Different")
        text.section("Model, provider and phase")
        text.comparisonRow("Model", comparison.reference.response.model.name, comparison.compared.response.model.name)
        text.comparisonRow("Model ID", comparison.reference.response.model.id, comparison.compared.response.model.id)
        text.comparisonRow("Model version", comparison.reference.response.model.modelVersion, comparison.compared.response.model.modelVersion)
        text.comparisonRow("Provider version", comparison.reference.response.model.providerVersion, comparison.compared.response.model.providerVersion)
        text.comparisonRow("Availability", comparison.reference.response.model.availability.rawValue, comparison.compared.response.model.availability.rawValue)
        text.comparisonRow("Phase", comparison.reference.response.phase.rawValue, comparison.compared.response.phase.rawValue)
        text.section("Properties")
        if comparison.properties.isEmpty {
            text.paragraph("No property records are available in either saved calculation.")
        }
        for property in comparison.properties {
            let unit = property.displayUnit ?? property.reference?.unit ?? property.compared?.unit ?? ""
            let reference = property.referenceDisplayValue.map(ReportingExportValidator.number) ?? "— [\(property.reference?.status.rawValue ?? "missing")]"
            let compared = property.comparedDisplayValue.map(ReportingExportValidator.number) ?? "— [\(property.compared?.status.rawValue ?? "missing")]"
            let difference = property.difference.map { ReportingExportValidator.number($0) + (unit.isEmpty ? "" : " \(unit)") } ?? "Not comparable"
            text.comparisonRow(property.id.displayName, reference + (property.referenceDisplayValue == nil || unit.isEmpty ? "" : " \(unit)"), compared + (property.comparedDisplayValue == nil || unit.isEmpty ? "" : " \(unit)"))
            text.row("Compared − reference", difference)
        }
        text.section("Recorded warnings")
        text.comparisonRow("Warnings", comparison.reference.response.warnings.isEmpty ? "None recorded" : comparison.reference.response.warnings.joined(separator: " | "), comparison.compared.response.warnings.isEmpty ? "None recorded" : comparison.compared.response.warnings.joined(separator: " | "))
        text.section("Saved notes")
        text.comparisonRow("Notes", snapshot.reference.notes.isEmpty ? "—" : snapshot.reference.notes, snapshot.compared.notes.isEmpty ? "—" : snapshot.compared.notes)
        text.section("Report traceability")
        text.row("Comparison schema version", String(snapshot.schemaVersion))
        text.row("Exported at", ReportingExportValidator.date(snapshot.exportedAt))
        text.paragraph("Both sides retain their recorded units, warnings, model/provider versions, solver metadata, provenance and identifiers. This report does not modify either saved case.")
        return try SearchablePDFReport.render(
            title: "PhaseXpert saved-case comparison",
            subject: "Compared-minus-reference saved calculation report",
            body: text.document
        )
    }
}

struct PDFPropertySweepExportRenderer {
    func render(_ snapshot: SweepReportSnapshot) throws -> Data {
        let result = snapshot.sweep
        let record = snapshot.sourceCalculation
        let text = ReportingPDFText()
        text.title("Property-sweep report")
        text.paragraph("Every plotted point is a successful provider calculation. Failed and unavailable points are retained as explicit gaps; no scientific value is interpolated.", color: PDFReportPalette.warning)
        text.section("Sweep definition")
        text.row("Sweep ID", result.id.uuidString)
        text.row("Source calculation ID", record.response.calculationID.uuidString)
        text.row("Source request ID", record.request.requestID.uuidString)
        text.row("Axis", result.request.axis.rawValue)
        text.row("Property", result.request.property.displayName)
        text.row("Start — SI", ReportingExportValidator.number(result.request.startValueSI))
        text.row("End — SI", ReportingExportValidator.number(result.request.endValueSI))
        text.row("Requested points", String(result.request.pointCount))
        text.row("Successful points", String(result.successfulSampleCount))
        text.row("Failed or unavailable points", String(result.failedSampleCount))
        text.row("Generated at", ReportingExportValidator.date(result.generatedAt))
        text.row("Duration", "\(ReportingExportValidator.number(result.durationMilliseconds)) ms")
        text.section("Fixed state and composition")
        text.row("Source pressure", "\(ReportingExportValidator.number(record.input.pressurePa / 100_000)) bar(a)")
        text.row("Source temperature", "\(ReportingExportValidator.number(record.input.temperatureK - 273.15)) °C")
        text.row("Composition", ReportingExportValidator.composition(record) + " mol%")
        text.section("Model and provider")
        text.row("Model", record.response.model.name)
        text.row("Model ID", record.response.model.id)
        text.row("Model version", record.response.model.modelVersion)
        text.row("Provider version", record.response.model.providerVersion)
        text.row("Availability", record.response.model.availability.rawValue)
        text.row("Scientific basis", record.response.model.scientificBasis)
        text.section("Samples")
        for sample in result.samples {
            let property = sample.value(for: result.request.property)
            let display = property.flatMap(EngineeringPropertyFormatter.measurement)
            let status = property?.status.rawValue ?? (sample.errorMessage == nil ? "unavailable" : "failed")
            let value = display.map { "\(ReportingExportValidator.number($0.value)) \($0.unit)" } ?? "—"
            text.row(
                "Point \(sample.index)",
                "\(ReportingExportValidator.number(sample.pressurePa / 100_000)) bar(a); \(ReportingExportValidator.number(sample.temperatureK - 273.15)) °C; \(status); \(value)"
            )
            if let calculationID = sample.response?.calculationID {
                text.row("Point \(sample.index) calculation ID", calculationID.uuidString)
            }
            let detail = sample.errorMessage ?? property?.message ?? sample.response?.warnings.joined(separator: " | ")
            if let detail, !detail.isEmpty { text.paragraph("Point \(sample.index) detail: \(detail)", color: PDFReportPalette.secondaryText) }
        }
        text.section("Source warnings and report traceability")
        if record.response.warnings.isEmpty {
            text.paragraph("No warning was recorded with the source calculation.")
        } else {
            record.response.warnings.forEach { text.bullet($0, color: PDFReportPalette.warning) }
        }
        text.row("Sweep report schema version", String(snapshot.schemaVersion))
        text.row("Exported at", ReportingExportValidator.date(snapshot.exportedAt))
        return try SearchablePDFReport.render(
            title: "PhaseXpert property-sweep report",
            subject: "Provider-calculated property sweep and provenance",
            body: text.document
        ) { context, pageNumber in
            try drawChart(snapshot, in: context, pageNumber: pageNumber)
        }
    }

    private func drawChart(
        _ snapshot: SweepReportSnapshot,
        in context: CGContext,
        pageNumber: Int
    ) throws {
        let result = snapshot.sweep
        let samples: [(index: Int, x: Double, y: Double, phase: PhaseRegion)] = result.samples.compactMap { sample in
            guard let property = sample.value(for: result.request.property),
                  property.hasFiniteCalculatedValue,
                  let measurement = EngineeringPropertyFormatter.measurement(for: property),
                  measurement.value.isFinite
            else { return nil }
            return (
                sample.index,
                result.request.axis == .pressure ? sample.pressurePa / 100_000 : sample.temperatureK - 273.15,
                measurement.value,
                sample.response?.phase ?? .unknown
            )
        }
        PDFReportingCanvas.beginPage(context, pageNumber: pageNumber, title: "Property-sweep chart")
        guard let xMin = samples.map(\.x).min(), let xMax = samples.map(\.x).max(),
              let yMin = samples.map(\.y).min(), let yMax = samples.map(\.y).max()
        else {
            PDFReportingCanvas.line("Property-sweep chart unavailable", font: PDFReportFonts.section, color: PDFReportPalette.primary, at: CGPoint(x: 82, y: 716), in: context)
            PDFReportingCanvas.line("No finite calculated provider points were returned. Every requested point remains recorded as a failed or unavailable gap.", font: PDFReportFonts.body, color: PDFReportPalette.warning, at: CGPoint(x: 82, y: 688), in: context)
            PDFReportingCanvas.line("Sweep ID: \(result.id.uuidString)", font: PDFReportFonts.small, color: PDFReportPalette.secondaryText, at: CGPoint(x: 82, y: 660), in: context)
            PDFReportingCanvas.endPage(context, pageNumber: pageNumber)
            return
        }
        // Reserve a dedicated left gutter for y-axis values and separate bands
        // below the plot for x-axis values and the axis title.
        let plot = CGRect(x: 112, y: 250, width: 420, height: 420)
        context.setStrokeColor(PDFReportPalette.bodyText)
        context.setLineWidth(1)
        let xSpan = max(xMax - xMin, max(abs(xMin), 1) * 1e-9)
        let ySpan = max(yMax - yMin, max(abs(yMin), 1) * 1e-9)
        func point(_ sample: (index: Int, x: Double, y: Double, phase: PhaseRegion)) -> CGPoint {
            CGPoint(x: plot.minX + CGFloat((sample.x - xMin) / xSpan) * plot.width,
                    y: plot.minY + CGFloat((sample.y - yMin) / ySpan) * plot.height)
        }
        let xUnit = result.request.axis == .pressure ? "bar(a)" : "°C"
        let yUnit = result.samples.compactMap { $0.value(for: result.request.property) }.compactMap(EngineeringPropertyFormatter.measurement).first?.unit ?? ""
        let tickCount = 5
        for index in 0..<tickCount {
            let fraction = Double(index) / Double(tickCount - 1)
            let xValue = xMin + xSpan * fraction
            let x = plot.minX + CGFloat(fraction) * plot.width
            let yValue = yMin + ySpan * fraction
            let y = plot.minY + CGFloat(fraction) * plot.height

            context.setStrokeColor(PDFReportPalette.rule)
            context.setLineWidth(0.45)
            context.move(to: CGPoint(x: x, y: plot.minY))
            context.addLine(to: CGPoint(x: x, y: plot.maxY))
            context.move(to: CGPoint(x: plot.minX, y: y))
            context.addLine(to: CGPoint(x: plot.maxX, y: y))
            context.strokePath()

            PDFReportingCanvas.centeredLine(
                tickNumber(xValue),
                font: PDFReportFonts.small,
                color: PDFReportPalette.secondaryText,
                centerX: x,
                y: plot.minY - 18,
                in: context
            )
            PDFReportingCanvas.rightAlignedLine(
                tickNumber(yValue),
                font: PDFReportFonts.small,
                color: PDFReportPalette.secondaryText,
                rightX: plot.minX - 8,
                y: y - 3,
                in: context
            )
        }
        context.setStrokeColor(PDFReportPalette.bodyText)
        context.setLineWidth(1)
        context.stroke(plot)

        var previous: (index: Int, x: Double, y: Double, phase: PhaseRegion)?
        context.setStrokeColor(PDFReportPalette.primary)
        context.setLineWidth(1.6)
        for sample in samples {
            let p = point(sample)
            if let previous, sample.index == previous.index + 1 {
                context.move(to: point(previous))
                context.addLine(to: p)
                context.strokePath()
            }
            context.setFillColor(sample.phase == .twoPhase ? PDFReportPalette.warning : PDFReportPalette.primary)
            context.fillEllipse(in: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5))
            previous = sample
        }

        PDFReportingCanvas.line("\(result.request.property.displayName) vs \(result.request.axis.rawValue)", font: PDFReportFonts.section, color: PDFReportPalette.primary, at: CGPoint(x: plot.minX, y: 722), in: context)
        PDFReportingCanvas.line("Y: \(result.request.property.displayName) (\(yUnit))", font: PDFReportFonts.body, color: PDFReportPalette.bodyText, at: CGPoint(x: plot.minX, y: 697), in: context)
        PDFReportingCanvas.centeredLine("X: \(result.request.axis.rawValue.capitalized) (\(xUnit))", font: PDFReportFonts.body, color: PDFReportPalette.bodyText, centerX: plot.midX, y: 211, in: context)
        PDFReportingCanvas.line("Legend: ● successful provider point", font: PDFReportFonts.small, color: PDFReportPalette.secondaryText, at: CGPoint(x: plot.minX, y: 184), in: context)
        PDFReportingCanvas.line("● two-phase provider point   gaps = failed/unavailable", font: PDFReportFonts.small, color: PDFReportPalette.secondaryText, at: CGPoint(x: plot.minX, y: 168), in: context)
        PDFReportingCanvas.line("Straight lines connect adjacent successful calculations for visualization only; no scientific value is interpolated.", font: PDFReportFonts.small, color: PDFReportPalette.warning, at: CGPoint(x: plot.minX, y: 146), in: context)
        PDFReportingCanvas.line("Sweep ID: \(result.id.uuidString)", font: PDFReportFonts.small, color: PDFReportPalette.secondaryText, at: CGPoint(x: plot.minX, y: 122), in: context)
        PDFReportingCanvas.line("Source calculation ID: \(snapshot.sourceCalculation.response.calculationID.uuidString)", font: PDFReportFonts.small, color: PDFReportPalette.secondaryText, at: CGPoint(x: plot.minX, y: 106), in: context)
        PDFReportingCanvas.endPage(context, pageNumber: pageNumber)
    }

    private func tickNumber(_ value: Double) -> String {
        value.formatted(
            .number
                .locale(Locale(identifier: "en_US_POSIX"))
                .grouping(.never)
                .precision(.significantDigits(1...6))
        )
    }
}

private enum SearchablePDFReport {
    static func render(
        title: String,
        subject: String,
        body: NSAttributedString,
        extraPage: ((CGContext, Int) throws -> Void)? = nil
    ) throws -> Data {
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output as CFMutableData) else {
            throw CalculationExportError.pdfRenderingFailed("PhaseXpert could not create a PDF data consumer.")
        }
        var mediaBox = PDFReportLayout.pageRect
        let metadata = [
            kCGPDFContextTitle as String: title,
            kCGPDFContextAuthor as String: "IFE Flow Technology Department",
            kCGPDFContextCreator as String: "PhaseXpert",
            kCGPDFContextSubject as String: subject
        ] as CFDictionary
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, metadata) else {
            throw CalculationExportError.pdfRenderingFailed("PhaseXpert could not create the PDF graphics context.")
        }
        let framesetter = CTFramesetterCreateWithAttributedString(body)
        var location = 0
        var page = 0
        repeat {
            page += 1
            PDFReportingCanvas.beginPage(context, pageNumber: page, title: title)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), CGPath(rect: PDFReportLayout.contentRect, transform: nil), nil)
            CTFrameDraw(frame, context)
            let visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0 else {
                context.endPDFPage(); context.closePDF()
                throw CalculationExportError.pdfRenderingFailed("PhaseXpert could not paginate the report content.")
            }
            location += visible.length
            PDFReportingCanvas.endPage(context, pageNumber: page)
        } while location < body.length
        if let extraPage {
            page += 1
            try extraPage(context, page)
        }
        context.closePDF()
        return output as Data
    }
}

private enum PDFReportingCanvas {
    static func beginPage(_ context: CGContext, pageNumber: Int, title: String) {
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(PDFReportLayout.pageRect)
        context.setFillColor(PDFReportPalette.primary)
        context.fill(CGRect(x: 0, y: PDFReportLayout.pageRect.maxY - 18, width: PDFReportLayout.pageRect.width, height: 18))
        line(pageNumber == 1 ? "PhaseXpert" : title, font: PDFReportFonts.header, color: PDFReportPalette.primary, at: CGPoint(x: PDFReportLayout.margin, y: 800), in: context)
        line("Developed by the IFE Flow Technology Department", font: PDFReportFonts.small, color: PDFReportPalette.secondaryText, at: CGPoint(x: PDFReportLayout.margin, y: 784), in: context)
        if let logo = UIImage(named: "IFELogoEnglish")?.cgImage {
            let bounds = PDFReportLayout.logoBounds
            let aspect = CGFloat(logo.width) / CGFloat(logo.height)
            let width = min(bounds.width, bounds.height * aspect)
            context.draw(logo, in: CGRect(x: bounds.maxX - width, y: bounds.midY - width / aspect / 2, width: width, height: width / aspect))
        }
        context.setStrokeColor(PDFReportPalette.rule)
        context.move(to: CGPoint(x: PDFReportLayout.margin, y: 776))
        context.addLine(to: CGPoint(x: PDFReportLayout.pageRect.maxX - PDFReportLayout.margin, y: 776))
        context.strokePath()
    }

    static func endPage(_ context: CGContext, pageNumber: Int) {
        context.setStrokeColor(PDFReportPalette.rule)
        context.move(to: CGPoint(x: PDFReportLayout.margin, y: 48))
        context.addLine(to: CGPoint(x: PDFReportLayout.pageRect.maxX - PDFReportLayout.margin, y: 48))
        context.strokePath()
        line("Generated locally by PhaseXpert • Page \(pageNumber)", font: PDFReportFonts.footer, color: PDFReportPalette.secondaryText, at: CGPoint(x: PDFReportLayout.margin, y: 31), in: context)
        context.endPDFPage()
    }

    static func line(_ text: String, font: CTFont, color: CGColor, at point: CGPoint, in context: CGContext) {
        let value = NSAttributedString(string: text, attributes: PDFReportText.attributes(font: font, color: color))
        context.textPosition = point
        CTLineDraw(CTLineCreateWithAttributedString(value), context)
    }

    static func centeredLine(
        _ text: String,
        font: CTFont,
        color: CGColor,
        centerX: CGFloat,
        y: CGFloat,
        in context: CGContext
    ) {
        let value = NSAttributedString(string: text, attributes: PDFReportText.attributes(font: font, color: color))
        let line = CTLineCreateWithAttributedString(value)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        context.textPosition = CGPoint(x: centerX - width / 2, y: y)
        CTLineDraw(line, context)
    }

    static func rightAlignedLine(
        _ text: String,
        font: CTFont,
        color: CGColor,
        rightX: CGFloat,
        y: CGFloat,
        in context: CGContext
    ) {
        let value = NSAttributedString(string: text, attributes: PDFReportText.attributes(font: font, color: color))
        let line = CTLineCreateWithAttributedString(value)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        context.textPosition = CGPoint(x: rightX - width, y: y)
        CTLineDraw(line, context)
    }
}

private final class ReportingPDFText {
    let document = NSMutableAttributedString(string: "")
    func title(_ value: String) { append(value + "\n\n", font: PDFReportFonts.title, color: PDFReportPalette.primary) }
    func section(_ value: String) { append("\n" + value + "\n", font: PDFReportFonts.section, color: PDFReportPalette.primary) }
    func row(_ label: String, _ value: String) {
        append(label + ": ", font: PDFReportFonts.label, color: PDFReportPalette.bodyText)
        append(value + "\n", font: PDFReportFonts.body, color: PDFReportPalette.bodyText)
    }
    func comparisonRow(_ label: String, _ reference: String, _ compared: String) {
        append(label + "\n", font: PDFReportFonts.label, color: PDFReportPalette.bodyText)
        append("Reference: " + reference + "\nCompared: " + compared + "\n", font: PDFReportFonts.body, color: PDFReportPalette.bodyText)
    }
    func differenceRow(_ label: String, reference: Double, compared: Double, difference: Double, unit: String) {
        comparisonRow(label, ReportingExportValidator.number(reference) + " " + unit, ReportingExportValidator.number(compared) + " " + unit)
        row("Compared − reference", ReportingExportValidator.number(difference) + " " + unit)
    }
    func paragraph(_ value: String, color: CGColor = PDFReportPalette.bodyText) { append(value + "\n", font: PDFReportFonts.body, color: color) }
    func bullet(_ value: String, color: CGColor = PDFReportPalette.bodyText) { append("• " + value + "\n", font: PDFReportFonts.body, color: color) }
    private func append(_ value: String, font: CTFont, color: CGColor) {
        document.append(NSAttributedString(string: value, attributes: PDFReportText.attributes(font: font, color: color)))
    }
}
