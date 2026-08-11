import XCTest
@testable import PhaseXpertCore

final class PhaseMapTests: XCTestCase {
    private static let descriptor = ModelDescriptor(
        id: "phase-map-test-provider",
        name: "Phase Map test provider",
        modelVersion: "test",
        providerVersion: "test",
        availability: .available,
        calculationMode: .local,
        supportedComponents: [.carbonDioxide, .nitrogen],
        supportedProperties: [.density],
        domain: .initialCO2Transport,
        scientificBasis: "Deterministic Phase Map test double.",
        equationOrMethod: "Fixture",
        limitations: ["Test only."],
        references: []
    )

    private final class CallRecorder: @unchecked Sendable {
        private(set) var requests: [CalculationRequest] = []

        func record(_ request: CalculationRequest) {
            requests.append(request)
        }
    }

    private actor ProgressRecorder {
        private var values: [PhaseMapProgress] = []

        func record(_ progress: PhaseMapProgress) {
            values.append(progress)
        }

        func last() -> PhaseMapProgress? {
            values.last
        }
    }

    private struct FixtureProvider: ThermodynamicModelProvider {
        let descriptor: ModelDescriptor
        let recorder: CallRecorder
        let response: @Sendable (CalculationRequest) throws -> CalculationResponse

        init(
            descriptor: ModelDescriptor = PhaseMapTests.descriptor,
            recorder: CallRecorder = CallRecorder(),
            response: @escaping @Sendable (CalculationRequest) throws -> CalculationResponse
        ) {
            self.descriptor = descriptor
            self.recorder = recorder
            self.response = response
        }

        func calculate(_ request: CalculationRequest) async throws -> CalculationResponse {
            recorder.record(request)
            return try response(request)
        }

        func phaseEnvelope(_ request: PhaseEnvelopeRequest) async throws -> PhaseEnvelopeResponse {
            XCTFail("Phase Map must not request a phase envelope.")
            return PhaseEnvelopeResponse(requestID: request.requestID, points: [], warnings: [], isAvailable: false)
        }
    }

    func testAutomaticRangeUsesSpecifiedOperatingPointExtents() {
        let range = PhaseMapRange.automatic(pressurePa: 12_000_000, temperatureK: 310)

        XCTAssertEqual(range.pressureMinimumPa, 6_000_000)
        XCTAssertEqual(range.pressureMaximumPa, 18_000_000)
        XCTAssertEqual(range.temperatureMinimumK, 285)
        XCTAssertEqual(range.temperatureMaximumK, 335)
    }

    func testGridConstructionCountsAndOperatingPointTreatment() throws {
        let five = request(resolution: .five)
        let ten = request(resolution: .ten)
        let twenty = request(resolution: .twenty)

        let fivePoints = try PhaseMapGridBuilder.points(for: five)
        let tenPoints = try PhaseMapGridBuilder.points(for: ten)
        let twentyPoints = try PhaseMapGridBuilder.points(for: twenty)

        XCTAssertEqual(fivePoints.count, 25)
        XCTAssertEqual(tenPoints.count, 101)
        XCTAssertEqual(twentyPoints.count, 401)
        XCTAssertEqual(fivePoints.filter(\.isOperatingPoint).count, 1)
        XCTAssertEqual(tenPoints.filter(\.isOperatingPoint).count, 1)
        XCTAssertEqual(twentyPoints.filter(\.isOperatingPoint).count, 1)
        XCTAssertEqual(fivePoints[12].pressurePa, five.pressurePa)
        XCTAssertEqual(fivePoints[12].temperatureK, five.temperatureK)
        XCTAssertEqual(
            tenPoints.filter {
                $0.pressurePa == ten.pressurePa && $0.temperatureK == ten.temperatureK
            }.count,
            1
        )
    }

    func testInvalidRangesBlockGridConstruction() {
        let negativePressure = request(range: PhaseMapRange(
            pressureMinimumPa: -1,
            pressureMaximumPa: 2_000_000,
            temperatureMinimumK: 280,
            temperatureMaximumK: 320
        ))
        let outsideOperatingPoint = request(range: PhaseMapRange(
            pressureMinimumPa: 1_000_000,
            pressureMaximumPa: 2_000_000,
            temperatureMinimumK: 280,
            temperatureMaximumK: 320
        ))

        XCTAssertTrue(PhaseMapGridBuilder.validationIssues(for: negativePressure).contains {
            $0.code == .invalidPressureRange
        })
        XCTAssertTrue(PhaseMapGridBuilder.validationIssues(for: outsideOperatingPoint).contains {
            $0.code == .operatingPointOutsideRange
        })
        XCTAssertThrowsError(try PhaseMapGridBuilder.points(for: negativePressure))
    }

    func testPureCompositionRejectedForPhaseMap() {
        let request = request(composition: [.init(component: .carbonDioxide, moleFraction: 1)])

        XCTAssertTrue(PhaseMapGridBuilder.validationIssues(for: request).contains {
            $0.code == .invalidComposition
        })
    }

    func testProviderClassificationMappingPreservesUnsupportedStates() {
        XCTAssertEqual(PhaseMapClassificationAdapter.map(.gas).classification, .gas)
        XCTAssertEqual(PhaseMapClassificationAdapter.map(.liquid).classification, .liquid)
        XCTAssertEqual(PhaseMapClassificationAdapter.map(.twoPhase).classification, .multiphase)
        XCTAssertEqual(PhaseMapClassificationAdapter.map(.solid).classification, .solid)
        XCTAssertEqual(PhaseMapClassificationAdapter.map(.dense).classification, .dense)
        XCTAssertEqual(PhaseMapClassificationAdapter.map(.supercritical).classification, .supercritical)

        let unknown = PhaseMapClassificationAdapter.map(.unknown)
        XCTAssertEqual(unknown.classification, .unknown)
        XCTAssertFalse(unknown.isSupported)

        let unavailable = PhaseMapClassificationAdapter.map(.unavailable)
        XCTAssertEqual(unavailable.classification, .unknown)
        XCTAssertFalse(unavailable.isSupported)
    }

    func testRunnerEvaluatesEveryPointAndContinuesAfterPointFailure() async throws {
        let recorder = CallRecorder()
        let provider = FixtureProvider(recorder: recorder) { request in
            if request.pressurePa == 8_000_000 && request.temperatureK == 300 {
                throw ProviderError.malformedResponse("Fixture failure.")
            }
            return Self.response(
                request: request,
                phase: request.pressurePa > 12_000_000 ? .liquid : .gas,
                converged: request.temperatureK != 275
            )
        }
        let progress = ProgressRecorder()

        let result = try await PhaseMapRunner(provider: provider).run(request()) {
            await progress.record($0)
        }
        let finalProgress = await progress.last()

        XCTAssertEqual(result.evaluations.count, 25)
        XCTAssertEqual(recorder.requests.count, 25)
        XCTAssertEqual(finalProgress, PhaseMapProgress(completedCount: 25, totalCount: 25))
        XCTAssertEqual(result.failedCount, 1)
        XCTAssertGreaterThan(result.nonConvergedCount, 0)
        XCTAssertGreaterThan(result.successfulCount, 0)
        XCTAssertNotNil(result.evaluations.first { $0.failureReason == "Fixture failure." })
    }

    func testRunnerUsesExpectedProviderCallCountForEvenGrid() async throws {
        let recorder = CallRecorder()
        let provider = FixtureProvider(recorder: recorder) {
            Self.response(request: $0, phase: .supercritical)
        }

        let result = try await PhaseMapRunner(provider: provider).run(request(resolution: .ten))

        XCTAssertEqual(result.evaluations.count, 101)
        XCTAssertEqual(recorder.requests.count, 101)
        XCTAssertEqual(result.operatingPoint?.classification.displayName, "Supercritical")
    }

    func testPhaseMapCodableRoundTrip() throws {
        let result = PhaseMapResult(
            request: request(),
            model: Self.descriptor,
            calculatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            evaluations: [
                PhaseMapEvaluation(
                    point: .init(pressurePa: 12_000_000, temperatureK: 300, isOperatingPoint: true),
                    classification: PhaseMapClassificationAdapter.map(.gas),
                    solver: .init(method: "Fixture", converged: true, durationMilliseconds: 1)
                )
            ],
            warnings: ["Discrete flash map."]
        )

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(PhaseMapResult.self, from: data)

        XCTAssertEqual(decoded, result)
    }

    private func request(
        resolution: PhaseMapResolution = .five,
        range: PhaseMapRange = PhaseMapRange(
            pressureMinimumPa: 8_000_000,
            pressureMaximumPa: 16_000_000,
            temperatureMinimumK: 275,
            temperatureMaximumK: 325
        ),
        composition: [MixtureComponent] = [
            .init(component: .carbonDioxide, moleFraction: 0.97),
            .init(component: .nitrogen, moleFraction: 0.03)
        ]
    ) -> PhaseMapRequest {
        PhaseMapRequest(
            modelID: Self.descriptor.id,
            pressurePa: 12_000_000,
            temperatureK: 300,
            composition: composition,
            range: range,
            resolution: resolution,
            clientVersion: "test"
        )
    }

    private static func response(
        request: CalculationRequest,
        phase: PhaseRegion,
        converged: Bool = true
    ) -> CalculationResponse {
        CalculationResponse(
            requestID: request.requestID,
            model: descriptor,
            phase: phase,
            properties: [
                PropertyValue(
                    property: .density,
                    value: 100,
                    unit: "kg/m³",
                    status: .calculated,
                    message: "Fixture density."
                )
            ],
            solver: SolverMetadata(
                method: "Fixture flash",
                converged: converged,
                durationMilliseconds: 1
            ),
            warnings: [],
            isScientificResult: false
        )
    }
}
