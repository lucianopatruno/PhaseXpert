import Foundation
import XCTest

final class AdvancedDensityContinuousDomainDecisionTests: XCTestCase {
    func testDecisionArtifactKeepsEveryInvestigatedGateConservative() throws {
        let url = repositoryRoot()
            .appendingPathComponent("Documentation/Validation/AdvancedDensityContinuousDomains2026-08-28.json")
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        let model = try XCTUnwrap(object["model"] as? [String: Any])
        XCTAssertEqual(model["version"] as? String, "0.23.1")
        XCTAssertEqual(
            model["commit"] as? String,
            "a68eb9cabf47af2c4aba0d272ac10fbca4c10eca"
        )
        XCTAssertEqual(model["parametersFittedInThisAudit"] as? Bool, false)
        XCTAssertEqual(model["nativeABIChanged"] as? Bool, false)

        let systems = try XCTUnwrap(object["systems"] as? [[String: Any]])
        XCTAssertEqual(Set(systems.compactMap { $0["system"] as? String }), [
            "CO2+N2", "CO2+CH4", "CO2+H2", "dryMulticomponent"
        ])
        for system in systems {
            XCTAssertEqual(system["status"] as? String, "KEEP EXISTING EXACT/DISCRETE GATE")
            XCTAssertEqual(system["supersedesPreviousGate"] as? Bool, false)
            let properties = try XCTUnwrap(system["acceptedProperties"] as? [String])
            XCTAssertEqual(Set(properties), [
                "density", "molarMass", "specificVolume", "compressibilityFactor"
            ])
            XCTAssertFalse((system["reason"] as? String ?? "").isEmpty)
        }
    }

    private func repositoryRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        return url
    }
}
