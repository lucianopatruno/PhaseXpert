import Foundation
import XCTest

final class MulticomponentDensityArtifactTests: XCTestCase {
    private struct Artifact: Decodable {
        let rowCount: Int
        let rows: [Row]
        let source: Source

        enum CodingKeys: String, CodingKey {
            case rowCount = "row_count"
            case rows, source
        }
    }

    private struct Source: Decodable {
        let articleDOI: String
        let datasetDOI: String

        enum CodingKeys: String, CodingKey {
            case articleDOI = "article_doi"
            case datasetDOI = "dataset_doi"
        }
    }

    private struct Row: Decodable {
        let id: String
        let composition: [String: Double]
        let pressurePa: Double
        let pressureMPa: Double

        enum CodingKeys: String, CodingKey {
            case id
            case composition = "composition_mole_fraction"
            case pressurePa = "pressure_pa"
            case pressureMPa = "pressure_mpa"
        }
    }

    func testRazmjooArtifactMetadataAndUnitsAreInternallyConsistent() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repositoryRoot.appendingPathComponent(
            "Documentation/Validation/Razmjoo2026MulticomponentDensity.json"
        )
        let artifact = try JSONDecoder().decode(Artifact.self, from: Data(contentsOf: url))
        XCTAssertEqual(artifact.rowCount, 330)
        XCTAssertEqual(artifact.rows.count, 330)
        XCTAssertEqual(Set(artifact.rows.map(\.id)).count, 330)
        XCTAssertEqual(artifact.source.articleDOI, "10.1016/j.fuel.2026.139184")
        XCTAssertEqual(artifact.source.datasetDOI, "10.5281/zenodo.15846367")
        for row in artifact.rows {
            XCTAssertEqual(row.composition.values.reduce(0, +), 1, accuracy: 1e-12, row.id)
            XCTAssertEqual(row.pressurePa, row.pressureMPa * 1_000_000, accuracy: 1e-6, row.id)
        }
    }
}
