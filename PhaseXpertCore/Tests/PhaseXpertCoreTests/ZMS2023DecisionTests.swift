import Foundation
import XCTest

final class ZMS2023DecisionTests: XCTestCase {
    func testPublishedIdentityIsLockedAndIncomplete() throws {
        let identity = try json("Documentation/Validation/ZMS2023ModelIdentity.json")
        let publication = try XCTUnwrap(identity["publication"] as? [String: Any])
        XCTAssertEqual(publication["authors"] as? [String], ["Jia Zhang", "Shide Mao", "Zeming Shi"])
        XCTAssertEqual(publication["doi"] as? String, "10.3390/app13063659")
        XCTAssertEqual(publication["license"] as? String, "CC BY 4.0")

        let formulation = try XCTUnwrap(identity["publishedFormulation"] as? [String: Any])
        XCTAssertEqual(formulation["publishedPairCoefficientCount"] as? Int, 12)
        XCTAssertEqual(formulation["referencedUniversalDepartureTermCount"] as? Int, 10)
        XCTAssertEqual(formulation["referencedUniversalDepartureCoefficientCount"] as? Int, 30)
        XCTAssertEqual(formulation["ternarySpecificTerms"] as? Int, 0)
        XCTAssertEqual(identity["identityComplete"] as? Bool, false)
        XCTAssertEqual(identity["implementationAllowed"] as? Bool, false)

        let pairs = try XCTUnwrap(identity["binaryParameters"] as? [[String: Any]])
        XCTAssertEqual(pairs.count, 3)
        XCTAssertEqual(pairs.map { [$0["first"] as? String, $0["second"] as? String] }, [
            ["CH4", "CO2"], ["CO2", "N2"], ["CH4", "N2"]
        ])
        XCTAssertEqual(pairs.compactMap { $0["F"] as? Double }, [1.2844025, 1.6671494, 0.63739997])

        let critical = try XCTUnwrap(identity["publishedCriticalTable"] as? [[String: Any]])
        XCTAssertEqual(critical.compactMap { $0["printedTciK"] as? Double }, [90.6941, 216.592, 63.151])
        XCTAssertGreaterThan((identity["identityBlockers"] as? [String])?.count ?? 0, 3)
    }

    func testNoMetricsOrProductionCapabilityAreInvented() throws {
        let results = try json("Documentation/Validation/ZMS2023ValidationResults.json")
        let implementation = try XCTUnwrap(results["implementation"] as? [String: Any])
        XCTAssertEqual(implementation["created"] as? Bool, false)
        XCTAssertEqual(implementation["iosNativeChanges"] as? Bool, false)
        XCTAssertEqual(implementation["xcframeworkRebuilt"] as? Bool, false)
        XCTAssertEqual(implementation["multiModelRoutingImplemented"] as? Bool, false)
        XCTAssertEqual(results["baselineUnchanged"] as? Bool, true)
        XCTAssertEqual(results["productionPromotion"] as? Bool, false)

        let metrics = try XCTUnwrap(results["zmsMetrics"] as? [String: Any])
        XCTAssertTrue(metrics.values.allSatisfy { $0 is NSNull })
        let fitting = try XCTUnwrap(results["fittingDataAudit"] as? [String: Any])
        let methaneNitrogen = try XCTUnwrap(fitting["ch4N2"] as? [String: Any])
        XCTAssertEqual(methaneNitrogen["pvtxSelectedRows"] as? Int, 433)
        XCTAssertEqual(methaneNitrogen["vleSelectedRows"] as? Int, 270)
    }

    private func json(_ path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: repositoryRoot().appendingPathComponent(path))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func repositoryRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        return url
    }
}
