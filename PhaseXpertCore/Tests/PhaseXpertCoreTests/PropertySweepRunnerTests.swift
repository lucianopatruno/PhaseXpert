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
        let task = Task {
            try await PropertySweepRunner(
                provider: MockProvider(delayNanoseconds: 10_000_000)
            ).run(request(count: PropertySweepRequest.maximumPointCount))
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
}
