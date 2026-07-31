import XCTest

final class PhaseXpertUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testMainWorkflowIsReachable() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Calculator"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Pressure"].exists)
        XCTAssertTrue(app.staticTexts["bar abs"].exists)
        XCTAssertTrue(app.staticTexts["Temperature"].exists)
        XCTAssertTrue(app.staticTexts["°C"].exists)

        let runCalculationButton = app.buttons["run-calculation"]
        for _ in 0..<5 where !runCalculationButton.waitForExistence(timeout: 0.5) {
            app.swipeUp()
        }
        XCTAssertTrue(
            runCalculationButton.waitForExistence(timeout: 2),
            "Run calculation button should be reachable by scrolling the calculator form."
        )

        app.tabBars.buttons["Models"].tap()
        XCTAssertTrue(app.navigationBars["Model Information"].waitForExistence(timeout: 2))
    }

    func testNumericKeyboardCanBeDismissed() {
        let app = XCUIApplication()
        app.launch()

        app.textFields["Pressure value"].tap()
        XCTAssertTrue(app.buttons["OK"].waitForExistence(timeout: 2))
        app.buttons["OK"].tap()
        XCTAssertFalse(app.buttons["OK"].exists)
    }

    func testPhaseDiagramRequiresARealCalculation() {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Phase Diagram"].tap()

        XCTAssertTrue(app.navigationBars["Phase Diagram"].waitForExistence(timeout: 2))
        XCTAssertTrue(
            app.otherElements["phase-diagram-no-calculation"].exists
                || app.staticTexts["No operating point"].exists
        )
    }
}
