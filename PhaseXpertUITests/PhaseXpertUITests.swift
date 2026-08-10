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
        XCTAssertEqual(app.buttons["pressure-unit-menu"].value as? String, "bar(a)")
        XCTAssertEqual(app.buttons["temperature-unit-menu"].value as? String, "°C")

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
        XCTAssertEqual(pressure.value as? String, "42 bar(a)")
        app.buttons["keyboard-done"].tap()

        let temperature = app.textFields["Temperature value"]
        XCTAssertTrue(temperature.waitForExistence(timeout: 2))
        temperature.tap()
        temperature.typeText("-10")
        XCTAssertEqual(temperature.value as? String, "-10 °C")
    }

    func testPSIAndFahrenheitValuesReplaceOnFocus() {
        let app = XCUIApplication()
        app.launch()

        let pressureUnit = app.buttons["pressure-unit-menu"]
        XCTAssertTrue(pressureUnit.waitForExistence(timeout: 2))
        pressureUnit.tap()
        app.buttons["psi(a)"].tap()
        XCTAssertEqual(pressureUnit.value as? String, "psi(a)")

        let pressure = app.textFields["Pressure value"]
        pressure.tap()
        pressure.typeText("500")
        XCTAssertEqual(pressure.value as? String, "500 psi(a)")
        app.buttons["keyboard-done"].tap()

        let temperatureUnit = app.buttons["temperature-unit-menu"]
        XCTAssertTrue(temperatureUnit.waitForExistence(timeout: 2))
        temperatureUnit.tap()
        app.buttons["°F"].tap()
        XCTAssertEqual(temperatureUnit.value as? String, "°F")

        let temperature = app.textFields["Temperature value"]
        temperature.tap()
        temperature.typeText("68")
        XCTAssertEqual(temperature.value as? String, "68 °F")
    }

    func testIFEModelIsVisibleUnavailableAndDoesNotEnableCalculation() {
        let app = XCUIApplication()
        app.launch()

        let coolProp = app.buttons["model-coolprop-heos"]
        let ife = app.buttons["model-ife-model"]
        XCTAssertTrue(coolProp.waitForExistence(timeout: 2))
        XCTAssertTrue(ife.waitForExistence(timeout: 2))
        XCTAssertEqual(coolProp.value as? String, "Selected")
        XCTAssertEqual(ife.value as? String, "Not selected")

        ife.tap()

        XCTAssertEqual(coolProp.value as? String, "Selected")
        XCTAssertEqual(ife.value as? String, "Not selected")

        let runCalculationButton = app.buttons["run-calculation"]
        for _ in 0..<6 where !runCalculationButton.waitForExistence(timeout: 0.5) {
            app.swipeUp()
        }
        XCTAssertTrue(runCalculationButton.waitForExistence(timeout: 2))
        XCTAssertTrue(runCalculationButton.isEnabled)
        XCTAssertFalse(app.staticTexts["This model is not available in this version."].exists)
    }

    func testOperatingPointUnitsAreSeparateAndAdaptive() {
        let app = XCUIApplication()
        app.launch()

        let pressureLabel = app.staticTexts["pressure-label"]
        let temperatureLabel = app.staticTexts["temperature-label"]
        let pressureField = app.textFields["pressure-value-field"]
        let temperatureField = app.textFields["temperature-value-field"]
        let pressureUnit = app.buttons["pressure-unit-menu"]
        let temperatureUnit = app.buttons["temperature-unit-menu"]

        XCTAssertTrue(pressureLabel.waitForExistence(timeout: 2))
        XCTAssertEqual(pressureLabel.label, "Pressure")
        XCTAssertTrue(temperatureLabel.waitForExistence(timeout: 2))
        XCTAssertEqual(temperatureLabel.label, "Temperature")
        XCTAssertTrue(pressureField.exists)
        XCTAssertTrue(temperatureField.exists)
        XCTAssertTrue(pressureUnit.exists)
        XCTAssertTrue(temperatureUnit.exists)
        XCTAssertEqual(pressureUnit.value as? String, "bar(a)")
        XCTAssertEqual(temperatureUnit.value as? String, "°C")
        XCTAssertFalse(pressureField.frame.intersects(pressureUnit.frame))
        XCTAssertFalse(temperatureField.frame.intersects(temperatureUnit.frame))
        XCTAssertLessThan(pressureLabel.frame.minX, pressureField.frame.minX)
        XCTAssertLessThan(temperatureLabel.frame.minX, temperatureField.frame.minX)
        XCTAssertLessThan(pressureLabel.frame.minX, 80)
        XCTAssertLessThan(temperatureLabel.frame.minX, 80)
        XCTAssertGreaterThan(pressureField.frame.minX, pressureLabel.frame.minX + 40)
        XCTAssertGreaterThan(temperatureField.frame.minX, temperatureLabel.frame.minX + 40)
        XCTAssertGreaterThan(pressureUnit.frame.minX, pressureField.frame.maxX)
        XCTAssertGreaterThan(temperatureUnit.frame.minX, temperatureField.frame.maxX)
        XCTAssertEqual(pressureField.frame.minX, temperatureField.frame.minX, accuracy: 2)
        XCTAssertEqual(pressureField.frame.maxX, temperatureField.frame.maxX, accuracy: 2)
        XCTAssertEqual(pressureField.frame.width, temperatureField.frame.width, accuracy: 2)
        XCTAssertEqual(pressureUnit.frame.minX, temperatureUnit.frame.minX, accuracy: 2)
        XCTAssertEqual(pressureUnit.frame.maxX, temperatureUnit.frame.maxX, accuracy: 2)
        XCTAssertGreaterThan(
            pressureUnit.frame.maxX,
            app.windows.element(boundBy: 0).frame.midX
        )
    }

    func testOperatingPointUnitsRemainUsableWithLargeDynamicType() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["pressure-label"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["temperature-label"].exists)
        XCTAssertTrue(app.textFields["pressure-value-field"].exists)
        XCTAssertTrue(app.buttons["pressure-unit-menu"].exists)
        XCTAssertTrue(app.textFields["temperature-value-field"].exists)
        XCTAssertTrue(app.buttons["temperature-unit-menu"].exists)
        XCTAssertFalse(
            app.textFields["pressure-value-field"].frame
                .intersects(app.buttons["pressure-unit-menu"].frame)
        )
        XCTAssertFalse(
            app.textFields["temperature-value-field"].frame
                .intersects(app.buttons["temperature-unit-menu"].frame)
        )
    }

    func testAboutShowsIFEAttributionHierarchy() {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["About"].tap()

        XCTAssertTrue(app.staticTexts["Developed by IFE"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Flow Technology Department"].exists)
        XCTAssertFalse(app.staticTexts["Developed by the IFE Flow Technology Department"].exists)
    }

    func testCalculatorDoesNotDuplicatePreliminaryWarningCopyAtLaunch() {
        let app = XCUIApplication()
        app.launch()

        let repeatedWarning = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Validation remains incomplete")
        )
        XCTAssertEqual(repeatedWarning.count, 0)
        XCTAssertTrue(app.staticTexts["CoolProp HEOS — Preliminary"].exists)
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
        app.staticTexts["Validation and capability state"].tap()
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
        nitrogenField.tap()
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

        let pureCO2ScopeMessage = app.staticTexts[
            "Phase diagrams are available for pure CO₂. Remove all impurities to view the CO₂ phase diagram."
        ]
        XCTAssertTrue(
            app.otherElements["phase-diagram-pure-co2-scope"].waitForExistence(timeout: 10)
                || pureCO2ScopeMessage.waitForExistence(timeout: 3),
            "The phase-diagram screen did not show the pure-CO₂ scope state for 3 mol% N₂."
        )
        XCTAssertTrue(pureCO2ScopeMessage.exists)
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
