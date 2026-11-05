import PDFKit
import PhaseXpertCore
import XCTest
@testable import PhaseXpert

@MainActor
final class PhaseMapPDFReportTests: XCTestCase {
    private let composition = [
        MixtureComponent(component: .carbonDioxide, moleFraction: 0.95),
        MixtureComponent(component: .nitrogen, moleFraction: 0.05)
    ]

    /// Synthetic classifications laid out as liquid / narrow multiphase band / gas.
    /// This exercises the report layout only; it is not thermodynamic data.
    private func syntheticResult(resolution: PhaseMapResolution) throws -> PhaseMapResult {
        let provider = CoolPropProvider(engine: NativeCoolPropEngine())
        let pressurePa = 16_000_000.0
        let temperatureK = 248.15
        let request = PhaseMapRequest(
            modelID: provider.descriptor.id,
            pressurePa: pressurePa,
            temperatureK: temperatureK,
            composition: composition,
            range: .automatic(pressurePa: pressurePa, temperatureK: temperatureK),
            resolution: resolution,
            clientVersion: "report-layout-test"
        )
        let range = request.range
        let evaluations = try PhaseMapGridBuilder.points(for: request).map { point -> PhaseMapEvaluation in
            let pressureFraction = (point.pressurePa - range.pressureMinimumPa)
                / (range.pressureMaximumPa - range.pressureMinimumPa)
            let temperatureFraction = (point.temperatureK - range.temperatureMinimumK)
                / (range.temperatureMaximumK - range.temperatureMinimumK)
            let offset = temperatureFraction - pressureFraction * 0.6 - 0.2
            let region: PhaseRegion = abs(offset) < 0.05 ? .twoPhase : (offset < 0 ? .liquid : .gas)
            return PhaseMapEvaluation(
                point: point,
                classification: PhaseMapClassificationAdapter.map(region),
                solver: nil
            )
        }
        return PhaseMapResult(
            request: request,
            model: provider.descriptor,
            evaluations: evaluations,
            warnings: ["Phase Map classifies discrete provider flash points only; it is not a phase envelope."]
        )
    }

    private func writeAndOpen(_ result: PhaseMapResult) throws -> PDFDocument {
        let artifacts = try PhaseMapPDFExporter().writeTemporaryPDF(
            result: result,
            pressureUnit: .barAbsolute,
            temperatureUnit: .celsius,
            application: ApplicationIdentity(version: "1.2.2", build: "3")
        )
        let url = try XCTUnwrap(artifacts.files.first)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return try XCTUnwrap(PDFDocument(url: url))
    }

    func testDiscreteReportIsOneA4LandscapePageWithCaseInformationAndLegend() throws {
        let document = try writeAndOpen(syntheticResult(resolution: .ten))
        XCTAssertEqual(document.pageCount, 1)
        let bounds = try XCTUnwrap(document.page(at: 0)).bounds(for: .mediaBox)
        XCTAssertEqual(bounds.width, 842, accuracy: 0.5)
        XCTAssertEqual(bounds.height, 595, accuracy: 0.5)

        let text = document.string ?? ""
        for expected in ["Legend", "Composition", "CO₂ 95 mol%", "N₂ 5 mol%", "Operating point", "bar(a)", "Request ID"] {
            XCTAssertTrue(text.contains(expected), "Missing “\(expected)” in report text")
        }
    }

    func testUltraReportDescribesRegionsAndBoundaries() throws {
        let document = try writeAndOpen(syntheticResult(resolution: .hundred))
        XCTAssertEqual(document.pageCount, 1)
        let text = document.string ?? ""
        XCTAssertTrue(text.contains("Classification boundary"))
        XCTAssertTrue(text.contains("100 × 100"))
    }
}
