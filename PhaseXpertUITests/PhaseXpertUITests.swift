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

    func testNumericKeyboardDoesNotShowCustomOKControl() {
        let app = XCUIApplication()
        app.launch()

        app.textFields["Pressure value"].tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["OK"].exists)
    }

    func testPressureAndTemperatureValuesReplaceOnFocus() {
        let app = XCUIApplication()
        app.launch()

        let pressure = app.textFields["Pressure value"]
        XCTAssertTrue(pressure.waitForExistence(timeout: 2))
        pressure.tap()
        pressure.typeText("42")
        XCTAssertEqual(pressure.value as? String, "42")

        let temperature = app.textFields["Temperature value"]
        XCTAssertTrue(temperature.waitForExistence(timeout: 2))
        temperature.tap()
        temperature.typeText("-10")
        XCTAssertEqual(temperature.value as? String, "-10")
    }

    func testIFEModelIsVisibleUnavailableAndDoesNotEnableCalculation() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["model-ife-model"].waitForExistence(timeout: 2))
        app.buttons["model-ife-model"].tap()

        let runCalculationButton = app.buttons["run-calculation"]
        for _ in 0..<6 where !runCalculationButton.waitForExistence(timeout: 0.5) {
            app.swipeUp()
        }
        XCTAssertTrue(runCalculationButton.waitForExistence(timeout: 2))
        XCTAssertTrue(runCalculationButton.isEnabled)
        XCTAssertTrue(app.buttons["model-coolprop-heos"].exists)
    }

    func testImpurityKeyboardDoneDismissesInPPMAndMolPercentModes() {
        let app = XCUIApplication()
        app.launch()

        addImpurity(in: app)

        let ppmField = app.textFields["N₂ ppm"]
        XCTAssertTrue(ppmField.waitForExistence(timeout: 3))
        ppmField.tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 2))
        ppmField.typeText("250")
        XCTAssertTrue(app.buttons["keyboard-done"].waitForExistence(timeout: 2))
        app.buttons["keyboard-done"].tap()
        XCTAssertFalse(app.keyboards.element.waitForExistence(timeout: 1))
        XCTAssertEqual(ppmField.value as? String, "250")

        app.buttons["mol%"].tap()
        let molePercentField = app.textFields["N₂ mol%"]
        XCTAssertTrue(molePercentField.waitForExistence(timeout: 3))
        molePercentField.tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["keyboard-done"].waitForExistence(timeout: 2))
        app.buttons["keyboard-done"].tap()
        XCTAssertFalse(app.keyboards.element.waitForExistence(timeout: 1))
    }

    func testImpurityKeyboardDismissesOnOutsideTapRunBasisChangeAndRemoval() {
        let app = XCUIApplication()
        app.launch()

        addImpurity(in: app)
        addImpurity(in: app)

        let nitrogenField = app.textFields["N₂ ppm"]
        XCTAssertTrue(nitrogenField.waitForExistence(timeout: 3))
        nitrogenField.tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 2))
        nitrogenField.typeText("100")
        app.staticTexts["Composition"].tap()
        XCTAssertFalse(app.keyboards.element.waitForExistence(timeout: 1))
        XCTAssertEqual(nitrogenField.value as? String, "100")

        nitrogenField.tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 2))
        app.buttons["mol%"].tap()
        XCTAssertFalse(app.keyboards.element.waitForExistence(timeout: 1))
        let nitrogenMolePercentField = app.textFields["N₂ mol%"]
        XCTAssertTrue(nitrogenMolePercentField.waitForExistence(timeout: 3))

        let oxygenField = app.textFields["O₂ mol%"]
        XCTAssertTrue(oxygenField.waitForExistence(timeout: 3))
        oxygenField.tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 2))
        openImpurityMenu("O₂", in: app)
        app.buttons["Remove impurity"].tap()
        XCTAssertFalse(app.keyboards.element.waitForExistence(timeout: 1))
        XCTAssertFalse(app.textFields["O₂ mol%"].exists)

        let runCalculationButton = app.buttons["run-calculation"]
        for _ in 0..<6 where !runCalculationButton.waitForExistence(timeout: 0.5) {
            app.swipeUp()
        }
        XCTAssertTrue(runCalculationButton.waitForExistence(timeout: 2))
        nitrogenMolePercentField.tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 2))
        runCalculationButton.tap()
        XCTAssertFalse(app.keyboards.element.waitForExistence(timeout: 1))
    }

    func testImpurityMenuProvidesExplicitRemoval() {
        let app = XCUIApplication()
        app.launch()

        addImpurity(in: app)

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

    func testThreePercentNitrogenShowsPureCO2PhaseDiagramScope() {
        let app = XCUIApplication()
        app.launch()

        addImpurity(in: app)

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
            app.otherElements["phase-diagram-pure-co2-scope"].waitForExistence(timeout: 10),
            "The phase-diagram screen did not show the pure-CO₂ scope state for 3 mol% N₂."
        )
        XCTAssertTrue(
            app.staticTexts[
                "Phase diagrams are available for pure CO₂. Remove all impurities to view the CO₂ phase diagram."
            ].exists
        )
        XCTAssertFalse(app.otherElements["phase-boundary-chart"].exists)
    }

    private func addImpurity(in app: XCUIApplication) {
        let addImpurityButton = app.buttons["Add impurity"]
        for _ in 0..<4 where !addImpurityButton.waitForExistence(timeout: 0.5) {
            app.swipeUp()
        }
        XCTAssertTrue(addImpurityButton.waitForExistence(timeout: 3))
        addImpurityButton.tap()
    }

    private func openImpurityMenu(_ symbol: String, in app: XCUIApplication) {
        let menu = app.buttons["\(symbol) impurity menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 3))
        menu.tap()
    }
}
