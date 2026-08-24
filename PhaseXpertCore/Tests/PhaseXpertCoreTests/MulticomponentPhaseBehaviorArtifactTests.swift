import Foundation
import XCTest

final class MulticomponentPhaseBehaviorArtifactTests: XCTestCase {
    func testKeGeorgeBoundaryArtifactIsCompleteAndUnmodified() throws {
        let artifact = try object("KeGeorge2017CO2ArN2PhaseBoundary")
        let source = try XCTUnwrap(artifact["source"] as? [String: Any])
        let rows = try XCTUnwrap(artifact["rows"] as? [[String: Any]])
        XCTAssertEqual(source["doi"] as? String, "10.1016/j.ijggc.2016.11.003")
        XCTAssertEqual(source["pressure_basis"] as? String, "absolute")
        XCTAssertEqual(source["both_phase_compositions_measured"] as? Bool, false)
        XCTAssertEqual(rows.count, 63)
        XCTAssertEqual(Set(rows.compactMap { $0["id"] as? String }).count, 63)
        XCTAssertEqual(rows.filter { $0["boundary"] as? String == "bubble" }.count, 24)
        XCTAssertEqual(rows.filter { $0["boundary"] as? String == "dew" }.count, 39)
        for row in rows {
            let composition = try XCTUnwrap(row["x"] as? [Double])
            XCTAssertEqual(composition.reduce(0, +), 1, accuracy: 1e-12)
            XCTAssertGreaterThan(try XCTUnwrap(row["t_k"] as? Double), 0)
            XCTAssertGreaterThan(try XCTUnwrap(row["p_mpa"] as? Double), 0)
        }
    }

    func testTheveneauInteriorArtifactHasPredictiveFlashInputsAndBothPhases() throws {
        let artifact = try object("Theveneau2020TernaryInteriorVLE")
        let source = try XCTUnwrap(artifact["source"] as? [String: Any])
        let families = try XCTUnwrap(artifact["families"] as? [String: [String: Any]])
        let rows = try XCTUnwrap(artifact["rows"] as? [[String: Any]])
        XCTAssertEqual(source["doi"] as? String, "10.1021/acs.jced.9b01082")
        XCTAssertEqual(source["feed_composition_known"] as? Bool, true)
        XCTAssertEqual(source["both_phase_compositions_measured"] as? Bool, true)
        XCTAssertEqual(source["phase_fraction_measured"] as? Bool, false)
        XCTAssertEqual(rows.count, 31)
        XCTAssertEqual(Set(rows.compactMap { $0["id"] as? String }).count, 31)
        XCTAssertEqual(families.count, 2)
        for family in families.values {
            XCTAssertEqual(try XCTUnwrap(family["z"] as? [Double]).reduce(0, +), 1, accuracy: 1e-12)
        }
        for row in rows {
            XCTAssertNotNil(families[row["family"] as! String])
            XCTAssertEqual(try XCTUnwrap(row["x"] as? [Double]).reduce(0, +), 1, accuracy: 0.0011)
            XCTAssertEqual(try XCTUnwrap(row["y"] as? [Double]).reduce(0, +), 1, accuracy: 0.0011)
        }
    }

    func testProductionDecisionRemainsPropertySpecificAndNegative() throws {
        let artifact = try object("AdvancedCCSMulticomponentPhaseBehavior2026-08-24")
        let boundary = try XCTUnwrap(artifact["new_boundary_validation"] as? [String: Any])
        let flash = try XCTUnwrap(artifact["new_interior_flash_validation"] as? [String: Any])
        let decisions = try XCTUnwrap(artifact["production_decisions"] as? [String: Any])
        XCTAssertEqual(boundary["rows"] as? Int, 63)
        XCTAssertEqual(boundary["converged"] as? Int, 40)
        XCTAssertEqual(flash["rows"] as? Int, 31)
        XCTAssertEqual(flash["converged"] as? Int, 0)
        XCTAssertEqual(decisions["new_gates"] as? [String], [])
        XCTAssertEqual(decisions["phase_fraction"] as? String, "research_only")
        XCTAssertEqual(decisions["phase_envelope"] as? String, "research_only")
        XCTAssertEqual(decisions["capability_matrix_changed"] as? Bool, false)
        XCTAssertEqual(decisions["production_ui_changed"] as? Bool, false)
    }

    private func object(_ name: String) throws -> [String: Any] {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: repositoryRoot
            .appendingPathComponent("Documentation/Validation/\(name).json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
