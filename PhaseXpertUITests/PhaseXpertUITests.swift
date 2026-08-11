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
        XCTAssertFalse(app.staticTexts["Absolute"].exists)
        XCTAssertFalse(app.staticTexts["absolute"].exists)
        XCTAssertFalse(app.staticTexts["Pressure inputs are absolute."].exists)

        let runCalculationButton = app.buttons["run-calculation"]
        for _ in 0..<5 where !runCalculationButton.waitForExistence(timeout: 0.5) {
            app.swipeUp()
        }
        XCTAssertTrue(
            runCalculationButton.waitForExistence(timeout: 2),
            "Run calculation button should be reachable by scrolling the calculator form."
        )

        openMoreRow("Models", in: app)
        XCTAssertTrue(app.navigationBars["Model Information"].waitForExistence(timeout: 2))
    }

    func testBottomTabBarHasThreePrimaryTabsInOrder() {
        let app = XCUIApplication()
        app.launch()

        let tabBar = app.tabBars.element
        XCTAssertTrue(tabBar.waitForExistence(timeout: 2))
        XCTAssertTrue(tabBar.buttons["Calculator"].exists)
        XCTAssertTrue(tabBar.buttons["Saved Cases"].exists)
        XCTAssertTrue(tabBar.buttons["Phase Diagram"].exists)
        XCTAssertFalse(tabBar.buttons["Stream Mixing"].exists)
        XCTAssertLessThan(tabBar.buttons["Calculator"].frame.minX, tabBar.buttons["Saved Cases"].frame.minX)
        XCTAssertLessThan(tabBar.buttons["Saved Cases"].frame.minX, tabBar.buttons["Phase Diagram"].frame.minX)
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
        if app.buttons["keyboard-minus"].waitForExistence(timeout: 2) {
            app.buttons["keyboard-minus"].tap()
            temperature.typeText("10")
        } else {
            temperature.typeText("-10")
        }
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

    func testThreePercentNitrogenShowsPhaseMap() {
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

        XCTAssertTrue(
            app.buttons["calculate-phase-map"].waitForExistence(timeout: 10),
            "The phase-diagram screen did not expose Phase Map for 3 mol% N₂."
        )
        XCTAssertTrue(app.staticTexts["Preliminary multicomponent Phase Map"].exists)
        XCTAssertFalse(app.otherElements["phase-boundary-chart"].exists)
    }

    func testStreamMixingNavigationAndInitialTwoStreamState() {
        let app = XCUIApplication()
        app.launch()

        openStreamMixing(in: app)

        XCTAssertTrue(app.navigationBars["Stream Mixing"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Stream Mixing v1"].exists)
        let addStream = app.buttons["Add stream"]
        for _ in 0..<4 where !addStream.waitForExistence(timeout: 0.5) {
            app.swipeUp()
        }
        XCTAssertTrue(addStream.exists)
        XCTAssertTrue(app.staticTexts["stream-mixing-stream-count"].exists)
        let calculate = app.buttons["Calculate mixture"]
        for _ in 0..<6 where !calculate.waitForExistence(timeout: 0.5) {
            app.swipeUp()
        }
        XCTAssertTrue(calculate.exists)
    }

    func testStreamMixingAddDuplicateAndMaximumStreamBehavior() {
        let app = XCUIApplication()
        app.launch()
        openStreamMixing(in: app)

        let addStream = streamMixingAddStreamButton(in: app)
        for _ in 0..<4 {
            addStream.tap()
        }

        XCTAssertFalse(addStream.isEnabled)

        app.buttons.matching(NSPredicate(format: "label == %@", "Stream actions")).element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["Duplicate stream"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["Duplicate stream"].isEnabled)
        app.tap()
    }

    func testStreamMixingDuplicateAndRemovePreserveMinimum() {
        let app = XCUIApplication()
        app.launch()
        openStreamMixing(in: app)

        app.buttons.matching(NSPredicate(format: "label == %@", "Stream actions")).element(boundBy: 0).tap()
        app.buttons["Duplicate stream"].tap()
        XCTAssertTrue(app.staticTexts["stream-mixing-stream-count"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.staticTexts["stream-mixing-stream-count"].label, "3 of 6 streams")

        app.buttons.matching(NSPredicate(format: "label == %@", "Stream actions")).element(boundBy: 0).tap()
        app.buttons["Remove stream"].tap()

        XCTAssertEqual(app.staticTexts["stream-mixing-stream-count"].label, "2 of 6 streams")
        app.buttons.matching(NSPredicate(format: "label == %@", "Stream actions")).element(boundBy: 0).tap()
        XCTAssertFalse(app.buttons["Remove stream"].isEnabled)
        app.tap()
    }

    func testStreamMixingFlowAndOutletUnitConversionPreservesValues() {
        let app = XCUIApplication()
        app.launch()
        openStreamMixing(in: app)

        let firstFlowUnit = app.buttons.matching(NSPredicate(format: "identifier CONTAINS %@", "stream-flow-")).element(boundBy: 0)
        XCTAssertTrue(firstFlowUnit.waitForExistence(timeout: 3))
        firstFlowUnit.tap()
        app.buttons["kmol/h"].tap()
        XCTAssertEqual(firstFlowUnit.value as? String, "kmol/h")
        let firstFlowValue = app.textFields.matching(NSPredicate(format: "identifier CONTAINS %@", "stream-flow-")).element(boundBy: 0)
        XCTAssertTrue(firstFlowValue.waitForExistence(timeout: 2))
        XCTAssertTrue((firstFlowValue.value as? String)?.contains("36") == true)

        let outletPressureUnit = app.buttons["stream-mixing-outlet-pressure-unit-menu"]
        for _ in 0..<5 where !outletPressureUnit.waitForExistence(timeout: 0.5) {
            app.swipeUp()
        }
        XCTAssertTrue(outletPressureUnit.exists)
        outletPressureUnit.tap()
        app.buttons["psi(a)"].tap()
        XCTAssertEqual(outletPressureUnit.value as? String, "psi(a)")
        let outletPressureValue = app.textFields["stream-mixing-outlet-pressure-value-field"]
        XCTAssertTrue((outletPressureValue.value as? String)?.contains("1740.45") == true)

        let outletTemperatureUnit = app.buttons["stream-mixing-outlet-temperature-unit-menu"]
        XCTAssertTrue(outletTemperatureUnit.exists)
        outletTemperatureUnit.tap()
        app.buttons["K"].tap()
        XCTAssertEqual(outletTemperatureUnit.value as? String, "K")
        let outletTemperatureValue = app.textFields["stream-mixing-outlet-temperature-value-field"]
        XCTAssertTrue((outletTemperatureValue.value as? String)?.contains("298.15") == true)
    }

    func testStreamMixingMoveDownActionReordersVisibleStreams() {
        let app = XCUIApplication()
        app.launch()
        openStreamMixing(in: app)

        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label == %@", "Stream actions"))
                .element(boundBy: 0)
                .waitForExistence(timeout: 3)
        )
        let streamNames = app.textFields.matching(NSPredicate(format: "label == %@", "Stream name"))
        XCTAssertTrue(streamNames.element(boundBy: 0).waitForExistence(timeout: 3))
        XCTAssertEqual(streamNames.element(boundBy: 0).value as? String, "Stream 1")

        app.buttons.matching(NSPredicate(format: "label == %@", "Stream actions")).element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["Move down"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["Move up"].isEnabled)
        app.buttons["Move down"].tap()

        XCTAssertEqual(streamNames.element(boundBy: 0).value as? String, "Stream 2")
    }

    func testStreamMixingSuccessfulCalculationWarningTraceabilityAndStaleState() {
        let app = XCUIApplication()
        app.launch()
        openStreamMixing(in: app)

        let calculate = app.buttons["Calculate mixture"]
        for _ in 0..<8 where !calculate.waitForExistence(timeout: 0.5) {
            app.swipeUp()
        }
        XCTAssertTrue(calculate.waitForExistence(timeout: 3))
        XCTAssertTrue(calculate.isEnabled)
        calculate.tap()

        for _ in 0..<8 where !app.staticTexts["Preliminary V1 aggregation"].waitForExistence(timeout: 0.5) {
            app.swipeUp()
        }
        XCTAssertTrue(app.staticTexts["Preliminary V1 aggregation"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Total molar flow"].exists)
        XCTAssertTrue(app.staticTexts["Total mass flow"].exists)
        XCTAssertEqual(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "does not model pressure equalization")).count,
            1
        )

        let traceability = app.buttons["Assumptions and traceability"]
        for _ in 0..<8 where !traceability.waitForExistence(timeout: 0.5) {
            app.swipeUp()
        }
        XCTAssertTrue(traceability.exists)
        traceability.tap()
        XCTAssertTrue(app.staticTexts["Outlet pressure — SI"].waitForExistence(timeout: 2))
    }

    func testStreamMixingLargeDynamicTypeEssentialControlsRemainReachable() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ]
        app.launch()

        openStreamMixing(in: app)

        XCTAssertTrue(app.buttons["Add stream"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier CONTAINS %@", "stream-flow-")).element(boundBy: 0).exists)
        let calculate = app.buttons["stream-mixing-calculate"]
        for _ in 0..<10 where !calculate.waitForExistence(timeout: 0.5) {
            app.swipeUp()
        }
        XCTAssertTrue(calculate.exists)
    }

    func testCalculatorCompositionEditingRemainsUnchangedAfterStreamMixingTabAdded() {
        let app = XCUIApplication()
        app.launch()

        addImpurity(in: app)

        let ppmField = app.textFields["N₂ ppm"]
        XCTAssertTrue(ppmField.waitForExistence(timeout: 3))
        ppmField.tap()
        ppmField.typeText("250")
        app.buttons["keyboard-done"].tap()
        XCTAssertEqual(ppmField.value as? String, "250")
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

    private func openStreamMixing(in app: XCUIApplication) {
        openMoreRow("Stream Mixing", in: app)
    }

    private func openMoreRow(_ label: String, in app: XCUIApplication) {
        let more = app.tabBars.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: 2))
        more.tap()
        let row = app.cells[label].exists
            ? app.cells[label]
            : app.buttons[label]
        XCTAssertTrue(row.waitForExistence(timeout: 2))
        row.tap()
    }

    private func streamMixingAddStreamButton(in app: XCUIApplication) -> XCUIElement {
        let addStream = app.buttons["Add stream"]
        for _ in 0..<6 where !addStream.waitForExistence(timeout: 0.5) {
            app.swipeUp()
        }
        XCTAssertTrue(addStream.waitForExistence(timeout: 3))
        return addStream
    }
}
