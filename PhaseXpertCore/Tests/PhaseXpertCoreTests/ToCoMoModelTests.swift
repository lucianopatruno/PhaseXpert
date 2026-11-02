import Foundation
import XCTest
@testable import PhaseXpertCore

/// The Swift port is checked against results produced by the original Python
/// implementation (see Scripts/generate-tocomo-reference.py), not against values
/// written by hand. ToCoMo is MIT licensed, Copyright (c) 2025 Equinor.
final class ToCoMoModelTests: XCTestCase {
    private struct ReferenceFile: Decodable {
        struct Step: Decodable {
            let reaction: Int
            let multiplier: Double
            let after: [String: Double]
        }

        struct Case: Decodable {
            let name: String
            let input: [String: Double]
            let final: [String: Double]
            let steps: [Step]
        }

        let commit: String
        let cases: [Case]
    }

    private func loadReference() throws -> ReferenceFile {
        try JSONDecoder().decode(ReferenceFile.self, from: Data(ToCoMoReferenceData.json.utf8))
    }

    private func input(from values: [String: Double]) -> ToCoMoInput {
        ToCoMoInput(
            oxygenPpm: values["O2"] ?? 0,
            waterPpm: values["H2O"] ?? 0,
            hydrogenSulfidePpm: values["H2S"] ?? 0,
            sulfurDioxidePpm: values["SO2"] ?? 0,
            nitrogenDioxidePpm: values["NO2"] ?? 0
        )
    }

    private func assertClose(
        _ actual: Double,
        _ expected: Double,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let tolerance = 1e-9 * max(1, abs(expected))
        XCTAssertEqual(actual, expected, accuracy: tolerance, message, file: file, line: line)
    }

    func testMatchesTheReferenceImplementationOnEveryCase() throws {
        let reference = try loadReference()
        XCTAssertEqual(reference.cases.count, 12)

        for referenceCase in reference.cases {
            let result = try ToCoMoModel.run(input(from: referenceCase.input))

            XCTAssertEqual(
                result.steps.count,
                referenceCase.steps.count,
                "\(referenceCase.name): number of reaction steps"
            )
            for species in ImpurityReactionSpecies.allCases {
                assertClose(
                    result.finalPpm[species] ?? .nan,
                    referenceCase.final[species.rawValue] ?? 0,
                    "\(referenceCase.name): final \(species.rawValue)"
                )
            }
            for (swiftStep, referenceStep) in zip(result.steps, referenceCase.steps) {
                XCTAssertEqual(
                    swiftStep.reactionIndex,
                    referenceStep.reaction,
                    "\(referenceCase.name): step \(swiftStep.order) reaction"
                )
                assertClose(
                    swiftStep.multiplier,
                    referenceStep.multiplier,
                    "\(referenceCase.name): step \(swiftStep.order) multiplier"
                )
                for species in ImpurityReactionSpecies.allCases {
                    assertClose(
                        swiftStep.concentrationsPpm[species] ?? .nan,
                        referenceStep.after[species.rawValue] ?? 0,
                        "\(referenceCase.name): step \(swiftStep.order) \(species.rawValue)"
                    )
                }
            }
        }
    }

    func testReferenceCommitIsPinnedAndAttributed() throws {
        XCTAssertEqual(try loadReference().commit, ToCoMoModel.reference.commit)
        XCTAssertEqual(ToCoMoModel.reference.licence, "MIT")
        XCTAssertEqual(ToCoMoModel.reference.copyright, "Copyright (c) 2025 Equinor")
        XCTAssertEqual(ToCoMoModel.reference.repository.scheme, "https")
        XCTAssertTrue(ToCoMoModel.reference.attribution.contains("Hesjevik"))
        XCTAssertTrue(ToCoMoModel.reference.attribution.contains("Halvorsen"))
    }

    /// The case used by AcidWatch's own test (tolerance 0.01 ppm there).
    func testAcidWatchWorkerTestCase() throws {
        let result = try ToCoMoModel.run(
            ToCoMoInput(
                oxygenPpm: 15,
                waterPpm: 40,
                hydrogenSulfidePpm: 3,
                sulfurDioxidePpm: 0,
                nitrogenDioxidePpm: 15
            )
        )
        let expected: [ImpurityReactionSpecies: Double] = [
            .sulfuricAcid: 3, .nitricAcid: 15, .nitrousAcid: 0, .sulfurDioxide: 0,
            .nitrogenDioxide: 0, .hydrogenSulfide: 0, .water: 32.5, .elementalSulfur: 0,
            .oxygen: 5.25, .nitricOxide: 0
        ]
        for (species, value) in expected {
            XCTAssertEqual(result.finalPpm[species] ?? .nan, value, accuracy: 0.01, species.rawValue)
        }
        XCTAssertTrue(result.reactionApplied)
    }

    /// The model stops when the next multiplier is below 0.001 ppm, so a small
    /// residue of NO₂ remains. This is the reference behaviour and must stay.
    func testCutoffLeavesASmallResidueExactlyAsTheReferenceDoes() throws {
        let result = try ToCoMoModel.run(
            ToCoMoInput(oxygenPpm: 15, waterPpm: 40, hydrogenSulfidePpm: 3, nitrogenDioxidePpm: 15)
        )
        let residue = try XCTUnwrap(result.finalPpm[.nitrogenDioxide])
        XCTAssertGreaterThan(residue, 0)
        XCTAssertLessThan(residue, 0.01)
    }

    func testReactionListHasTheReferenceOrderAndActivation() {
        XCTAssertEqual(ToCoMoModel.reactions.map(\.index), [3, 2, 1, 4, 5, 6])
        XCTAssertEqual(ToCoMoModel.reactions.filter { !$0.isActive }.map(\.index), [5])
        XCTAssertEqual(ToCoMoModel.minimumMultiplier, 0.001)
    }

    func testEveryReactionIsAtomBalanced() {
        for reaction in ToCoMoModel.reactions {
            XCTAssertEqual(
                atoms(of: reaction.reactants),
                atoms(of: reaction.products),
                "reaction \(reaction.index): \(reaction.displayText)"
            )
        }
    }

    func testEveryStepConservesAtoms() throws {
        let result = try ToCoMoModel.run(
            ToCoMoInput(oxygenPpm: 500, waterPpm: 1000, hydrogenSulfidePpm: 100, sulfurDioxidePpm: 200, nitrogenDioxidePpm: 300)
        )
        let start = atoms(of: result.initialPpm)
        for step in result.steps {
            let now = atoms(of: step.concentrationsPpm)
            for (element, count) in start {
                XCTAssertEqual(now[element] ?? .nan, count, accuracy: 1e-8 * max(1, count), "\(element) after step \(step.order)")
            }
        }
        let end = atoms(of: result.finalPpm)
        for (element, count) in start {
            XCTAssertEqual(end[element] ?? .nan, count, accuracy: 1e-8 * max(1, count), element)
        }
    }

    func testNoReactionLeavesTheStreamUnchangedAndSaysSo() throws {
        let zero = try ToCoMoModel.run(ToCoMoInput())
        XCTAssertFalse(zero.reactionApplied)
        XCTAssertEqual(zero.finalPpm, zero.initialPpm)

        let stuck = try ToCoMoModel.run(ToCoMoInput(nitrogenDioxidePpm: 10))
        XCTAssertFalse(stuck.reactionApplied)
        XCTAssertEqual(stuck.finalPpm, stuck.initialPpm)
        XCTAssertTrue(stuck.steps.isEmpty)
    }

    func testRejectsInvalidInputInsteadOfCorrectingIt() {
        XCTAssertThrowsError(try ToCoMoModel.run(ToCoMoInput(waterPpm: -1))) {
            XCTAssertEqual($0 as? ToCoMoError, .invalidValue(.water, -1))
        }
        XCTAssertThrowsError(try ToCoMoModel.run(ToCoMoInput(oxygenPpm: .nan))) {
            guard case .invalidValue(.oxygen, _) = $0 as? ToCoMoError else {
                return XCTFail("expected an invalid oxygen value")
            }
        }
        XCTAssertThrowsError(try ToCoMoModel.run(ToCoMoInput(nitrogenDioxidePpm: .infinity)))
        XCTAssertThrowsError(try ToCoMoModel.run(ToCoMoInput(oxygenPpm: 400_001, waterPpm: 600_000))) {
            guard case .totalExceedsLimit = $0 as? ToCoMoError else {
                return XCTFail("expected the total limit error")
            }
        }
        XCTAssertNoThrow(try ToCoMoModel.run(ToCoMoInput(waterPpm: 1_000_000)))
    }

    func testInputSpeciesAreTheFiveAcidWatchExposes() {
        XCTAssertEqual(
            Set(ToCoMoInput.species),
            [.water, .oxygen, .hydrogenSulfide, .sulfurDioxide, .nitrogenDioxide]
        )
    }

    // MARK: - Helpers

    private func atoms(of terms: [ToCoMoTerm]) -> [String: Int] {
        var totals: [String: Int] = [:]
        for term in terms {
            for (element, count) in term.species.atoms {
                totals[element, default: 0] += count * term.coefficient
            }
        }
        return totals
    }

    private func atoms(of concentrations: [ImpurityReactionSpecies: Double]) -> [String: Double] {
        var totals: [String: Double] = [:]
        for (species, value) in concentrations {
            for (element, count) in species.atoms {
                totals[element, default: 0] += Double(count) * value
            }
        }
        return totals
    }
}
