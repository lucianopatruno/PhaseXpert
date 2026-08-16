import XCTest

final class CCSMixtureExpansionEvidenceTests: XCTestCase {
    func testMethaneExpansionBakeoffRecordsNonProductionSlices() throws {
        let artifact = try validationArtifact("Liu2017MethaneDensityExpansionBakeoff")
        let summary = try XCTUnwrap(artifact["overallSummary"] as? [String: Any])

        XCTAssertEqual(summary["pointCount"] as? Int, 271)
        XCTAssertEqual(summary["convergedPointCount"] as? Int, 271)
        XCTAssertEqual(summary["compositionCount"] as? Int, 6)
        XCTAssertGreaterThan(try XCTUnwrap(summary["worstRelativeDeviationPercent"] as? Double), 7.6)

        let compositionSummaries = try XCTUnwrap(
            artifact["compositionSummaries"] as? [[String: Any]]
        )
        let co2RichCandidates = compositionSummaries.filter { summary in
            guard let moleFraction = summary["methaneMoleFraction"] as? Double else {
                return false
            }
            return moleFraction < 0.25
        }

        XCTAssertEqual(co2RichCandidates.count, 2)
        XCTAssertTrue(co2RichCandidates.allSatisfy {
            ($0["productionDecision"] as? String) == "rejectedForProduction"
        })
    }

    func testHydrogenExpansionBakeoffRecordsAdditionalDiagnosticCompositions() throws {
        let artifact = try validationArtifact("Cheng2019HydrogenDensityExpansionBakeoff")
        let summary = try XCTUnwrap(artifact["overallSummary"] as? [String: Any])

        XCTAssertEqual(summary["pointCount"] as? Int, 16)
        XCTAssertEqual(summary["convergedPointCount"] as? Int, 16)
        XCTAssertEqual(summary["compositionCount"] as? Int, 2)
        XCTAssertLessThan(try XCTUnwrap(summary["worstRelativeDeviationPercent"] as? Double), 2.0)

        let compositionSummaries = try XCTUnwrap(
            artifact["compositionSummaries"] as? [[String: Any]]
        )
        XCTAssertEqual(
            compositionSummaries.map { $0["productionDecision"] as? String },
            Array(repeating: "rejectedForProduction", count: 2)
        )
    }

    func testExpansionDecisionPreservesProductionDomains() throws {
        let artifact = try validationArtifact("CCSMixtureCompositionExpansionDecision2026-08-16")
        let production = try XCTUnwrap(
            artifact["productionCapabilitiesAfterMilestone"] as? [String: String]
        )

        XCTAssertEqual(
            production["hydrogenDensity"],
            "unchanged: xH2 = 0.05362 exactly; T = 273.15 K, 293.15 K or 323.15 K; Souissi per-isotherm gas pressure ranges only"
        )
        XCTAssertEqual(
            production["methaneDensity"],
            "unchanged: xCH4 = 0.05 exactly; Ghafri 301.14 K gas block plus 308.15-313.15 K high-temperature supercritical slices"
        )
        XCTAssertEqual(
            production["mixtureCaloricProperties"],
            "diagnostic only; not user-visible"
        )
    }

    private func validationArtifact(_ name: String) throws -> [String: Any] {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let repositoryRoot = packageRoot.deletingLastPathComponent()
        let artifactURL = repositoryRoot
            .appendingPathComponent("Documentation")
            .appendingPathComponent("Validation")
            .appendingPathComponent("\(name).json")
        let data = try Data(contentsOf: artifactURL)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }
}
