import XCTest
@testable import PhaseXpertCore

final class PropertySweepRunnerTests: XCTestCase {
    private struct MockProvider: ThermodynamicModelProvider {
        let descriptor = ModelDescriptor(
            id: "sweep-test",
            name: "Sweep test provider",
            modelVersion: "1",
            providerVersion: "1",
            availability: .available,
            calculationMode: .local,
            supportedComponents: [.carbonDioxide],
            supportedProperties: [.density, .enthalpy],
            domain: ScientificDomain(
                minimumPressurePa: 1_000_000,
                maximumPressurePa: 20_000_000,
                minimumTemperatureK: 250,
                maximumTemperatureK: 350
            ),
            scientificBasis: "Deterministic test data only.",
            equationOrMethod: "Test fixture",
            limitations: ["Not a scientific provider."],
            references: []
        )

        let failingPressurePa: Double?
        let delayNanoseconds: UInt64

        init(
            failingPressurePa: Double? = nil,
            delayNanoseconds: UInt64 = 0
        ) {
            self.failingPressurePa = failingPressurePa
            self.delayNanoseconds = delayNanoseconds
        }

        func calculate(_ request: CalculationRequest) async throws -> CalculationResponse {
            if delayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            }
            if request.pressurePa == failingPressurePa {
                throw ProviderError.malformedResponse("Injected point failure.")
            }
            let property = request.requestedProperties.first ?? .density
            let value = request.pressurePa / 1_000_000 + request.temperatureK / 1_000
            return CalculationResponse(
                requestID: request.requestID,
                model: descriptor,
                phase: request.pressurePa >= 10_000_000 ? .dense : .gas,
                properties: [
                    PropertyValue(
                        property: property,
                        value: value,
                        unit: property == .density ? "kg/m³" : "J/kg",
                        status: .calculated
                    )
                ],
                solver: SolverMetadata(
                    method: "Deterministic test fixture",
                    converged: true,
                    durationMilliseconds: 0.1
                ),
                warnings: ["TEST DATA — NOT SCIENTIFIC"],
                isScientificResult: false
            )
        }

        func phaseEnvelope(_ request: PhaseEnvelopeRequest) async throws
            -> PhaseEnvelopeResponse {
            PhaseEnvelopeResponse(
                requestID: request.requestID,
                points: [],
                warnings: [],
                isAvailable: false
            )
        }
    }

    private func request(
        axis: PropertySweepAxis = .pressure,
        start: Double = 2_000_000,
        end: Double = 18_000_000,
        count: Int = 5,
        property: PropertyID = .density,
        modelID: String = "sweep-test"
    ) -> PropertySweepRequest {
        PropertySweepRequest(
            baseRequest: CalculationRequest(
                modelID: modelID,
                pressurePa: 10_000_000,
                temperatureK: 300,
                composition: [.init(component: .carbonDioxide, moleFraction: 1)],
                requestedProperties: [property],
                clientVersion: "test"
            ),
            axis: axis,
            startValueSI: start,
            endValueSI: end,
            pointCount: count,
            property: property
        )
    }

    func testPressureSweepUsesExactEndpointsAndFixedTemperature() async throws {
        let result = try await PropertySweepRunner(provider: MockProvider())
            .run(request())

        XCTAssertEqual(result.samples.count, 5)
        XCTAssertEqual(result.samples.first?.pressurePa, 2_000_000)
        XCTAssertEqual(result.samples.last?.pressurePa, 18_000_000)
        XCTAssertTrue(result.samples.allSatisfy { $0.temperatureK == 300 })
        XCTAssertEqual(result.successfulSampleCount, 5)
        XCTAssertEqual(result.failedSampleCount, 0)
        XCTAssertEqual(result.samples.first?.response?.model.id, "sweep-test")
    }

    func testTemperatureSweepUsesExactEndpointsAndFixedPressure() async throws {
        let result = try await PropertySweepRunner(provider: MockProvider())
            .run(request(axis: .temperature, start: 260, end: 340, count: 3))

        XCTAssertEqual(result.samples.map(\.temperatureK), [260, 300, 340])
        XCTAssertTrue(result.samples.allSatisfy { $0.pressurePa == 10_000_000 })
    }

    func testPerPointFailureIsRetainedWithoutFabricatedValue() async throws {
        let result = try await PropertySweepRunner(
            provider: MockProvider(failingPressurePa: 10_000_000)
        ).run(request())

        XCTAssertEqual(result.samples.count, 5)
        XCTAssertEqual(result.successfulSampleCount, 4)
        XCTAssertEqual(result.failedSampleCount, 1)
        let failed = try XCTUnwrap(result.samples.first { $0.pressurePa == 10_000_000 })
        XCTAssertNil(failed.response)
        XCTAssertNil(failed.value(for: .density)?.value)
        XCTAssertEqual(failed.errorMessage, "Injected point failure.")
    }

    func testNorthernLightsGeneralDryMixturePressureSweepScreensEveryPoint() async throws {
        let recorder = DryMixtureSweepRecorder()
        let provider = CoolPropProvider(engine: DryMixtureSweepEngine(recorder: recorder))
        let baseRequest = CalculationRequest(
            modelID: provider.descriptor.id,
            pressurePa: 4_318_000,
            temperatureK: 247.15,
            composition: northernLightsComposition(),
            requestedProperties: [.density],
            clientVersion: "test"
        )
        let sweep = PropertySweepRequest(
            baseRequest: baseRequest,
            axis: .pressure,
            startValueSI: 4_000_000,
            endValueSI: 4_636_000,
            pointCount: 3,
            property: .density
        )

        let result = try await PropertySweepRunner(provider: provider).run(sweep)

        XCTAssertEqual(result.samples.map(\.pressurePa), [4_000_000, 4_318_000, 4_636_000])
        XCTAssertEqual(result.successfulSampleCount, 2)
        XCTAssertEqual(result.failedSampleCount, 1)
        let reproduced = try XCTUnwrap(result.samples.first { $0.pressurePa == 4_318_000 })
        XCTAssertNil(reproduced.response)
        XCTAssertTrue(reproduced.errorMessage?.contains("Multiphase") == true)
        XCTAssertEqual(recorder.phaseClassificationCount, 3)
        XCTAssertEqual(recorder.imposedPhaseCount, 2)
        XCTAssertEqual(recorder.unhintedCalculationCount, 0)
    }

    func testRejectsUnsupportedPropertyAndInvalidBounds() async {
        let runner = PropertySweepRunner(provider: MockProvider())

        do {
            _ = try await runner.run(request(property: .thermalConductivity))
            XCTFail("Unsupported property should fail before provider execution.")
        } catch {
            XCTAssertEqual(
                error as? PropertySweepError,
                .unsupportedProperty(.thermalConductivity)
            )
        }

        do {
            _ = try await runner.run(request(start: 20_000_000, end: 2_000_000))
            XCTFail("Reversed bounds should fail.")
        } catch {
            guard let sweepError = error as? PropertySweepError,
                  case .invalidRange = sweepError
            else {
                return XCTFail("Expected invalidRange, received \(error)")
            }
        }
    }

    func testCancellationStopsSweepWithoutReturningPartialResult() async {
        let sweepRequest = request(count: PropertySweepRequest.maximumPointCount)
        let runner = PropertySweepRunner(
            provider: MockProvider(delayNanoseconds: 10_000_000)
        )
        let task = Task {
            try await runner.run(sweepRequest)
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Cancelled sweep should not return a result.")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, received \(error)")
        }
    }

    func testRejectsOutOfDomainRangeAndPointCount() async {
        let runner = PropertySweepRunner(provider: MockProvider())

        do {
            _ = try await runner.run(request(start: 500_000))
            XCTFail("Out-of-domain range should fail.")
        } catch {
            XCTAssertEqual(error as? PropertySweepError, .rangeOutsideDomain)
        }

        do {
            _ = try await runner.run(request(count: 1))
            XCTFail("One point should fail.")
        } catch {
            XCTAssertEqual(error as? PropertySweepError, .invalidPointCount(1))
        }
    }

    private func northernLightsComposition() -> [MixtureComponent] {
        [
            .init(component: .carbonDioxide, moleFraction: 0.9998309999999999),
            .init(component: .nitrogen, moleFraction: 0),
            .init(component: .oxygen, moleFraction: 0.000010000000000000001),
            .init(component: .argon, moleFraction: 0),
            .init(component: .methane, moleFraction: 0),
            .init(component: .hydrogen, moleFraction: 0.000050000000000000002),
            .init(component: .carbonMonoxide, moleFraction: 0.0001),
            .init(component: .hydrogenSulfide, moleFraction: 0.000009000000000000002)
        ]
    }
}

private final class DryMixtureSweepRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var phaseClassificationCount = 0
    private(set) var imposedPhaseCount = 0
    private(set) var unhintedCalculationCount = 0

    func recordPhaseClassification() {
        lock.withLock { phaseClassificationCount += 1 }
    }

    func recordImposedPhase() {
        lock.withLock { imposedPhaseCount += 1 }
    }

    func recordUnhintedCalculation() {
        lock.withLock { unhintedCalculationCount += 1 }
    }
}

private struct DryMixtureSweepEngine: CoolPropEngine {
    let isAvailable = true
    let libraryVersion = "8.0.0-sweep-test"
    let recorder: DryMixtureSweepRecorder

    func calculatePureCarbonDioxide(
        pressurePa: Double,
        temperatureK: Double
    ) async throws -> CoolPropEngineResult {
        throw ProviderError.modelUnavailable("Pure CO₂ is not used by this test engine.")
    }

    func calculateDryCarbonDioxideMixture(
        pressurePa: Double,
        temperatureK: Double,
        composition: [MixtureComponent]
    ) async throws -> CoolPropBinaryEngineResult {
        recorder.recordUnhintedCalculation()
        throw ProviderError.malformedResponse("Unscreened PT flash must not be used.")
    }

    func calculateDryCarbonDioxideMixture(
        pressurePa: Double,
        temperatureK: Double,
        composition: [MixtureComponent],
        imposedPhase: CoolPropSinglePhaseHint
    ) async throws -> CoolPropBinaryEngineResult {
        recorder.recordImposedPhase()
        return CoolPropBinaryEngineResult(
            densityKilogramsPerCubicMetre: pressurePa / 10_000,
            phaseIdentifier: imposedPhase == .gas ? "gas" : "liquid"
        )
    }

    func identifyDryCarbonDioxideMixturePhase(
        pressurePa: Double,
        temperatureK: Double,
        composition: [MixtureComponent]
    ) async throws -> CoolPropPhaseEngineResult {
        recorder.recordPhaseClassification()
        return CoolPropPhaseEngineResult(
            phaseIdentifier: pressurePa == 4_318_000 ? "twophase" : "gas"
        )
    }

    func pureCarbonDioxideSaturationLimits() async throws -> CoolPropSaturationLimits {
        throw ProviderError.modelUnavailable("Pure CO₂ saturation is not used by this test engine.")
    }

    func pureCarbonDioxideSaturationPressure(temperatureK: Double) async throws -> Double {
        throw ProviderError.modelUnavailable("Pure CO₂ saturation is not used by this test engine.")
    }
}
