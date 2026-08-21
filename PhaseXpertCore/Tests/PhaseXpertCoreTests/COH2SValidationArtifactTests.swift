import Foundation
import XCTest

final class COH2SValidationArtifactTests: XCTestCase {
    func testNazeriDensityArtifactHasCompleteTraceableProductionBlock() throws {
        let artifact = try object("Nazeri2016CO2H2SDensityValidation")
        let source = try XCTUnwrap(artifact["source"] as? [String: Any])
        let metrics = try XCTUnwrap(artifact["metrics"] as? [String: Any])
        let rows = try XCTUnwrap(artifact["rows"] as? [[String: Any]])
        let decision = try XCTUnwrap(artifact["productionDecision"] as? [String: Any])

        XCTAssertEqual(source["doi"] as? String, "10.1016/j.fluid.2016.04.024")
        XCTAssertEqual(source["thermoMLMD5"] as? String, "486a1b58bdcf853469edca32630200af")
        XCTAssertEqual(metrics["rows"] as? Int, 450)
        XCTAssertEqual(metrics["converged"] as? Int, 450)
        XCTAssertEqual(rows.count, 450)
        XCTAssertEqual(Set(rows.compactMap { $0["rowID"] as? String }).count, 450)
        XCTAssertEqual(decision["decision"] as? String, "promoted")
        XCTAssertEqual((decision["includedRows"] as? [String])?.count, 19)
        XCTAssertEqual(decision["minimumPressurePa"] as? Int, 301_000)
        XCTAssertEqual(decision["maximumPressurePa"] as? Int, 3_196_000)
    }

    func testVLEArtifactKeepsCOAndH2SResearchOnlyWithoutHidingFailures() throws {
        let artifact = try object("AdvancedCCSCOH2SVLEValidation")
        let sources = try XCTUnwrap(artifact["sources"] as? [[String: Any]])
        XCTAssertEqual(sources.count, 4)
        XCTAssertEqual(Set(sources.compactMap { $0["doi"] as? String }), [
            "10.1016/j.fluid.2018.05.006",
            "10.1016/j.jct.2018.06.022",
            "10.1016/j.jct.2020.106180",
            "10.1016/j.fluid.2013.07.050"
        ])
        XCTAssertTrue(sources.allSatisfy { ($0["decision"] as? String) == "rejected" })
        XCTAssertTrue(sources.allSatisfy { source in
            guard let metrics = source["bubbleMetrics"] as? [String: Any],
                  let rows = metrics["rows"] as? Int,
                  let converged = metrics["converged"] as? Int else { return false }
            return rows > 0 && converged <= rows
        })
    }

    private func object(_ name: String) throws -> [String: Any] {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: repositoryRoot
            .appendingPathComponent("Documentation/Validation/\(name).json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
