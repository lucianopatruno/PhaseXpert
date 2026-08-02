import Foundation
import PhaseXpertCore

enum CalculationExportFormat: String, CaseIterable, Hashable, Identifiable, Sendable {
    case json
    case csv
    case pdf

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .json: "JSON"
        case .csv: "CSV"
        case .pdf: "PDF Report"
        }
    }

    var fileExtension: String { rawValue }
}

/// Versioned export payload. The calculation record is embedded rather than
/// reconstructed so its original provider provenance survives later updates.
struct SavedCaseExportSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let exportedAt: Date
    let savedCaseID: UUID
    let name: String
    let notes: String
    let savedAt: Date
    let lastUpdatedAt: Date
    let calculation: CalculationRecord

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        exportedAt: Date = Date(),
        savedCaseID: UUID,
        name: String,
        notes: String,
        savedAt: Date,
        lastUpdatedAt: Date,
        calculation: CalculationRecord
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.savedCaseID = savedCaseID
        self.name = name
        self.notes = notes
        self.savedAt = savedAt
        self.lastUpdatedAt = lastUpdatedAt
        self.calculation = calculation
    }
}

struct CalculationExportArtifact: Identifiable, Sendable {
    var id: CalculationExportFormat { format }
    let format: CalculationExportFormat
    let fileURL: URL
}

enum CalculationExportError: LocalizedError, Equatable {
    case nonFiniteValue(String)
    case textEncodingFailed
    case noStoredCalculation
    case pdfRenderingFailed(String)

    var errorDescription: String? {
        switch self {
        case let .nonFiniteValue(field):
            "Export stopped because \(field) contains a non-finite value. The stored calculation was not changed."
        case .textEncodingFailed:
            "PhaseXpert could not encode the export as UTF-8."
        case .noStoredCalculation:
            "The stored calculation record could not be decoded, so no export was created."
        case let .pdfRenderingFailed(message):
            message
        }
    }
}

protocol CalculationExportRendering: Sendable {
    var format: CalculationExportFormat { get }
    func render(_ snapshot: SavedCaseExportSnapshot) throws -> Data
}

struct CalculationExporter: Sendable {
    func data(
        for snapshot: SavedCaseExportSnapshot,
        format: CalculationExportFormat,
        phaseDiagram: PhaseDiagramReportAttachment? = nil
    ) throws -> Data {
        try validateFiniteValues(in: snapshot)
        switch format {
        case .json:
            return try JSONCalculationExportRenderer().render(snapshot)
        case .csv:
            return try CSVCalculationExportRenderer().render(snapshot)
        case .pdf:
            return try PDFCalculationExportRenderer(phaseDiagram: phaseDiagram).render(snapshot)
        }
    }

    func filename(
        for snapshot: SavedCaseExportSnapshot,
        format: CalculationExportFormat
    ) -> String {
        let safeName = sanitizedFilenameComponent(snapshot.name)
        let calculationID = snapshot.calculation.response.calculationID.uuidString
            .prefix(8)
            .lowercased()
        return "PhaseXpert-\(safeName)-\(calculationID).\(format.fileExtension)"
    }

    private func validateFiniteValues(in snapshot: SavedCaseExportSnapshot) throws {
        let record = snapshot.calculation
        let scalarValues: [(String, Double)] = [
            ("displayed pressure", record.input.pressureValue),
            ("SI pressure", record.input.pressurePa),
            ("displayed temperature", record.input.temperatureValue),
            ("SI temperature", record.input.temperatureK),
            ("request pressure", record.request.pressurePa),
            ("request temperature", record.request.temperatureK),
            ("solver duration", record.response.solver.durationMilliseconds),
            ("minimum model pressure", record.response.model.domain.minimumPressurePa),
            ("maximum model pressure", record.response.model.domain.maximumPressurePa),
            ("minimum model temperature", record.response.model.domain.minimumTemperatureK),
            ("maximum model temperature", record.response.model.domain.maximumTemperatureK)
        ]
        for (field, value) in scalarValues where !value.isFinite {
            throw CalculationExportError.nonFiniteValue(field)
        }

        for entry in record.input.originalComposition where !entry.value.isFinite {
            throw CalculationExportError.nonFiniteValue(
                "original composition for \(entry.component.symbol)"
            )
        }
        for entry in record.input.normalizedComposition ?? [] where !entry.moleFraction.isFinite {
            throw CalculationExportError.nonFiniteValue(
                "normalized composition for \(entry.component.symbol)"
            )
        }
        for entry in record.request.composition where !entry.moleFraction.isFinite {
            throw CalculationExportError.nonFiniteValue(
                "calculation composition for \(entry.component.symbol)"
            )
        }
        for property in record.response.properties {
            if let value = property.value, !value.isFinite {
                throw CalculationExportError.nonFiniteValue(
                    "property \(property.property.rawValue)"
                )
            }
        }
        if let value = record.response.solver.absoluteTolerance, !value.isFinite {
            throw CalculationExportError.nonFiniteValue("absolute solver tolerance")
        }
        if let value = record.response.solver.relativeTolerance, !value.isFinite {
            throw CalculationExportError.nonFiniteValue("relative solver tolerance")
        }
    }

    private func sanitizedFilenameComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics
        var result = ""
        var previousWasSeparator = false

        for scalar in value.unicodeScalars {
            if allowed.contains(scalar) {
                result.unicodeScalars.append(scalar)
                previousWasSeparator = false
            } else if !previousWasSeparator, !result.isEmpty {
                result.append("-")
                previousWasSeparator = true
            }
        }

        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let limited = String(trimmed.prefix(64))
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return limited.isEmpty ? "Saved-Case" : limited
    }
}

struct CalculationExportFileStore {
    private let baseDirectory: URL
    private let fileManager: FileManager

    init(
        baseDirectory: URL = FileManager.default.temporaryDirectory,
        fileManager: FileManager = .default
    ) {
        self.baseDirectory = baseDirectory
        self.fileManager = fileManager
    }

    func createArtifacts(
        for snapshot: SavedCaseExportSnapshot,
        exporter: CalculationExporter = CalculationExporter(),
        phaseDiagram: PhaseDiagramReportAttachment? = nil
    ) throws -> [CalculationExportArtifact] {
        let exportDirectory = baseDirectory
            .appendingPathComponent("PhaseXpertExports", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(
            at: exportDirectory,
            withIntermediateDirectories: true
        )

        do {
            return try CalculationExportFormat.allCases.map { format in
                let url = exportDirectory.appendingPathComponent(
                    exporter.filename(for: snapshot, format: format),
                    isDirectory: false
                )
                let data = try exporter.data(
                    for: snapshot,
                    format: format,
                    phaseDiagram: format == .pdf ? phaseDiagram : nil
                )
                try data.write(to: url, options: .atomic)
                return CalculationExportArtifact(format: format, fileURL: url)
            }
        } catch {
            try? fileManager.removeItem(at: exportDirectory)
            throw error
        }
    }
}

private struct JSONCalculationExportRenderer: CalculationExportRendering {
    let format = CalculationExportFormat.json

    func render(_ snapshot: SavedCaseExportSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(snapshot)
    }
}

private struct CSVCalculationExportRenderer: CalculationExportRendering {
    struct Row {
        let section: String
        let key: String
        var index = ""
        var identifier = ""
        var value = ""
        var unit = ""
        var status = ""
        var message = ""

        var fields: [String] {
            [section, key, index, identifier, value, unit, status, message]
        }
    }

    let format = CalculationExportFormat.csv

    func render(_ snapshot: SavedCaseExportSnapshot) throws -> Data {
        var rows = makeRows(snapshot)
        rows.insert(
            Row(
                section: "section",
                key: "key",
                index: "index",
                identifier: "identifier",
                value: "value",
                unit: "unit",
                status: "status",
                message: "message"
            ),
            at: 0
        )

        let text = rows
            .map { $0.fields.map(escape).joined(separator: ",") }
            .joined(separator: "\r\n") + "\r\n"
        guard let encoded = text.data(using: .utf8) else {
            throw CalculationExportError.textEncodingFailed
        }
        // The BOM keeps symbols such as CO₂, °C and Pa·s intact in spreadsheet
        // software that otherwise guesses a legacy text encoding.
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(encoded)
        return data
    }

    private func makeRows(_ snapshot: SavedCaseExportSnapshot) -> [Row] {
        let record = snapshot.calculation
        let request = record.request
        let input = record.input
        let response = record.response
        let model = response.model
        let solver = response.solver
        var rows: [Row] = []

        func append(
            _ section: String,
            _ key: String,
            index: Int? = nil,
            identifier: String = "",
            value: String = "",
            unit: String = "",
            status: String = "",
            message: String = ""
        ) {
            rows.append(Row(
                section: section,
                key: key,
                index: index.map { String($0) } ?? "",
                identifier: identifier,
                value: value,
                unit: unit,
                status: status,
                message: message
            ))
        }

        append("export", "schema_version", value: String(snapshot.schemaVersion))
        append("export", "exported_at", value: date(snapshot.exportedAt))
        append("saved_case", "id", value: snapshot.savedCaseID.uuidString)
        append("saved_case", "name", value: snapshot.name)
        append("saved_case", "notes", value: snapshot.notes)
        append("saved_case", "saved_at", value: date(snapshot.savedAt))
        append("saved_case", "last_updated_at", value: date(snapshot.lastUpdatedAt))

        append("request", "request_id", value: request.requestID.uuidString)
        append("request", "model_id", value: request.modelID)
        append("request", "client_version", value: request.clientVersion)
        append("request", "pressure", value: number(request.pressurePa), unit: "Pa")
        append("request", "temperature", value: number(request.temperatureK), unit: "K")
        for (index, property) in request.requestedProperties
            .sorted(by: { $0.rawValue < $1.rawValue })
            .enumerated()
        {
            append(
                "request",
                "requested_property",
                index: index,
                identifier: property.rawValue
            )
        }
        for (index, component) in request.composition.enumerated() {
            append(
                "calculation_composition",
                "mole_fraction",
                index: index,
                identifier: component.component.rawValue,
                value: number(component.moleFraction),
                unit: "mol/mol",
                message: component.component.symbol
            )
        }

        append(
            "display_input",
            "pressure",
            value: number(input.pressureValue),
            unit: input.pressureUnit.rawValue
        )
        append("si_input", "pressure", value: number(input.pressurePa), unit: "Pa")
        append(
            "display_input",
            "temperature",
            value: number(input.temperatureValue),
            unit: input.temperatureUnit.rawValue
        )
        append("si_input", "temperature", value: number(input.temperatureK), unit: "K")
        for (index, component) in input.originalComposition.enumerated() {
            append(
                "original_composition",
                "value",
                index: index,
                identifier: component.component.rawValue,
                value: number(component.value),
                unit: component.unit.rawValue,
                message: component.component.symbol
            )
        }
        append(
            "normalization",
            "applied",
            value: input.normalizedComposition == nil ? "false" : "true"
        )
        for (index, component) in (input.normalizedComposition ?? []).enumerated() {
            append(
                "normalized_composition",
                "mole_fraction",
                index: index,
                identifier: component.component.rawValue,
                value: number(component.moleFraction),
                unit: "mol/mol",
                message: component.component.symbol
            )
        }

        append("result", "calculation_id", value: response.calculationID.uuidString)
        append("result", "calculated_at", value: date(response.calculatedAt))
        append("result", "phase", value: response.phase.rawValue)
        append("result", "scientific_result", value: String(response.isScientificResult))
        for (index, property) in response.properties
            .sorted(by: { $0.property.rawValue < $1.property.rawValue })
            .enumerated()
        {
            append(
                "property",
                "result",
                index: index,
                identifier: property.property.rawValue,
                value: property.value.map { number($0) } ?? "",
                unit: property.unit,
                status: property.status.rawValue,
                message: property.message ?? ""
            )
        }
        for (index, warning) in response.warnings.enumerated() {
            append("warning", "message", index: index, message: warning)
        }

        append("model", "id", value: model.id)
        append("model", "name", value: model.name)
        append("model", "model_version", value: model.modelVersion)
        append("model", "provider_version", value: model.providerVersion)
        append("model", "availability", value: model.availability.rawValue)
        append("model", "calculation_mode", value: model.calculationMode.rawValue)
        append("model", "scientific_basis", message: model.scientificBasis)
        append("model", "equation_or_method", message: model.equationOrMethod)
        append("model", "coefficient_set_version", value: model.coefficientSetVersion ?? "")
        append("model_domain", "minimum_pressure", value: number(model.domain.minimumPressurePa), unit: "Pa")
        append("model_domain", "maximum_pressure", value: number(model.domain.maximumPressurePa), unit: "Pa")
        append("model_domain", "minimum_temperature", value: number(model.domain.minimumTemperatureK), unit: "K")
        append("model_domain", "maximum_temperature", value: number(model.domain.maximumTemperatureK), unit: "K")
        for (index, component) in model.supportedComponents
            .sorted(by: { $0.rawValue < $1.rawValue })
            .enumerated()
        {
            append("model", "supported_component", index: index, identifier: component.rawValue, message: component.symbol)
        }
        for (index, property) in model.supportedProperties
            .sorted(by: { $0.rawValue < $1.rawValue })
            .enumerated()
        {
            append("model", "supported_property", index: index, identifier: property.rawValue)
        }
        for (index, resource) in model.requiredResources.enumerated() {
            append("model", "required_resource", index: index, value: resource)
        }
        for (index, limitation) in model.limitations.enumerated() {
            append("model", "limitation", index: index, message: limitation)
        }
        for (index, reference) in model.references.enumerated() {
            append(
                "model_reference",
                "reference",
                index: index,
                identifier: reference.doiOrURL ?? "",
                value: String(reference.year),
                message: "\(reference.authors): \(reference.title)"
            )
        }

        append("solver", "method", message: solver.method)
        append("solver", "converged", value: String(solver.converged))
        append("solver", "iteration_count", value: solver.iterationCount.map { String($0) } ?? "")
        append("solver", "absolute_tolerance", value: solver.absoluteTolerance.map { number($0) } ?? "")
        append("solver", "relative_tolerance", value: solver.relativeTolerance.map { number($0) } ?? "")
        append("solver", "duration", value: number(solver.durationMilliseconds), unit: "ms")
        append("application", "version", value: record.application.version)
        append("application", "build", value: record.application.build)
        return rows
    }

    private func escape(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private func number(_ value: Double) -> String {
        String(value)
    }

    private func date(_ value: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: value)
    }
}

struct ComparisonExportSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let exportedAt: Date
    let reference: SavedCaseExportSnapshot
    let compared: SavedCaseExportSnapshot

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        exportedAt: Date = Date(),
        reference: SavedCaseExportSnapshot,
        compared: SavedCaseExportSnapshot
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.reference = reference
        self.compared = compared
    }
}

struct SweepReportSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let exportedAt: Date
    let sourceCalculation: CalculationRecord
    let sweep: PropertySweepResult

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        exportedAt: Date = Date(),
        sourceCalculation: CalculationRecord,
        sweep: PropertySweepResult
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.sourceCalculation = sourceCalculation
        self.sweep = sweep
    }
}

enum ReportingArtifactKind: String, Identifiable, Sendable {
    case comparisonCSV
    case comparisonPDF
    case sweepPDF

    var id: String { rawValue }
}

struct ReportingExportArtifact: Identifiable, Sendable {
    let id: ReportingArtifactKind
    let fileURL: URL
}

struct ComparisonReportExporter: Sendable {
    func csvData(for snapshot: ComparisonExportSnapshot) throws -> Data {
        try ReportingExportValidator.validate(snapshot.reference.calculation)
        try ReportingExportValidator.validate(snapshot.compared.calculation)
        let comparison = CalculationComparison(
            reference: snapshot.reference.calculation,
            compared: snapshot.compared.calculation
        )
        var rows: [[String]] = [
            ["PhaseXpert saved-case comparison"],
            ["schema_version", String(snapshot.schemaVersion)],
            ["exported_at", ReportingExportValidator.date(snapshot.exportedAt)],
            ["difference_semantics", "compared minus reference"],
            ["accuracy_statement", "Numerical differences do not establish which model or result is more accurate."],
            [],
            ["field", "reference", "compared", "difference", "unit", "reference_status", "compared_status"]
        ]
        rows.append(["saved_case_id", snapshot.reference.savedCaseID.uuidString, snapshot.compared.savedCaseID.uuidString, "", "", "", ""])
        rows.append(["saved_case_name", snapshot.reference.name, snapshot.compared.name, "", "", "", ""])
        rows.append(["calculation_id", comparison.reference.response.calculationID.uuidString, comparison.compared.response.calculationID.uuidString, "", "", "", ""])
        rows.append(["request_id", comparison.reference.request.requestID.uuidString, comparison.compared.request.requestID.uuidString, "", "", "", ""])
        rows.append(["pressure", ReportingExportValidator.number(comparison.reference.input.pressurePa / 100_000), ReportingExportValidator.number(comparison.compared.input.pressurePa / 100_000), ReportingExportValidator.number(comparison.pressureDifferenceBar), "bar(a)", "calculated", "calculated"])
        rows.append(["temperature", ReportingExportValidator.number(comparison.reference.input.temperatureK - 273.15), ReportingExportValidator.number(comparison.compared.input.temperatureK - 273.15), ReportingExportValidator.number(comparison.temperatureDifferenceCelsius), "°C", "calculated", "calculated"])
        rows.append(["model_id", comparison.reference.response.model.id, comparison.compared.response.model.id, "", "", "", ""])
        rows.append(["model_version", comparison.reference.response.model.modelVersion, comparison.compared.response.model.modelVersion, "", "", "", ""])
        rows.append(["provider_version", comparison.reference.response.model.providerVersion, comparison.compared.response.model.providerVersion, "", "", "", ""])
        rows.append(["phase", comparison.reference.response.phase.rawValue, comparison.compared.response.phase.rawValue, "", "", "", ""])
        rows.append(["composition", ReportingExportValidator.composition(comparison.reference), ReportingExportValidator.composition(comparison.compared), "", "mol%", "", ""])
        rows.append(["warnings", comparison.reference.response.warnings.joined(separator: " | "), comparison.compared.response.warnings.joined(separator: " | "), "", "", "", ""])
        for property in comparison.properties {
            let referenceValue = property.referenceDisplayValue.map(ReportingExportValidator.number) ?? ""
            let comparedValue = property.comparedDisplayValue.map(ReportingExportValidator.number) ?? ""
            rows.append([
                "property:\(property.id.rawValue)", referenceValue, comparedValue,
                property.difference.map(ReportingExportValidator.number) ?? "",
                property.displayUnit ?? property.reference?.unit ?? property.compared?.unit ?? "",
                property.reference?.status.rawValue ?? "missing",
                property.compared?.status.rawValue ?? "missing"
            ])
        }
        rows.append(["reference_notes", snapshot.reference.notes, "", "", "", "", ""])
        rows.append(["compared_notes", "", snapshot.compared.notes, "", "", "", ""])
        return try ReportingExportValidator.csvData(rows)
    }

    func pdfData(for snapshot: ComparisonExportSnapshot) throws -> Data {
        try ReportingExportValidator.validate(snapshot.reference.calculation)
        try ReportingExportValidator.validate(snapshot.compared.calculation)
        return try PDFComparisonExportRenderer().render(snapshot)
    }

    func createArtifacts(
        for snapshot: ComparisonExportSnapshot,
        baseDirectory: URL = FileManager.default.temporaryDirectory
    ) throws -> [ReportingExportArtifact] {
        let directory = baseDirectory.appendingPathComponent("PhaseXpertComparison-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stem = "PhaseXpert-Comparison-\(snapshot.reference.calculation.response.calculationID.uuidString.prefix(8))-\(snapshot.compared.calculation.response.calculationID.uuidString.prefix(8))"
        let csvURL = directory.appendingPathComponent(stem + ".csv")
        let pdfURL = directory.appendingPathComponent(stem + ".pdf")
        do {
            try csvData(for: snapshot).write(to: csvURL, options: .atomic)
            try pdfData(for: snapshot).write(to: pdfURL, options: .atomic)
            return [
                ReportingExportArtifact(id: .comparisonCSV, fileURL: csvURL),
                ReportingExportArtifact(id: .comparisonPDF, fileURL: pdfURL)
            ]
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}

struct SweepReportExporter: Sendable {
    func pdfData(for snapshot: SweepReportSnapshot) throws -> Data {
        try ReportingExportValidator.validate(snapshot.sourceCalculation)
        try ReportingExportValidator.validate(snapshot.sweep)
        return try PDFPropertySweepExportRenderer().render(snapshot)
    }

    func writeTemporaryPDF(for snapshot: SweepReportSnapshot) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "PhaseXpert-Sweep-\(snapshot.sweep.id.uuidString).pdf"
        )
        try pdfData(for: snapshot).write(to: url, options: .atomic)
        return url
    }
}

enum ReportingExportValidator {
    static func validate(_ record: CalculationRecord) throws {
        let values = [
            record.input.pressureValue, record.input.pressurePa,
            record.input.temperatureValue, record.input.temperatureK,
            record.request.pressurePa, record.request.temperatureK,
            record.response.solver.durationMilliseconds,
            record.response.model.domain.minimumPressurePa,
            record.response.model.domain.maximumPressurePa,
            record.response.model.domain.minimumTemperatureK,
            record.response.model.domain.maximumTemperatureK
        ]
        guard values.allSatisfy(\.isFinite) else {
            throw CalculationExportError.nonFiniteValue("comparison or sweep source calculation")
        }
        for property in record.response.properties where property.value?.isFinite == false {
            throw CalculationExportError.nonFiniteValue("property \(property.property.rawValue)")
        }
        guard record.request.composition.allSatisfy({ $0.moleFraction.isFinite }) else {
            throw CalculationExportError.nonFiniteValue("calculation composition")
        }
    }

    static func validate(_ result: PropertySweepResult) throws {
        guard result.durationMilliseconds.isFinite,
              result.request.startValueSI.isFinite,
              result.request.endValueSI.isFinite
        else { throw CalculationExportError.nonFiniteValue("sweep metadata") }
        for sample in result.samples {
            guard sample.pressurePa.isFinite, sample.temperatureK.isFinite else {
                throw CalculationExportError.nonFiniteValue("sweep operating point \(sample.index)")
            }
            if let value = sample.value(for: result.request.property)?.value,
               !value.isFinite {
                throw CalculationExportError.nonFiniteValue("sweep property at point \(sample.index)")
            }
        }
    }

    static func csvData(_ rows: [[String]]) throws -> Data {
        let quote = "\u{0022}"
        let text = rows.map { row in
            row.map { value in quote + value.replacingOccurrences(of: quote, with: quote + quote) + quote }
                .joined(separator: ",")
        }.joined(separator: "\r\n") + "\r\n"
        guard let encoded = text.data(using: .utf8) else {
            throw CalculationExportError.textEncodingFailed
        }
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(encoded)
        return data
    }

    static func number(_ value: Double) -> String { String(value) }

    static func date(_ value: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: value)
    }

    static func composition(_ record: CalculationRecord) -> String {
        record.request.composition.map {
            "\($0.component.symbol) \(number($0.moleFraction * 100))"
        }.joined(separator: "; ")
    }
}
