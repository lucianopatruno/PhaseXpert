import CoreGraphics
import CoreText
import Foundation
import PhaseXpertCore

/// Printable, provider-independent rendering of an immutable saved calculation.
///
/// Core Graphics and Core Text are used instead of screen capture so the PDF
/// remains searchable, paginates long records and is independent of appearance.
struct PDFCalculationExportRenderer: CalculationExportRendering {
    let format = CalculationExportFormat.pdf

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

        context.closePDF()
        return output as Data
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
    ) }
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
            "\(number(input.pressureValue)) \(pressureUnit(input.pressureUnit))",
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
            "\(number(model.domain.minimumPressurePa / 100_000))–\(number(model.domain.maximumPressurePa / 100_000)) bar abs; \(number(model.domain.minimumTemperatureK - 273.15))–\(number(model.domain.maximumTemperatureK - 273.15)) °C",
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
            solver.iterationCount.map(String.init) ?? "Not reported",
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
        case .bara: "bar abs"
        case .barg: "bar gauge"
        default: unit.rawValue
        }
    }

    private func compositionUnit(_ unit: CompositionUnit) -> String {
        switch unit {
        case .molePercent: "mol%"
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
