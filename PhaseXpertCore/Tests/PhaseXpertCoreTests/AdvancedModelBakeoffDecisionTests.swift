import Foundation
import XCTest

final class AdvancedModelBakeoffDecisionTests: XCTestCase {
    func testBakeoffIdentityAndNegativeDecisionRemainAuditable() throws {
        let data = try Data(contentsOf: repositoryRoot()
            .appendingPathComponent("Documentation/Validation/AdvancedModelBakeoff2026-08-28.json"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let baseline = try XCTUnwrap(object["baselineModel"] as? [String: Any])
        XCTAssertEqual(baseline["engineCommit"] as? String, "a68eb9cabf47af2c4aba0d272ac10fbca4c10eca")
        XCTAssertEqual(baseline["productionUnchanged"] as? Bool, true)

        let candidates = try XCTUnwrap(object["candidateModels"] as? [[String: Any]])
        XCTAssertEqual(candidates.count, 8)
        XCTAssertEqual(Set(candidates.compactMap { $0["candidateID"] as? String }).count, 8)
        XCTAssertTrue(candidates.allSatisfy {
            ["REJECT", "PROMISING — NEEDS MORE DATA"].contains($0["status"] as? String)
        })
        XCTAssertTrue(candidates.allSatisfy {
            guard let identity = $0["identity"] as? [String: Any] else { return false }
            return identity["family"] is String
        })

        let decision = try XCTUnwrap(object["productionDecision"] as? [String: Any])
        XCTAssertEqual(decision["status"] as? String, "RETAIN CURRENT FORMULATION")
        XCTAssertEqual(decision["promotedCandidates"] as? [String], [])
        XCTAssertEqual(decision["acceptedDomains"] as? [String], [])
        XCTAssertEqual(decision["multiModelRoutingImplemented"] as? Bool, false)
        XCTAssertEqual(decision["capabilityMatrixChanged"] as? Bool, false)
        XCTAssertEqual(decision["providerRoutingChanged"] as? Bool, false)

        let native = try XCTUnwrap(object["nativeImpact"] as? [String: Any])
        XCTAssertEqual(native["abiChanged"] as? Bool, false)
        XCTAssertEqual(native["nativeSourceChanged"] as? Bool, false)
        XCTAssertEqual(native["teqpXCFrameworkRebuilt"] as? Bool, false)
        XCTAssertEqual(native["coolPropChanged"] as? Bool, false)
    }

    private func repositoryRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        return url
    }
}
