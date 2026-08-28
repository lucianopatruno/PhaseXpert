import Foundation
import XCTest

final class AdvancedMulticomponentPhaseProductionDecisionTests: XCTestCase {
    func testDecisionArtifactPreservesResearchOnlyBoundary() throws {
        let data = try Data(contentsOf: repositoryRoot()
            .appendingPathComponent("Documentation/Validation/AdvancedMulticomponentPhaseProduction2026-08-28.json"))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let model = try XCTUnwrap(object["model"] as? [String: Any])
        XCTAssertEqual(model["version"] as? String, "0.23.1")
        XCTAssertEqual(
            model["commit"] as? String,
            "a68eb9cabf47af2c4aba0d272ac10fbca4c10eca"
        )
        XCTAssertEqual(model["parametersFitted"] as? Bool, false)
        XCTAssertEqual(model["binaryInteractionParametersChanged"] as? Bool, false)
        XCTAssertEqual(model["nativeABIChanged"] as? Bool, false)
        XCTAssertEqual(model["xcframeworkRebuilt"] as? Bool, false)

        let production = try XCTUnwrap(object["productionChanges"] as? [String: Any])
        XCTAssertEqual(production["promotedDomains"] as? [String], [])
        for key in [
            "capabilityMatrixChanged", "providerRoutingChanged",
            "phaseClassificationChanged", "phaseEnvelopeChanged",
            "phaseDiagramChanged", "uiChanged"
        ] {
            XCTAssertEqual(production[key] as? Bool, false, key)
        }

        let decisions = try XCTUnwrap(object["systemDecisions"] as? [[String: Any]])
        XCTAssertEqual(decisions.count, 8)
        XCTAssertTrue(decisions.allSatisfy {
            (($0["decisions"] as? [String]) ?? []).contains("NO PROMOTION")
        })
        XCTAssertTrue(decisions.allSatisfy {
            !(($0["reason"] as? String) ?? "").isEmpty
        })
    }

    private func repositoryRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        return url
    }
}
