import XCTest
@testable import PhaseXpertCore

final class StreamScreeningTests: XCTestCase {
    private actor RecordingProvider: ThermodynamicModelProvider {
        nonisolated let descriptor = ModelDescriptor(
            id: "screening-test", name: "Test only", modelVersion: "fixture", providerVersion: "fixture",
            availability: .preliminary, calculationMode: .local,
            supportedComponents: Set(ComponentID.allCases), supportedProperties: [.density],
            domain: .initialCO2Transport, scientificBasis: "Test fixture", equationOrMethod: "None",
            limitations: ["No scientific result"], references: [])
        private(set) var requests: [CalculationRequest] = []
        func calculate(_ request: CalculationRequest) async throws -> CalculationResponse {
            requests.append(request)
            return CalculationResponse(requestID: request.requestID, model: descriptor, phase: .unknown,
                properties: [], solver: .init(method: "Test fixture", converged: true, durationMilliseconds: 0),
                warnings: ["Test only"], isScientificResult: false)
        }
        nonisolated func phaseEnvelope(_ request: PhaseEnvelopeRequest) async throws -> PhaseEnvelopeResponse {
            throw ProviderError.modelUnavailable("Test fixture has no envelope")
        }
    }

    private func input(_ ppm: [StreamScreeningSpecies: Double], reference: Bool = false,
                       pressure: Double = 3_000_000, temperature: Double = 313.15) -> StreamScreeningInput {
        .init(pressurePa: pressure, temperatureK: temperature, impurityPpm: ppm,
              includeBinaryWaterReference: reference)
    }

    func testOriginalCompositionReachesProviderWithoutReactionOrRenormalization() async throws {
        let provider = RecordingProvider()
        let original = input([.oxygen: 40, .hydrogenSulfide: 80])
        let output = try await StreamScreeningService(provider: provider).screen(original, clientVersion: "test")
        XCTAssertEqual(output.reactionResult?.finalPpm[.elementalSulfur] ?? .nan, 10, accuracy: 1e-10)
        let requests = await provider.requests
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.composition, try original.thermophysicalComposition())
        XCTAssertEqual(request.composition.first { $0.component == .hydrogenSulfide }?.moleFraction, 80e-6)
        XCTAssertFalse(request.composition.contains { $0.component == .water })
        guard case .unavailable(let water) = output.streamWater else { return XCTFail("Reaction water must not enter equilibrium") }
        XCTAssertEqual(water.kind, .noWater)
    }

    func testSO2AndNO2AreNotDroppedToObtainThermophysicalResult() async throws {
        let provider = RecordingProvider()
        let output = try await StreamScreeningService(provider: provider).screen(
            input([.water: 100, .sulfurDioxide: 10, .nitrogenDioxide: 10]), clientVersion: "test")
        XCTAssertEqual(output.reactionResult?.finalPpm[.sulfuricAcid] ?? .nan, 10, accuracy: 1e-10)
        guard case .unavailable(let issue) = output.thermophysical else { return XCTFail("EOS must reject unmapped impurities") }
        XCTAssertEqual(issue.kind, .unsupportedComposition)
        let requests = await provider.requests
        XCTAssertTrue(requests.isEmpty)
        guard case .unavailable(let water) = output.streamWater else { return XCTFail("Mixture is not binary") }
        XCTAssertEqual(water.kind, .unsupportedComposition)
        XCTAssertNil(output.binaryWaterReference)
    }

    func testOptInReferenceIsSeparateAndKeepsOriginalWaterBasis() async throws {
        let original = input([.water: 20_000, .oxygen: 15, .hydrogenSulfide: 3, .nitrogenDioxide: 15], reference: true)
        let output = try await StreamScreeningService(provider: nil).screen(original, clientVersion: "test")
        XCTAssertEqual(output.acidFormationEstimated, true)
        guard case .unavailable = output.streamWater,
              case .result(let reference) = output.binaryWaterReference else { return XCTFail("Separate reference expected") }
        XCTAssertEqual(reference.currentWaterPPM ?? .nan, 20_000, accuracy: 1e-8)
        XCTAssertEqual(reference.waterStatus, .aqueousWaterExpected)
        XCTAssertTrue(output.binaryReferenceWaterExpected)
        XCTAssertNotEqual(output.reactionResult?.finalPpm[.water], reference.currentWaterPPM)
        XCTAssertEqual(output.input, original)
    }

    func testBinaryStreamUsesExistingWaterModelEvenWithoutNativeEngine() async throws {
        let original = input([.water: 20_000])
        let output = try await StreamScreeningService(provider: nil).screen(original, clientVersion: "test")
        guard case .result(let water) = output.streamWater else { return XCTFail("Binary water assessment should work independently") }
        let expected = try CarbonDioxideWaterEquilibrium.standard.equilibrium(
            pressurePa: original.pressurePa, temperatureK: original.temperatureK, currentWaterMoleFraction: 0.02)
        XCTAssertEqual(water.waterStatus, expected.waterStatus)
        XCTAssertEqual(water.waterInCarbonDioxideRichPhasePPM, expected.waterInCarbonDioxideRichPhasePPM, accuracy: 1e-9)
        XCTAssertNil(output.binaryWaterReference)
        guard case .unavailable(let issue) = output.thermophysical else { return XCTFail("No EOS engine was provided") }
        XCTAssertEqual(issue.kind, .modelUnavailable)
    }

    func testWaterDomainFailureDoesNotSuppressReactionResult() async throws {
        let output = try await StreamScreeningService(provider: nil).screen(
            input([.water: 100, .sulfurDioxide: 10, .nitrogenDioxide: 10], reference: true,
                  pressure: 20_000_000, temperature: 293.15), clientVersion: "test")
        XCTAssertEqual(output.acidFormationEstimated, true)
        guard case .unavailable(let issue) = output.binaryWaterReference else { return XCTFail("No extrapolation") }
        XCTAssertEqual(issue.kind, .outsideDomain)
        XCTAssertFalse(output.binaryReferenceWaterExpected)
    }

    func testSpectatorSpeciesRemainInEOSInputAndPreventActualMixtureWaterPrediction() async throws {
        let provider = RecordingProvider()
        let original = input([.water: 500, .nitrogen: 1000, .argon: 100])
        let output = try await StreamScreeningService(provider: provider).screen(original, clientVersion: "test")
        let requests = await provider.requests
        XCTAssertEqual(requests.first?.composition.count, 4)
        XCTAssertEqual(output.reactionResult?.input, original.reactionInput)
        guard case .unavailable(let issue) = output.streamWater else { return XCTFail("Spectators cannot be ignored") }
        XCTAssertEqual(issue.kind, .unsupportedComposition)
    }

    func testInvalidInputsAreRejectedWithoutCorrection() async {
        for invalid in [input([.water: -1]), input([.water: .nan]), input([.oxygen: .infinity]),
                        input([.water: 1_000_000]), input([.nitrogen: 999_990, .water: 20]),
                        input([:], pressure: 0), input([:], temperature: 0)] {
            do {
                _ = try await StreamScreeningService(provider: nil).screen(invalid, clientVersion: "test")
                XCTFail("Invalid shared inputs must fail before calculation")
            } catch is StreamScreeningInputError { }
            catch { XCTFail("Unexpected error: \(error)") }
        }
    }

    func testReactionFailureDoesNotSuppressWaterOrProperties() async throws {
        let provider = RecordingProvider()
        let service = StreamScreeningService(provider: provider, reactionModel: { _ in
            throw ToCoMoError.didNotTerminate(steps: ToCoMoModel.maximumSteps)
        })
        let output = try await service.screen(input([.water: 20_000]), clientVersion: "test")
        guard case .unavailable = output.reactions,
              case .result = output.streamWater,
              case .result = output.thermophysical else { return XCTFail("Each route must remain independent") }
        XCTAssertNil(output.acidFormationEstimated)
    }

    func testAllAppComponentsCanBeRepresentedWithoutOmission() {
        XCTAssertEqual(Set(StreamScreeningSpecies.allCases.compactMap(\.componentID)),
                       Set(ComponentID.allCases).subtracting([.carbonDioxide]))
    }
}
