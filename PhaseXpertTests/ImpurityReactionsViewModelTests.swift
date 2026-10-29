import PhaseXpertCore
import XCTest
@testable import PhaseXpert

@MainActor
final class ImpurityReactionsViewModelTests: XCTestCase {
    func testParsingAcceptsDotAndCommaAndRejectsText() {
        XCTAssertEqual(ImpurityReactionsViewModel.parse("12.5"), 12.5)
        XCTAssertEqual(ImpurityReactionsViewModel.parse("12,5"), 12.5)
        XCTAssertEqual(ImpurityReactionsViewModel.parse("  7 "), 7)
        XCTAssertNil(ImpurityReactionsViewModel.parse("15.."))
        XCTAssertNil(ImpurityReactionsViewModel.parse("abc"))
        XCTAssertNil(ImpurityReactionsViewModel.parse(""))
    }

    func testNothingEnteredIsEmptyNotAResult() {
        let model = ImpurityReactionsViewModel()
        XCTAssertEqual(model.outcome, .empty)
        model.texts[.water] = "   "
        XCTAssertEqual(model.outcome, .empty)
    }

    func testReferenceCaseProducesTheModelResult() throws {
        let model = ImpurityReactionsViewModel()
        model.texts = [.water: "40", .oxygen: "15", .nitrogenDioxide: "15", .hydrogenSulfide: "3"]

        guard case let .result(result) = model.outcome else {
            return XCTFail("expected a result")
        }
        XCTAssertTrue(result.reactionApplied)
        XCTAssertEqual(result.finalPpm[.sulfuricAcid] ?? .nan, 3, accuracy: 0.01)
        XCTAssertEqual(result.finalPpm[.nitricAcid] ?? .nan, 15, accuracy: 0.01)
        XCTAssertEqual(
            result,
            try ToCoMoModel.run(ToCoMoInput(oxygenPpm: 15, waterPpm: 40, hydrogenSulfidePpm: 3, nitrogenDioxidePpm: 15))
        )
    }

    func testDecimalCommaGivesTheSameResultAsDecimalPoint() {
        let comma = ImpurityReactionsViewModel()
        comma.texts = [.water: "33,3", .oxygen: "7,7", .nitrogenDioxide: "12,5"]
        let point = ImpurityReactionsViewModel()
        point.texts = [.water: "33.3", .oxygen: "7.7", .nitrogenDioxide: "12.5"]
        XCTAssertEqual(comma.outcome, point.outcome)
    }

    func testUnreadableTextNamesTheFieldAndShowsNoResult() {
        let model = ImpurityReactionsViewModel()
        model.texts = [.water: "40", .nitrogenDioxide: "15.."]
        XCTAssertEqual(model.outcome, .unreadable(.nitrogenDioxide))
    }

    func testRejectedValuesAreReportedNotCorrected() {
        let negative = ImpurityReactionsViewModel()
        negative.texts = [.water: "-5"]
        guard case let .rejected(message) = negative.outcome else {
            return XCTFail("expected a rejection")
        }
        XCTAssertTrue(message.contains("H₂O"))

        let tooMuch = ImpurityReactionsViewModel()
        tooMuch.texts = [.water: "900000", .oxygen: "200000"]
        guard case .rejected = tooMuch.outcome else {
            return XCTFail("expected the total limit to be enforced")
        }
    }

    func testZeroAmountsReportNoReactionNotAnError() {
        let model = ImpurityReactionsViewModel()
        model.texts = [.water: "0", .oxygen: "0"]
        guard case let .result(result) = model.outcome else {
            return XCTFail("expected a result")
        }
        XCTAssertFalse(result.reactionApplied)
    }

    func testClearReturnsToEmpty() {
        let model = ImpurityReactionsViewModel()
        model.texts = [.water: "40"]
        model.clear()
        XCTAssertEqual(model.outcome, .empty)
    }
}
