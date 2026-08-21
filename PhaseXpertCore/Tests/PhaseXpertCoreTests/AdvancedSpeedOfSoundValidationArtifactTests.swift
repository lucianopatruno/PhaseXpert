import Foundation
import XCTest

final class AdvancedSpeedOfSoundValidationArtifactTests: XCTestCase {
    func testAlSiyabiArtifactPreservesEveryExtractedAcousticRow() throws {
        let artifact = try object("AlSiyabi2013AdvancedSpeedOfSoundValidation")
        let rows = try XCTUnwrap(artifact["rows"] as? [[String: Any]])
        XCTAssertEqual(rows.count, 300)
        XCTAssertEqual(Set(rows.compactMap { $0["rowID"] as? String }).count, 300)
        let expectedCounts = ["N2": 60, "CH4": 61, "H2": 57, "O2": 62, "MIXb": 60]
        for (system, count) in expectedCounts {
            XCTAssertEqual(rows.filter { $0["system"] as? String == system }.count, count)
            XCTAssertTrue(rows.filter { $0["system"] as? String == system }.allSatisfy {
                (($0["prediction"] as? [String: Any])?["converged"] as? Bool) == true
            })
        }
    }

    func testPromotedAcousticBlockIsContiguousAndUncertaintyTraceable() throws {
        let artifact = try object("AlSiyabi2013AdvancedSpeedOfSoundValidation")
        let source = try XCTUnwrap(artifact["source"] as? [String: Any])
        let candidates = try XCTUnwrap(artifact["candidateBlocks"] as? [[String: Any]])
        let promoted = try XCTUnwrap(candidates.first)
        let metrics = try XCTUnwrap(promoted["metrics"] as? [String: Any])
        XCTAssertEqual(source["reportedSpeedOfSoundAccuracyMetresPerSecond"] as? Int, 1)
        XCTAssertEqual(promoted["decision"] as? String, "promoted")
        XCTAssertEqual((promoted["includedRows"] as? [String])?.count, 6)
        XCTAssertEqual(promoted["minimumPressurePa"] as? Int, 24_120_000)
        XCTAssertEqual(promoted["maximumPressurePa"] as? Int, 40_830_000)
        XCTAssertEqual(metrics["converged"] as? Int, 6)
        XCTAssertEqual(
            try XCTUnwrap(metrics["MAEMetresPerSecond"] as? Double),
            0.5385729664132176,
            accuracy: 1e-12
        )
        XCTAssertEqual(
            try XCTUnwrap(metrics["RMSMetresPerSecond"] as? Double),
            0.639985399710561,
            accuracy: 1e-12
        )
        XCTAssertEqual(promoted["immediateExcludedLowerPressureRow"] as? String, "alsiyabi2013-o2-044")
    }

    private func object(_ name: String) throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent(
            "Documentation/Validation/\(name).json"
        ))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
