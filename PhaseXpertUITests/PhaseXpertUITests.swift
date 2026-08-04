import XCTest

@MainActor
final class PhaseXpertUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testMainWorkflowIsReachable() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Calculator"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Pressure"].exists)
        XCTAssertTrue(app.staticTexts["bar(a)"].exists)
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

    func testShieldScientificReferenceIsAnInteractiveLink() {
        let app = XCUIApplication()
        app.launch()

        let shield = app.buttons["Scientific traceability"]
        XCTAssertTrue(shield.waitForExistence(timeout: 3))
        shield.tap()
        XCTAssertTrue(
            app.navigationBars["Scientific Traceability"].waitForExistence(timeout: 3)
        )

        var link = app.links.firstMatch
        for _ in 0..<12 where !link.waitForExistence(timeout: 0.25) {
            app.swipeUp()
            link = app.links.firstMatch
        }
        XCTAssertTrue(
            link.waitForExistence(timeout: 2),
            "A valid HTTPS/DOI scientific reference must be exposed as a Link."
        )
        XCTAssertFalse(link.label.isEmpty)
    }

    func testNumericKeyboardDoesNotShowCustomOKControl() {
        let app = XCUIApplication()
        app.launch()

        app.textFields["Pressure value"].tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["OK"].exists)
    }

    func testImpurityMenuProvidesExplicitRemoval() {
        let app = XCUIApplication()
        app.launch()

        let addImpurityButton = app.buttons["Add impurity"]
        XCTAssertTrue(addImpurityButton.waitForExistence(timeout: 3))
        addImpurityButton.tap()

        let impurityMenu = app.buttons["N₂ impurity menu"]
        XCTAssertTrue(impurityMenu.waitForExistence(timeout: 3))
        impurityMenu.tap()

        let removeButton = app.buttons["Remove impurity"]
        XCTAssertTrue(removeButton.waitForExistence(timeout: 2))
        removeButton.tap()

        XCTAssertFalse(app.textFields["N₂ ppm"].exists)
        XCTAssertFalse(app.buttons["N₂ impurity menu"].exists)
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

    func testThreePercentNitrogenRejectsOutOfDomainProviderTrace() {
        let app = XCUIApplication()
        app.launch()

        let addImpurityButton = app.buttons["Add impurity"]
        XCTAssertTrue(addImpurityButton.waitForExistence(timeout: 3))
        addImpurityButton.tap()

        let nitrogenField = app.textFields["N₂ ppm"]
        XCTAssertTrue(nitrogenField.waitForExistence(timeout: 3))
        nitrogenField.typeText("30000")
        XCTAssertFalse(app.buttons["OK"].exists)
        app.swipeDown()

        let runCalculationButton = app.buttons["run-calculation"]
        for _ in 0..<6 where !runCalculationButton.waitForExistence(timeout: 0.5) {
            app.swipeUp()
        }
        XCTAssertTrue(runCalculationButton.waitForExistence(timeout: 2))
        XCTAssertTrue(runCalculationButton.isEnabled)
        runCalculationButton.tap()

        let viewPhaseDiagramButton = app.buttons["view-phase-diagram"]
        for _ in 0..<18 where !viewPhaseDiagramButton.waitForExistence(timeout: 0.5) {
            app.swipeUp()
        }
        XCTAssertTrue(
            viewPhaseDiagramButton.waitForExistence(timeout: 5),
            "The 3 mol% N₂ operating-point calculation did not finish."
        )
        viewPhaseDiagramButton.tap()

        XCTAssertTrue(
            app.otherElements["phase-diagram-error"].waitForExistence(timeout: 10),
            "The out-of-domain provider trace was not rejected for 3 mol% N₂."
        )
        XCTAssertTrue(
            app.staticTexts[
                "CoolProp mixture phase-envelope continuation left PhaseXpert's supported "
                    + "0.8–300 bar(a), −55–150 °C domain; no diagram is displayed."
            ].exists
        )
        XCTAssertFalse(app.otherElements["phase-boundary-chart"].exists)
    }
}
