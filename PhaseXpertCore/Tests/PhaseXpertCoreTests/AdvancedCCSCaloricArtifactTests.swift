import Foundation
import XCTest

final class AdvancedCCSCaloricArtifactTests: XCTestCase {
    func testCaloricDecisionArtifactSeparatesCalculationValidationAndProduction() throws {
        let artifact = try json(named: "AdvancedCCSCaloricProperties2026-08-24.json")
        let implementation = try XCTUnwrap(artifact["implementation"] as? [String: Any])
        XCTAssertEqual(implementation["arbitraryN"] as? Bool, true)
        XCTAssertEqual(implementation["status"] as? String, "calculable_research_only")
        let validation = try XCTUnwrap(artifact["experimentalValidation"] as? [String: Any])
        for property in ["cp", "cv", "gamma", "enthalpyOrDeltaH", "multicomponent"] {
            let result = try XCTUnwrap(validation[property] as? [String: Any])
            XCTAssertEqual(result["rows"] as? Int, 0)
            XCTAssertTrue(result["metrics"] is NSNull)
        }
        let decisions = try XCTUnwrap(artifact["productionDecisions"] as? [String: Any])
        XCTAssertEqual((decisions["newProductionGates"] as? [Any])?.count, 0)
    }

    func testCaloricAcquisitionAuditHasNoSyntheticOrDigitizedRows() throws {
        let artifact = try json(named: "AdvancedCCSCaloricDataAcquisitionAudit2026-08-24.json")
        XCTAssertEqual(artifact["exactExperimentalRowsAcquired"] as? Int, 0)
        XCTAssertEqual(artifact["graphDigitizationUsed"] as? Bool, false)
        XCTAssertEqual(artifact["modelGeneratedRowsUsedAsTruth"] as? Bool, false)
        let candidates = try XCTUnwrap(artifact["candidates"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(candidates.count, 7)
        XCTAssertEqual(Set(candidates.compactMap { $0["doi"] as? String }).count, 6)
    }

    private func json(named name: String) throws -> [String: Any] {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repositoryRoot
            .appendingPathComponent("Documentation/Validation")
            .appendingPathComponent(name)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
    }
}
