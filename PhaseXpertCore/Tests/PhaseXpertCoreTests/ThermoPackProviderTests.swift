import XCTest
@testable import PhaseXpertCore

final class ThermoPackProviderTests: XCTestCase {
    private struct MockEngine: ThermoPackEngine {
        let isAvailable: Bool
        let libraryVersion: String
        let bridgeVersion: String
        let configurationIdentifier: String
        var state: ThermoPackStateResult
        var envelope: ThermoPackEnvelopeResult
        var error: ProviderError?
        var delayNanoseconds: UInt64 = 0

        init(
            isAvailable: Bool = true,
            libraryVersion: String = "2.2.4+ca75d8e",
            bridgeVersion: String = "1.0.0",
            configurationIdentifier: String =
                "PR / Classic / Classic-vdW / PR_kij.json vdW-18 ref=Default",
            state: ThermoPackStateResult = .init(
                phase: .liquid,
                densityKilogramsPerCubicMetre: 800,
                molarMassKilogramsPerMole: 0.0435,
                specificVolumeCubicMetresPerKilogram: 0.00125,
                compressibilityFactor: 0.7,
                enthalpyJoulesPerKilogram: 120_000,
                entropyJoulesPerKilogramKelvin: 1_200,
                isobaricHeatCapacityJoulesPerKilogramKelvin: 2_000
            ),
            envelope: ThermoPackEnvelopeResult = .init(
                points: [
                    .init(temperatureK: 230, pressurePa: 1_000_000, branch: .bubble),
                    .init(temperatureK: 250, pressurePa: 2_000_000, branch: .bubble),
                    .init(temperatureK: 250, pressurePa: 1_900_000, branch: .dew),
                    .init(temperatureK: 230, pressurePa: 900_000, branch: .dew)
                ],
                attemptedCalls: 4,
                failedCalls: 0,
                complete: true,
                timedOut: false,
                durationMilliseconds: 8
            ),
            error: ProviderError? = nil,
            delayNanoseconds: UInt64 = 0
        ) {
            self.isAvailable = isAvailable
            self.libraryVersion = libraryVersion
            self.bridgeVersion = bridgeVersion
            self.configurationIdentifier = configurationIdentifier
            self.state = state
            self.envelope = envelope
            self.error = error
            self.delayNanoseconds = delayNanoseconds
        }

        func calculate(
            pressurePa: Double,
            temperatureK: Double,
            carbonDioxideMoleFraction: Double,
            nitrogenMoleFraction: Double
        ) async throws -> ThermoPackStateResult {
            if delayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            }
            if let error { throw error }
            return state
        }

        func phaseEnvelope(
            carbonDioxideMoleFraction: Double,
            nitrogenMoleFraction: Double,
            bounds: ScientificDomain,
            maximumPointsPerBranch: Int,
            maximumElapsedMilliseconds: Double
        ) async throws -> ThermoPackEnvelopeResult {
            if delayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            }
            if let error { throw error }
            return envelope
        }
    }

    func testProviderIdentityAndExactConfigurationRoundTrip() throws {
        let descriptor = ThermoPackProvider(engine: MockEngine()).descriptor
        XCTAssertEqual(descriptor.id, "thermopack-pr-classic-co2-n2")
        XCTAssertTrue(descriptor.modelVersion.contains("2.2.4"))
        XCTAssertEqual(descriptor.providerVersion, "1.0.0")
        XCTAssertTrue(descriptor.equationOrMethod.contains("Peng–Robinson"))
        XCTAssertTrue(descriptor.equationOrMethod.contains("Classic"))
        XCTAssertTrue(descriptor.coefficientSetVersion?.contains("vdW-18") == true)
        XCTAssertTrue(descriptor.coefficientSetVersion?.contains("ref=Default") == true)
        XCTAssertTrue(descriptor.coefficientSetVersion?.contains("ca75d8e095e8") == true)

        let data = try JSONEncoder().encode(descriptor)
        XCTAssertEqual(
            try JSONDecoder().decode(ModelDescriptor.self, from: data),
            descriptor
        )
    }

    func testCompositionMustBeExactAndSupportsOnlyCO2N2() async {
        let provider = ThermoPackProvider(engine: MockEngine())
        await assertThrows(
            provider,
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.97),
                .init(component: .nitrogen, moleFraction: 0.0299)
            ],
            expected: .invalidRequest(
                "ThermoPack mole fractions must sum to one without implicit normalization."
            )
        )
        await assertThrows(
            provider,
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.97),
                .init(component: .oxygen, moleFraction: 0.03)
            ],
            expected: .unsupportedComponent(.oxygen)
        )
    }

    func testTenPercentNitrogenGuardAndApplicability() async {
        let provider = ThermoPackProvider(engine: MockEngine())
        XCTAssertTrue(provider.applicabilityIssues(for: [
            .init(component: .carbonDioxide, moleFraction: 0.89),
            .init(component: .nitrogen, moleFraction: 0.11)
        ]).contains { $0.code == .componentOutsideModelRange })
        await assertThrows(
            provider,
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.89),
                .init(component: .nitrogen, moleFraction: 0.11)
            ],
            expected: .invalidRequest(
                "ThermoPack PR supports 90–100 mol% CO₂ and 0–10 mol% N₂ in this milestone."
            )
        )
    }

    func testFinitePropertiesAndUnavailablePropertyNeverUseCoolProp() async throws {
        let provider = ThermoPackProvider(engine: MockEngine())
        let response = try await provider.calculate(request(
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.97),
                .init(component: .nitrogen, moleFraction: 0.03)
            ],
            properties: [.density, .enthalpy, .dynamicViscosity]
        ))
        XCTAssertEqual(
            response.properties.first(where: { $0.property == .density })?.value,
            800
        )
        let unavailable = try XCTUnwrap(
            response.properties.first(where: { $0.property == .dynamicViscosity })
        )
        XCTAssertEqual(unavailable.status, .unavailable)
        XCTAssertTrue(unavailable.message?.contains("no CoolProp value") == true)
        XCTAssertTrue(response.warnings.contains { $0.contains("no CoolProp") })
    }

    func testNonFinitePropertyIsFailed() async throws {
        let engine = MockEngine(state: .init(
            phase: .liquid,
            densityKilogramsPerCubicMetre: .nan,
            molarMassKilogramsPerMole: 0.044,
            specificVolumeCubicMetresPerKilogram: 0.001,
            compressibilityFactor: 0.8,
            enthalpyJoulesPerKilogram: 100,
            entropyJoulesPerKilogramKelvin: 10,
            isobaricHeatCapacityJoulesPerKilogramKelvin: 1_000
        ))
        let response = try await ThermoPackProvider(engine: engine).calculate(
            request(properties: [.density])
        )
        XCTAssertEqual(response.properties.first?.status, .failed)
        XCTAssertNil(response.properties.first?.value)
    }

    func testTwoPhaseMakesBulkPropertiesUnavailableAndKeepsVaporFraction() async throws {
        let engine = MockEngine(state: .init(
            phase: .twoPhase,
            vaporFraction: 0.25
        ))
        let response = try await ThermoPackProvider(engine: engine).calculate(
            request(properties: [.density, .vapourFraction])
        )
        XCTAssertEqual(response.phase, .twoPhase)
        XCTAssertEqual(
            response.properties.first(where: { $0.property == .density })?.status,
            .unavailable
        )
        XCTAssertEqual(
            response.properties.first(where: { $0.property == .vapourFraction })?.value,
            0.25
        )
    }

    func testNativeErrorIsPropagatedWithoutFallback() async {
        let expected = ProviderError.malformedResponse("native failure")
        let provider = ThermoPackProvider(engine: MockEngine(error: expected))
        do {
            _ = try await provider.calculate(request())
            XCTFail("Expected native error")
        } catch let error as ProviderError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testEnvelopeKeepsBubbleDewBranchesAndIncompleteStatus() async throws {
        let result = ThermoPackEnvelopeResult(
            points: [
                .init(temperatureK: 230, pressurePa: 1_000_000, branch: .bubble),
                .init(temperatureK: 250, pressurePa: 2_000_000, branch: .bubble),
                .init(temperatureK: 249, pressurePa: 1_900_000, branch: .dew),
                .init(temperatureK: 229, pressurePa: 900_000, branch: .dew)
            ],
            attemptedCalls: 12,
            failedCalls: 2,
            complete: false,
            timedOut: true,
            durationMilliseconds: 5_000
        )
        let response = try await ThermoPackProvider(
            engine: MockEngine(envelope: result)
        ).phaseEnvelope(envelopeRequest())
        XCTAssertTrue(response.isAvailable)
        XCTAssertEqual(response.points.filter { $0.branch == .bubble }.count, 2)
        XCTAssertEqual(response.points.filter { $0.branch == .dew }.count, 2)
        XCTAssertFalse(try XCTUnwrap(response.solver).converged)
        XCTAssertEqual(response.solver?.iterationCount, 12)
        XCTAssertTrue(response.warnings.contains { $0.contains("incomplete") })
        XCTAssertTrue(response.warnings.contains { $0.contains("5000 ms") })
    }

    func testBranchDeficientEnvelopeIsUnavailable() async throws {
        let result = ThermoPackEnvelopeResult(
            points: [
                .init(temperatureK: 230, pressurePa: 1_000_000, branch: .bubble),
                .init(temperatureK: 250, pressurePa: 2_000_000, branch: .bubble)
            ],
            attemptedCalls: 4,
            failedCalls: 2,
            complete: false,
            timedOut: false,
            durationMilliseconds: 10
        )
        let response = try await ThermoPackProvider(
            engine: MockEngine(envelope: result)
        ).phaseEnvelope(envelopeRequest())
        XCTAssertFalse(response.isAvailable)
        XCTAssertTrue(response.points.isEmpty)
    }

    func testCancellationPreventsDelayedResultCompletion() async {
        let provider = ThermoPackProvider(
            engine: MockEngine(delayNanoseconds: 2_000_000_000)
        )
        let task = Task { try await provider.calculate(request()) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCalculationSnapshotCodablePreservesThermoPackProvider() async throws {
        let provider = ThermoPackProvider(engine: MockEngine())
        let calculationRequest = request()
        let response = try await provider.calculate(calculationRequest)
        let record = CalculationRecord(
            request: calculationRequest,
            input: .init(
                pressureValue: 150,
                pressureUnit: .bara,
                pressurePa: calculationRequest.pressurePa,
                temperatureValue: 20,
                temperatureUnit: .celsius,
                temperatureK: calculationRequest.temperatureK,
                originalComposition: [
                    .init(component: .carbonDioxide, value: 970_000, unit: .partsPerMillion),
                    .init(component: .nitrogen, value: 30_000, unit: .partsPerMillion)
                ]
            ),
            response: response,
            application: .init(version: "test", build: "1")
        )
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(CalculationRecord.self, from: data)
        XCTAssertEqual(decoded, record)
        XCTAssertEqual(decoded.response.model.id, "thermopack-pr-classic-co2-n2")
        XCTAssertTrue(decoded.response.model.coefficientSetVersion?.contains("vdW-18") == true)
    }

    func testScientificReferenceURLConstruction() {
        XCTAssertEqual(
            SourceReference(
                authors: "A",
                title: "B",
                year: 2026,
                doiOrURL: "10.1021/acs.iecr.7b00317"
            ).destinationURL?.absoluteString,
            "https://doi.org/10.1021/acs.iecr.7b00317"
        )
        XCTAssertNotNil(SourceReference(
            authors: "A", title: "B", year: 2026,
            doiOrURL: "https://github.com/thermotools/thermopack"
        ).destinationURL)
        XCTAssertNil(SourceReference(
            authors: "A", title: "B", year: 2026,
            doiOrURL: "http://example.com"
        ).destinationURL)
        XCTAssertNil(SourceReference(
            authors: "A", title: "B", year: 2026,
            doiOrURL: "not a url"
        ).destinationURL)
    }

    private func request(
        composition: [MixtureComponent] = [
            .init(component: .carbonDioxide, moleFraction: 0.97),
            .init(component: .nitrogen, moleFraction: 0.03)
        ],
        properties: Set<PropertyID> = [.density]
    ) -> CalculationRequest {
        CalculationRequest(
            modelID: "thermopack-pr-classic-co2-n2",
            pressurePa: 15_000_000,
            temperatureK: 293.15,
            composition: composition,
            requestedProperties: properties,
            clientVersion: "test"
        )
    }

    private func envelopeRequest() -> PhaseEnvelopeRequest {
        PhaseEnvelopeRequest(
            modelID: "thermopack-pr-classic-co2-n2",
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.97),
                .init(component: .nitrogen, moleFraction: 0.03)
            ]
        )
    }

    private func assertThrows(
        _ provider: ThermoPackProvider<MockEngine>,
        composition: [MixtureComponent],
        expected: ProviderError
    ) async {
        do {
            _ = try await provider.calculate(request(composition: composition))
            XCTFail("Expected provider error")
        } catch let error as ProviderError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
