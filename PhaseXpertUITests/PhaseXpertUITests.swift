import XCTest

final class PhaseXpertUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testMainWorkflowIsReachable() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Calculator"].exists)
        XCTAssertTrue(app.buttons["run-calculation"].exists)
        XCTAssertTrue(app.staticTexts["Pressure"].exists)
        XCTAssertTrue(app.staticTexts["bar abs"].exists)
        XCTAssertTrue(app.staticTexts["Temperature"].exists)
        XCTAssertTrue(app.staticTexts["°C"].exists)

        app.tabBars.buttons["Models"].tap()
        XCTAssertTrue(app.navigationBars["Model Information"].exists)
    }

    func testNumericKeyboardCanBeDismissed() {
        let app = XCUIApplication()
        app.launch()

        app.textFields["Pressure value"].tap()
        XCTAssertTrue(app.buttons["OK"].waitForExistence(timeout: 2))
        app.buttons["OK"].tap()
        XCTAssertFalse(app.buttons["OK"].exists)
    }
}
