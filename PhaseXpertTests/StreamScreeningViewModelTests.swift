import PhaseXpertCore
import XCTest
@testable import PhaseXpert

@MainActor
final class StreamScreeningViewModelTests: XCTestCase {
    func testInputParsingUsesPPMAndSIWithoutNormalization() throws {
        let model = StreamScreeningViewModel(service: .init(provider: nil))
        model.pressureText = "30,5"
        model.temperatureText = "40,2"
        model.ppmTexts = [.water: "100", .nitrogenDioxide: "10", .sulfurDioxide: "10"]
        let input = try model.parsedInput()
        XCTAssertEqual(input.pressurePa, 3_050_000)
        XCTAssertEqual(input.temperatureK, 313.35, accuracy: 1e-10)
        XCTAssertEqual(input.carbonDioxidePpm, 999_880)
        XCTAssertFalse(input.includeBinaryWaterReference)
    }

    func testCalculatorHandoffCopiesSIInputsAndAllOriginalImpurities() throws {
        let request = CalculationRequest(modelID: "test", pressurePa: 3_000_000,
            temperatureK: 313.15, composition: [
                .init(component: .carbonDioxide, moleFraction: 0.98),
                .init(component: .nitrogen, moleFraction: 0.001),
                .init(component: .water, moleFraction: 0.019)
            ], clientVersion: "test")
        let response = CalculationResponse(requestID: request.requestID,
            model: ProviderRegistry.ifeModelDescriptor, phase: .unknown, properties: [],
            solver: .init(method: "Test fixture", converged: true, durationMilliseconds: 0),
            warnings: [], isScientificResult: false)
        let record = CalculationRecord(request: request,
            input: .init(pressureValue: 3, pressureUnit: .megapascal, pressurePa: request.pressurePa,
                temperatureValue: 313.15, temperatureUnit: .kelvin, temperatureK: request.temperatureK,
                originalComposition: []), response: response,
            application: .init(version: "test", build: "test"))
        let model = StreamScreeningViewModel(record: record, service: .init(provider: nil))
        let input = try model.parsedInput()
        XCTAssertEqual(input.pressurePa, request.pressurePa)
        XCTAssertEqual(input.temperatureK, request.temperatureK, accuracy: 1e-10)
        XCTAssertEqual(input.impurityPpm[.nitrogen], 1000)
        XCTAssertEqual(input.impurityPpm[.water], 19000)
        XCTAssertEqual(model.sourceCalculationID, record.id)
        XCTAssertNil(model.result)
        model.temperatureText = "50"
        XCTAssertNil(model.sourceCalculationID)
    }

    func testInvalidOrOverfullInputCannotRun() {
        let model = StreamScreeningViewModel()
        for text in ["abc", "-1", "nan", "1000000"] {
            model.ppmTexts = [.water: text]
            XCTAssertNil(model.input)
            XCTAssertNotNil(model.inputError)
        }
    }

    func testEditingClearsResultsAndReferenceRequiresExplicitOptIn() async throws {
        let model = StreamScreeningViewModel(service: .init(provider: nil))
        model.loadReactiveExample()
        XCTAssertFalse(model.includeBinaryWaterReference)
        model.run()
        try await waitUntilFinished(model)
        XCTAssertNotNil(model.result)
        XCTAssertNil(model.result?.binaryWaterReference)
        model.includeBinaryWaterReference = true
        XCTAssertNil(model.result)
        model.run()
        try await waitUntilFinished(model)
        XCTAssertNotNil(model.result?.binaryWaterReference)
        model.ppmTexts[.water] = "100"
        XCTAssertNil(model.result)
        model.clear()
        XCTAssertTrue(model.ppmTexts.isEmpty)
        XCTAssertFalse(model.includeBinaryWaterReference)
    }

    func testCancelledRequestCannotReplaceEditedInputs() async throws {
        let model = StreamScreeningViewModel(service: .init(provider: nil))
        model.loadWaterExample()
        model.run()
        model.ppmTexts[.water] = "500"
        for _ in 0..<10 { await Task.yield() }
        XCTAssertNil(model.result)
        XCTAssertFalse(model.isRunning)
    }

    private func waitUntilFinished(_ model: StreamScreeningViewModel) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while model.isRunning && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(model.isRunning)
        XCTAssertNil(model.errorMessage)
    }
}
