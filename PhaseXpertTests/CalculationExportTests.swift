import Foundation
import PDFKit
import PhaseXpertCore
import XCTest
@testable import PhaseXpert

@MainActor
final class CalculationExportTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_800_000_000.125)
    private let caseID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let calculationID = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!

    func testJSONExportRoundTripsCompleteVersionedSnapshot() throws {
        let snapshot = makeSnapshot()
        let data = try CalculationExporter().data(for: snapshot, format: .json)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let decoded = try decoder.decode(SavedCaseExportSnapshot.self, from: data)

        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.schemaVersion, SavedCaseExportSnapshot.currentSchemaVersion)
        XCTAssertEqual(decoded.calculation.response.model.providerVersion, "export-test-provider")
        XCTAssertEqual(decoded.calculation.response.warnings, ["PRELIMINARY — validation pending."])
    }

    func testCSVExportContainsUnitsStatusesWarningsAndRFC4180Escaping() throws {
        let data = try CalculationExporter().data(for: makeSnapshot(), format: .csv)

        XCTAssertEqual(Array(data.prefix(3)), [0xEF, 0xBB, 0xBF])
        let text = String(decoding: data.dropFirst(3), as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("\"section\",\"key\",\"index\""))
        XCTAssertTrue(text.contains("\"display_input\",\"pressure\""))
        XCTAssertTrue(text.contains("\"150.0\",\"bara\""))
        XCTAssertTrue(text.contains("\"property\",\"result\",\"0\",\"density\",\"903.5\",\"kg/m³\",\"calculated\""))
        XCTAssertTrue(text.contains("PRELIMINARY — validation pending."))
        XCTAssertTrue(text.contains("\"He said \"\"check\"\"\nsecond line\""))
        XCTAssertTrue(text.contains("\"model_reference\",\"reference\""))
        XCTAssertTrue(text.contains("\"solver\",\"duration\""))
        XCTAssertTrue(text.hasSuffix("\r\n"))
    }

    func testPDFReportIsSearchableAndContainsRecordedProvenance() throws {
        let data = try CalculationExporter().data(for: makeSnapshot(), format: .pdf)

        XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "%PDF")
        let document = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThanOrEqual(document.pageCount, 1)
        let text = (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")

        XCTAssertTrue(text.contains("PhaseXpert"))
        XCTAssertTrue(text.contains("IFE Flow Technology Department"))
        XCTAssertTrue(text.contains("Pipeline inlet"))
        XCTAssertTrue(text.contains("150 bar abs"))
        XCTAssertTrue(text.contains("Density"))
        XCTAssertTrue(text.contains("903.5 kg/m³"))
        XCTAssertTrue(text.contains("PRELIMINARY — validation pending."))
        XCTAssertTrue(text.contains("export-test-provider"))
        XCTAssertTrue(text.contains(calculationID.uuidString))
        XCTAssertTrue(text.contains("Test Reference"))
    }

    func testPDFReportPaginatesLongSavedCaseNotes() throws {
        let longNotes = Array(
            repeating: "Long traceable engineering note retained in the report.",
            count: 300
        ).joined(separator: " ")
        let data = try CalculationExporter().data(
            for: makeSnapshot(notes: longNotes),
            format: .pdf
        )
        let document = try XCTUnwrap(PDFDocument(data: data))

        XCTAssertGreaterThan(document.pageCount, 1)
        XCTAssertTrue(
            document.page(at: document.pageCount - 1)?
                .string?
                .contains("Independent engineering review") == true
        )
    }

    func testNonFinitePropertyStopsEveryExportFormat() {
        let snapshot = makeSnapshot(propertyValue: .nan)
        let exporter = CalculationExporter()

        for format in CalculationExportFormat.allCases {
            XCTAssertThrowsError(try exporter.data(for: snapshot, format: format)) { error in
                XCTAssertEqual(
                    error as? CalculationExportError,
                    .nonFiniteValue("property density")
                )
            }
        }
    }

    func testFilenameIsSanitizedAndRetainsStableCalculationIdentifier() {
        let snapshot = makeSnapshot(name: "  Pipeline / inlet?  ")
        let exporter = CalculationExporter()

        XCTAssertEqual(
            exporter.filename(for: snapshot, format: .json),
            "PhaseXpert-Pipeline-inlet-12345678.json"
        )
        XCTAssertEqual(
            exporter.filename(for: snapshot, format: .csv),
            "PhaseXpert-Pipeline-inlet-12345678.csv"
        )
        XCTAssertEqual(
            exporter.filename(for: snapshot, format: .pdf),
            "PhaseXpert-Pipeline-inlet-12345678.pdf"
        )
    }

    func testFileStoreCreatesAllArtifactsWithMatchingContents() throws {
        let testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhaseXpertExportTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: testDirectory) }
        let snapshot = makeSnapshot()
        let exporter = CalculationExporter()

        let artifacts = try CalculationExportFileStore(
            baseDirectory: testDirectory
        ).createArtifacts(for: snapshot, exporter: exporter)

        XCTAssertEqual(Set(artifacts.map(\.format)), Set(CalculationExportFormat.allCases))
        for artifact in artifacts {
            XCTAssertTrue(FileManager.default.fileExists(atPath: artifact.fileURL.path))
            let storedData = try Data(contentsOf: artifact.fileURL)
            if artifact.format == .pdf {
                XCTAssertNotNil(PDFDocument(data: storedData))
            } else {
                XCTAssertEqual(
                    storedData,
                    try exporter.data(for: snapshot, format: artifact.format)
                )
            }
        }
    }

    private func makeSnapshot(
        name: String = "Pipeline inlet",
        notes: String = "He said \"check\"\nsecond line",
        propertyValue: Double = 903.5
    ) -> SavedCaseExportSnapshot {
        let requestID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let model = ModelDescriptor(
            id: "export-test",
            name: "Export Test — Preliminary",
            modelVersion: "1.2.3",
            providerVersion: "export-test-provider",
            availability: .preliminary,
            calculationMode: .local,
            supportedComponents: [.carbonDioxide],
            supportedProperties: [.density],
            domain: .initialCO2Transport,
            scientificBasis: "Deterministic test model only.",
            equationOrMethod: "No scientific calculation.",
            coefficientSetVersion: "test-coefficients",
            requiredResources: ["test-resource"],
            limitations: ["Not a scientific result."],
            references: [
                .init(
                    authors: "Test Author",
                    title: "Test Reference",
                    year: 2026,
                    doiOrURL: "https://example.invalid/reference"
                )
            ]
        )
        let request = CalculationRequest(
            requestID: requestID,
            modelID: model.id,
            pressurePa: 15_000_000,
            temperatureK: 293.15,
            composition: [.init(component: .carbonDioxide, moleFraction: 1)],
            requestedProperties: [.density],
            clientVersion: "0.1.0 (1)"
        )
        let response = CalculationResponse(
            calculationID: calculationID,
            requestID: requestID,
            model: model,
            calculatedAt: fixedDate,
            phase: .dense,
            properties: [
                .init(
                    property: .density,
                    value: propertyValue,
                    unit: "kg/m³",
                    status: .calculated
                ),
                .init(
                    property: .enthalpy,
                    value: nil,
                    unit: "",
                    status: .unavailable,
                    message: "Not supported"
                )
            ],
            solver: .init(
                method: "Deterministic test solver",
                converged: true,
                iterationCount: 4,
                absoluteTolerance: 1e-9,
                relativeTolerance: 1e-8,
                durationMilliseconds: 2.5
            ),
            warnings: ["PRELIMINARY — validation pending."],
            isScientificResult: false
        )
        let record = CalculationRecord(
            request: request,
            input: .init(
                pressureValue: 150,
                pressureUnit: .bara,
                pressurePa: request.pressurePa,
                temperatureValue: 20,
                temperatureUnit: .celsius,
                temperatureK: request.temperatureK,
                originalComposition: [
                    .init(component: .carbonDioxide, value: 99.99, unit: .molePercent)
                ],
                normalizedComposition: [
                    .init(component: .carbonDioxide, moleFraction: 1)
                ]
            ),
            response: response,
            application: .init(version: "0.1.0", build: "1")
        )
        return SavedCaseExportSnapshot(
            exportedAt: fixedDate,
            savedCaseID: caseID,
            name: name,
            notes: notes,
            savedAt: fixedDate,
            lastUpdatedAt: fixedDate,
            calculation: record
        )
    }
}
