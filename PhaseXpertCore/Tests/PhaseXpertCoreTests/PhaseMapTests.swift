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
        try assertValidGrid(fivePoints, request: five)
        try assertValidGrid(tenPoints, request: ten)
        try assertValidGrid(twentyPoints, request: twenty)
    }

    func testTenByTenBaseGridUsesUniformInclusiveAxesAndAddsOffGridOperatingPointOnce() throws {
        let request = request(resolution: .ten)
        let points = try PhaseMapGridBuilder.points(for: request)
        let basePoints = points.filter { !$0.isOperatingPoint }
        let pressureAxis = uniqueSorted(basePoints.map(\.pressurePa))
        let temperatureAxis = uniqueSorted(basePoints.map(\.temperatureK))

        XCTAssertEqual(basePoints.count, 100)
        XCTAssertEqual(points.count, 101)
        XCTAssertEqual(pressureAxis.count, 10)
        XCTAssertEqual(temperatureAxis.count, 10)
        assertUniformAxis(
            pressureAxis,
            minimum: request.range.pressureMinimumPa,
            maximum: request.range.pressureMaximumPa,
            operatingValue: request.pressurePa
        )
        assertUniformAxis(
            temperatureAxis,
            minimum: request.range.temperatureMinimumK,
            maximum: request.range.temperatureMaximumK,
            operatingValue: request.temperatureK
        )
        XCTAssertEqual(points.filter(\.isOperatingPoint).count, 1)
        try assertValidGrid(points, request: request)
    }

    func testTwentyByTwentyBaseGridUsesUniformInclusiveAxesAndAddsOffGridOperatingPointOnce() throws {
        let request = request(resolution: .twenty)
        let points = try PhaseMapGridBuilder.points(for: request)
        let basePoints = points.filter { !$0.isOperatingPoint }
        let pressureAxis = uniqueSorted(basePoints.map(\.pressurePa))
        let temperatureAxis = uniqueSorted(basePoints.map(\.temperatureK))

        XCTAssertEqual(basePoints.count, 400)
        XCTAssertEqual(points.count, 401)
        XCTAssertEqual(pressureAxis.count, 20)
        XCTAssertEqual(temperatureAxis.count, 20)
        assertUniformAxis(
            pressureAxis,
            minimum: request.range.pressureMinimumPa,
            maximum: request.range.pressureMaximumPa,
            operatingValue: request.pressurePa
        )
        assertUniformAxis(
            temperatureAxis,
            minimum: request.range.temperatureMinimumK,
            maximum: request.range.temperatureMaximumK,
            operatingValue: request.temperatureK
        )
        XCTAssertEqual(points.filter(\.isOperatingPoint).count, 1)
        try assertValidGrid(points, request: request)
    }

    func testGridConstructionSupportsAsymmetricRanges() throws {
        let asymmetricRange = PhaseMapRange(
            pressureMinimumPa: 10_000_000,
            pressureMaximumPa: 21_000_000,
            temperatureMinimumK: 291,
            temperatureMaximumK: 341
        )
        let request = request(range: asymmetricRange)

        let points = try PhaseMapGridBuilder.points(for: request)

        XCTAssertEqual(points.count, 26)
        XCTAssertEqual(points.filter(\.isOperatingPoint).count, 1)
        XCTAssertEqual(points.first(where: \.isOperatingPoint)?.pressurePa, request.pressurePa)
        XCTAssertEqual(points.first(where: \.isOperatingPoint)?.temperatureK, request.temperatureK)
        try assertValidGrid(points, request: request)
    }

    func testGridConstructionAcceptsOperatingPointsCloseToBoundaries() throws {
        let closeRange = PhaseMapRange(
            pressureMinimumPa: 11_999_999.999,
            pressureMaximumPa: 12_000_100,
            temperatureMinimumK: 299.999,
            temperatureMaximumK: 301
        )
        let fiveRequest = request(range: closeRange)
        let tenRequest = request(resolution: .ten, range: closeRange)

        let fivePoints = try PhaseMapGridBuilder.points(for: fiveRequest)
        let tenPoints = try PhaseMapGridBuilder.points(for: tenRequest)

        XCTAssertEqual(fivePoints.count, 26)
        XCTAssertEqual(tenPoints.count, 101)
        try assertValidGrid(fivePoints, request: fiveRequest)
        try assertValidGrid(tenPoints, request: tenRequest)
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

    func testOperatingPointEqualToBoundaryIsBlocked() {
        let pressureAtMinimum = request(range: PhaseMapRange(
            pressureMinimumPa: 12_000_000,
            pressureMaximumPa: 16_000_000,
            temperatureMinimumK: 275,
            temperatureMaximumK: 325
        ))
        let pressureAtMaximum = request(range: PhaseMapRange(
            pressureMinimumPa: 8_000_000,
            pressureMaximumPa: 12_000_000,
            temperatureMinimumK: 275,
            temperatureMaximumK: 325
        ))
        let temperatureAtMinimum = request(range: PhaseMapRange(
            pressureMinimumPa: 8_000_000,
            pressureMaximumPa: 16_000_000,
            temperatureMinimumK: 300,
            temperatureMaximumK: 325
        ))
        let temperatureAtMaximum = request(range: PhaseMapRange(
            pressureMinimumPa: 8_000_000,
            pressureMaximumPa: 16_000_000,
            temperatureMinimumK: 275,
            temperatureMaximumK: 300
        ))

        for candidate in [
            pressureAtMinimum,
            pressureAtMaximum,
            temperatureAtMinimum,
            temperatureAtMaximum
        ] {
            XCTAssertTrue(PhaseMapGridBuilder.validationIssues(for: candidate).contains {
                $0.code == .operatingPointOutsideRange
                    && $0.message.contains("strictly inside")
            })
            XCTAssertThrowsError(try PhaseMapGridBuilder.points(for: candidate))
        }
    }

    func testEvenGridReusesNaturallyCoincidentOperatingPointWithoutDuplicate() throws {
        let request = request(
            resolution: .ten,
            range: PhaseMapRange(
                pressureMinimumPa: 8_000_000,
                pressureMaximumPa: 17_000_000,
                temperatureMinimumK: 296,
                temperatureMaximumK: 305
            )
        )
        let points = try PhaseMapGridBuilder.points(for: request)
        let operatingPoints = points.filter(\.isOperatingPoint)
        let pressureAxis = uniqueSorted(points.map(\.pressurePa))
        let temperatureAxis = uniqueSorted(points.map(\.temperatureK))

        XCTAssertEqual(points.count, 100)
        XCTAssertEqual(operatingPoints.count, 1)
        XCTAssertEqual(operatingPoints.first?.pressurePa, request.pressurePa)
        XCTAssertEqual(operatingPoints.first?.temperatureK, request.temperatureK)
        XCTAssertEqual(pressureAxis.count, 10)
        XCTAssertEqual(temperatureAxis.count, 10)
        assertUniformAxis(
            pressureAxis,
            minimum: request.range.pressureMinimumPa,
            maximum: request.range.pressureMaximumPa,
            operatingValue: request.pressurePa
        )
        assertUniformAxis(
            temperatureAxis,
            minimum: request.range.temperatureMinimumK,
            maximum: request.range.temperatureMaximumK,
            operatingValue: request.temperatureK
        )
        try assertValidGrid(points, request: request)
    }

    func testTwentyByTwentyReusesNaturallyCoincidentOperatingPointWithoutDuplicate() throws {
        let request = request(
            resolution: .twenty,
            range: PhaseMapRange(
                pressureMinimumPa: 3_000_000,
                pressureMaximumPa: 22_000_000,
                temperatureMinimumK: 291,
                temperatureMaximumK: 310
            )
        )
        let points = try PhaseMapGridBuilder.points(for: request)

        XCTAssertEqual(points.count, 400)
        XCTAssertEqual(points.filter(\.isOperatingPoint).count, 1)
        try assertValidGrid(points, request: request)
    }

    func testGridConstructionIsStableAcrossRepeatedCalls() throws {
        let request = request(
            resolution: .twenty,
            range: PhaseMapRange(
                pressureMinimumPa: 9_500_000,
                pressureMaximumPa: 21_000_000,
                temperatureMinimumK: 280,
                temperatureMaximumK: 333
            )
        )

        let first = try PhaseMapGridBuilder.points(for: request)
        let second = try PhaseMapGridBuilder.points(for: request)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 401)
        try assertValidGrid(first, request: request)
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

    func testSummaryCountsKeepUnknownSeparateFromClassifiedAndFailed() {
        let result = PhaseMapResult(
            request: request(),
            model: Self.descriptor,
            evaluations: [
                evaluation(classification: .gas),
                evaluation(classification: .unknown),
                evaluation(classification: .failed, failureReason: "Fixture failure.")
            ],
            warnings: []
        )

        XCTAssertEqual(result.classifiedCount, 1)
        XCTAssertEqual(result.successfulCount, 1)
        XCTAssertEqual(result.unknownCount, 1)
        XCTAssertEqual(result.failedCount, 1)
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

    func testRunnerUsesExpectedProviderCallCountsForEveryResolution() async throws {
        for resolution in PhaseMapResolution.allCases {
            let recorder = CallRecorder()
            let provider = FixtureProvider(recorder: recorder) {
                Self.response(request: $0, phase: .supercritical)
            }

            let result = try await PhaseMapRunner(provider: provider).run(request(resolution: resolution))

            let expectedCount = try PhaseMapGridBuilder.points(for: request(resolution: resolution)).count
            XCTAssertEqual(result.evaluations.count, expectedCount)
            XCTAssertEqual(recorder.requests.count, expectedCount)
            XCTAssertEqual(result.operatingPoint?.classification.displayName, "Supercritical")
        }
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

    private func evaluation(
        classification: PhaseMapClassification,
        failureReason: String? = nil
    ) -> PhaseMapEvaluation {
        PhaseMapEvaluation(
            point: PhaseMapGridPoint(
                pressurePa: 12_000_000,
                temperatureK: 300,
                isOperatingPoint: false
            ),
            classification: classification == .failed
                ? PhaseMapClassificationResult(
                    classification: .failed,
                    displayName: "Failed",
                    isSupported: false
                )
                : PhaseMapClassificationResult(
                    classification: classification,
                    displayName: classification.rawValue,
                    isSupported: classification != .unknown
                ),
            solver: failureReason == nil
                ? SolverMetadata(method: "Fixture", converged: true, durationMilliseconds: 1)
                : nil,
            failureReason: failureReason
        )
    }

    private func assertValidGrid(
        _ points: [PhaseMapGridPoint],
        request: PhaseMapRequest,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let coordinateKeys = Set(points.map { "\($0.pressurePa),\($0.temperatureK)" })
        XCTAssertEqual(coordinateKeys.count, points.count, file: file, line: line)
        XCTAssertEqual(points.filter(\.isOperatingPoint).count, 1, file: file, line: line)
        if request.resolution.rawValue == 5 && points.count == request.resolution.gridPointCount {
            XCTAssertEqual(points[12].pressurePa, request.pressurePa, file: file, line: line)
            XCTAssertEqual(points[12].temperatureK, request.temperatureK, file: file, line: line)
        }
        for point in points {
            XCTAssertGreaterThanOrEqual(point.pressurePa, request.range.pressureMinimumPa, file: file, line: line)
            XCTAssertLessThanOrEqual(point.pressurePa, request.range.pressureMaximumPa, file: file, line: line)
            XCTAssertGreaterThanOrEqual(point.temperatureK, request.range.temperatureMinimumK, file: file, line: line)
            XCTAssertLessThanOrEqual(point.temperatureK, request.range.temperatureMaximumK, file: file, line: line)
        }
    }

    private func uniqueSorted(_ values: [Double]) -> [Double] {
        Array(Set(values)).sorted()
    }

    private func assertUniformAxis(
        _ axis: [Double],
        minimum: Double,
        maximum: Double,
        operatingValue: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard axis.count > 1 else {
            XCTFail("Axis must contain at least two points", file: file, line: line)
            return
        }
        XCTAssertEqual(axis[0], minimum, accuracy: 1e-8, file: file, line: line)
        XCTAssertEqual(axis[axis.count - 1], maximum, accuracy: 1e-8, file: file, line: line)
        let intervals = zip(axis, axis.dropFirst()).map { $1 - $0 }
        let expectedInterval = (maximum - minimum) / Double(axis.count - 1)
        for interval in intervals {
            XCTAssertEqual(interval, expectedInterval, accuracy: max(abs(expectedInterval), 1) * 1e-12, file: file, line: line)
        }
        if let lowerIndex = axis.lastIndex(where: { $0 < operatingValue }),
           axis.indices.contains(lowerIndex + 1) {
            XCTAssertEqual(
                axis[lowerIndex + 1] - axis[lowerIndex],
                expectedInterval,
                accuracy: max(abs(expectedInterval), 1) * 1e-12,
                file: file,
                line: line
            )
        }
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
