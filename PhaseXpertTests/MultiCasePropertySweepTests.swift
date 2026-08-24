import PDFKit
import PhaseXpertCore
import XCTest
@testable import PhaseXpert

@MainActor
final class MultiCasePropertySweepTests: XCTestCase {
    func testGeneralSweepReturnsOneCompleteSeriesPerCaseAndIsolatesPointFailure() async throws {
        let provider = MultiSweepTestProvider(id: BatchCalculationModel.general.id, failingPressures: [2_000_000])
        let cases = try builtIns(["northern-lights-cargo-specification-example", "brevik-ccs-conditioned-export-example", "porthos-pipeline-specification-example"])
        let result = try await service(provider).run(cases: cases, model: .general, definition: pressureDefinition(points: 4, start: 1_000_000, end: 4_000_000))

        XCTAssertEqual(result.series.count, 3)
        XCTAssertTrue(result.series.allSatisfy { $0.points.count == 4 })
        XCTAssertEqual(result.totalPointCount, 12)
        XCTAssertEqual(result.series.flatMap(\.points).filter { $0.state == .failed }.count, 3)
        XCTAssertEqual(result.series.flatMap(\.points).filter { $0.state == .generalCalculated }.count, 9)
        XCTAssertTrue(result.series.flatMap(\.points).compactMap(\.response).allSatisfy { $0.model.id == BatchCalculationModel.general.id })
    }

    func testAdvancedValidationIsPointwiseAndOutsidePointsAreNeverCalculatedOrPlotted() async throws {
        let input = h2Input()
        let provider = MultiSweepTestProvider(id: BatchCalculationModel.advanced.id)
        let definition = MultiCaseSweepDefinition(
            axis: .temperature, property: .density,
            startValueSI: 273.15, endValueSI: 323.15, pointCount: 6,
            fixedMode: .commonFixedValue, commonFixedValueSI: 1_000_000
        )
        let result = try await service(provider).run(cases: [input], model: .advanced, definition: definition)
        let points = try XCTUnwrap(result.series.first).points

        XCTAssertEqual(points.map(\.temperatureK), [273.15, 283.15, 293.15, 303.15, 313.15, 323.15])
        XCTAssertEqual(points.filter { $0.state == .advancedValidated }.map(\.index), [0, 2, 5])
        XCTAssertEqual(points.filter { $0.state == .outsideValidatedRange }.map(\.index), [1, 3, 4])
        XCTAssertTrue(points.filter { $0.state == .outsideValidatedRange }.allSatisfy { $0.response == nil && !$0.validatedProperties.contains(.density) })
        let calls = await provider.callCount
        XCTAssertEqual(calls, 3)
    }

    func testAdvancedMulticomponentAndOxygenPropertySpecificDecisionsRemainExact() async throws {
        let options = AdvancedValidationPresentation.stateOptions(currentPressurePa: nil, currentTemperatureK: nil)
        let multi = try input(try XCTUnwrap(options.first { $0.composition.count > 2 }))
        let oxygen = try input(try XCTUnwrap(options.first {
            Set($0.composition.map(\.component)) == [.carbonDioxide, .oxygen]
                && $0.properties.contains(.speedOfSound)
        }))
        let provider = MultiSweepTestProvider(id: BatchCalculationModel.advanced.id)
        let multiResult = try await service(provider).run(
            cases: [multi], model: .advanced,
            definition: pressureDefinition(points: 3, start: multi.pressurePa!, end: multi.pressurePa! + 100_000)
        )
        XCTAssertTrue(multiResult.series[0].points.contains { $0.validatedProperties.contains(.density) })
        XCTAssertTrue(multiResult.series[0].points.allSatisfy { !$0.validatedProperties.contains(.speedOfSound) })

        var acoustic = pressureDefinition(points: 2, start: oxygen.pressurePa!, end: oxygen.pressurePa! + 10_000)
        acoustic.property = .speedOfSound
        let oxygenResult = try await service(provider).run(cases: [oxygen], model: .advanced, definition: acoustic)
        XCTAssertTrue(oxygenResult.series[0].points.contains { $0.validatedProperties.contains(.speedOfSound) })
        XCTAssertTrue(oxygenResult.series[0].points.allSatisfy { !$0.validatedProperties.contains(.dynamicViscosity) })
    }

    func testPreservedAndCommonFixedConditionsAreExplicitlyApplied() async throws {
        let cases = try builtIns(["brevik-ccs-conditioned-export-example", "porthos-pipeline-specification-example"])
        let provider = MultiSweepTestProvider(id: BatchCalculationModel.general.id)
        let preserve = try await service(provider).run(cases: cases, model: .general,
            definition: pressureDefinition(points: 2, start: 1_000_000, end: 2_000_000))
        XCTAssertEqual(preserve.series[0].points.map(\.temperatureK), [cases[0].temperatureK!, cases[0].temperatureK!])
        XCTAssertEqual(preserve.series[1].points.map(\.temperatureK), [cases[1].temperatureK!, cases[1].temperatureK!])

        var common = pressureDefinition(points: 2, start: 1_000_000, end: 2_000_000)
        common.fixedMode = .commonFixedValue; common.commonFixedValueSI = 310
        let commonResult = try await service(provider).run(cases: cases, model: .general, definition: common)
        XCTAssertTrue(commonResult.series.flatMap(\.points).allSatisfy { $0.temperatureK == 310 })
    }

    func testDeltaAndMinMaxUseOnlyMatchingFinitePoints() async throws {
        let cases = try builtIns(["brevik-ccs-conditioned-export-example", "porthos-pipeline-specification-example"])
        let result = try await service(MultiSweepTestProvider(id: BatchCalculationModel.general.id)).run(
            cases: cases, model: .general,
            definition: pressureDefinition(points: 3, start: 1_000_000, end: 3_000_000)
        )
        let first = result.series[0], second = result.series[1]
        let expected = second.points[1].value(for: .density)!.value! - first.points[1].value(for: .density)!.value!
        XCTAssertEqual(try XCTUnwrap(result.delta(caseID: second.id, referenceCaseID: first.id, pointIndex: 1)), expected, accuracy: 1e-12)
        XCTAssertNil(result.delta(caseID: second.id, referenceCaseID: second.id, pointIndex: 1))
        let summary = first.summary(property: .density)
        XCTAssertEqual(summary.successfulCount, 3)
        XCTAssertEqual(summary.minimumPoint?.index, 0)
        XCTAssertEqual(summary.maximumPoint?.index, 2)
        XCTAssertLessThan(summary.minimumValue!, summary.maximumValue!)
    }

    func testProviderAndDefinitionChangesInvalidateControllerResult() async throws {
        let cases = try builtIns(["brevik-ccs-conditioned-export-example", "porthos-pipeline-specification-example"])
        let controller = MultiCasePropertySweepController(
            model: .general, definition: pressureDefinition(points: 2, start: 1_000_000, end: 2_000_000),
            service: service(MultiSweepTestProvider(id: BatchCalculationModel.general.id))
        )
        controller.start(cases: cases)
        try await waitUntil { !controller.isRunning }
        XCTAssertNotNil(controller.result)
        var changed = controller.definition; changed.endValueSI = 3_000_000
        controller.definition = changed
        XCTAssertNil(controller.result)
        controller.model = .advanced
        XCTAssertNil(controller.result)
    }

    func testDisplayUnitsDoNotRecomputeAndPointOpensExactCalculatorSnapshot() async throws {
        let provider = MultiSweepTestProvider(id: BatchCalculationModel.general.id)
        let source = try builtIns(["brevik-ccs-conditioned-export-example"])[0]
        let result = try await service(provider).run(cases: [source], model: .general,
            definition: pressureDefinition(points: 2, start: 1_000_000, end: 2_000_000))
        let point = result.series[0].points[1]
        _ = PressureDisplayUnit.psiAbsolute.displayValue(from: point.pressurePa)
        _ = TemperatureDisplayUnit.fahrenheit.displayValue(from: point.temperatureK)
        let calls = await provider.callCount
        XCTAssertEqual(calls, 2)
        let input = point.calculatorInput(from: source)
        XCTAssertEqual(input.pressurePa, point.pressurePa)
        XCTAssertEqual(input.temperatureK, point.temperatureK)
        XCTAssertEqual(input.composition, source.composition)
        let viewModel = CalculatorViewModel(registry: ProviderRegistry(providers: [provider], extraDescriptors: []))
        viewModel.loadInputs(from: input, model: .general)
        XCTAssertNil(viewModel.calculationRecord)
        XCTAssertEqual(viewModel.selectedModelID, BatchCalculationModel.general.id)
    }

    func testMultiCaseGeneralSweepScreensCoolPropDryMixturePoints() async throws {
        let recorder = MultiCaseDryMixtureRoutingRecorder()
        let provider = CoolPropProvider(
            engine: MultiCaseDryMixtureEngine(recorder: recorder)
        )
        let cases = try builtIns([
            "northern-lights-cargo-specification-example",
            "brevik-ccs-conditioned-export-example"
        ])
        let sweepService = MultiCasePropertySweepService(
            registry: ProviderRegistry(providers: [provider], extraDescriptors: []),
            clientVersion: "multi-sweep-coolprop-routing-tests",
            applicationIdentity: ApplicationIdentity(version: "test", build: "1")
        )

        let result = try await sweepService.run(
            cases: cases,
            model: .general,
            definition: pressureDefinition(
                points: 3,
                start: 4_000_000,
                end: 4_636_000
            )
        )

        XCTAssertEqual(result.totalPointCount, 6)
        XCTAssertEqual(result.series.flatMap(\.points).filter { $0.state == .generalCalculated }.count, 4)
        XCTAssertEqual(result.series.flatMap(\.points).filter { $0.state == .failed }.count, 2)
        XCTAssertEqual(recorder.phaseClassificationCount, 6)
        XCTAssertEqual(recorder.imposedPhaseCount, 4)
        XCTAssertEqual(recorder.unhintedCalculationCount, 0)
    }

    func testCSVContainsEverySuccessfulFailedAndOutsidePointWithStableCompositionColumns() async throws {
        let input = h2Input()
        let definition = MultiCaseSweepDefinition(axis: .temperature, property: .density,
            startValueSI: 273.15, endValueSI: 323.15, pointCount: 6,
            fixedMode: .commonFixedValue, commonFixedValueSI: 1_000_000)
        let result = try await service(MultiSweepTestProvider(id: BatchCalculationModel.advanced.id)).run(cases: [input], model: .advanced, definition: definition)
        let csv = String(decoding: MultiCaseSweepCSVExporter().data(result), as: UTF8.self)
        XCTAssertEqual(csv.split(whereSeparator: \.isNewline).count, 7)
        ComponentID.allCases.forEach { XCTAssertTrue(csv.contains("mole_fraction_\($0.rawValue)")) }
        XCTAssertTrue(csv.contains("Validated"))
        XCTAssertTrue(csv.contains("Outside validated range"))
        XCTAssertTrue(csv.contains(input.fingerprint))
        XCTAssertTrue(csv.contains(BatchCalculationModel.advanced.id))
    }

    func testPDFContainsCasesChartSummaryValidationLegendAndProvenance() async throws {
        let cases = try builtIns(["northern-lights-cargo-specification-example", "brevik-ccs-conditioned-export-example"])
        let result = try await service(MultiSweepTestProvider(id: BatchCalculationModel.general.id)).run(
            cases: cases, model: .general,
            definition: pressureDefinition(points: 3, start: 1_000_000, end: 3_000_000)
        )
        let document = try XCTUnwrap(PDFDocument(data: MultiCaseSweepPDFExporter().data(result)))
        let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
        cases.forEach { XCTAssertTrue(text.contains($0.name)) }
        XCTAssertTrue(text.contains("Case summaries"))
        XCTAssertTrue(text.contains("General engineering calculations"))
        XCTAssertTrue(text.contains(result.id.uuidString))
    }

    func testCancellationProducesCleanControllerState() async throws {
        let provider = MultiSweepTestProvider(id: BatchCalculationModel.general.id, delayNanoseconds: 100_000_000)
        let cases = try builtIns(["northern-lights-cargo-specification-example", "brevik-ccs-conditioned-export-example", "porthos-pipeline-specification-example"])
        let controller = MultiCasePropertySweepController(
            model: .general, definition: pressureDefinition(points: 20, start: 1_000_000, end: 3_000_000),
            service: service(provider)
        )
        controller.start(cases: cases)
        try await Task.sleep(for: .milliseconds(30))
        let started = ContinuousClock.now
        controller.cancel()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertFalse(controller.isRunning)
        XCTAssertNil(controller.result)
        XCTAssertLessThan(milliseconds(started.duration(to: .now)), 100)
    }

    func testNativePerformanceBenchmarks() async throws {
        let native = MultiCasePropertySweepService()
        let generalBase = (0..<3).map(pureCO2Input)
        let general5 = (0..<5).map(pureCO2Input)
        let advancedOptions = AdvancedValidationPresentation.stateOptions(currentPressurePa: nil, currentTemperatureK: nil)
        let advanced5 = try Array(advancedOptions.prefix(5)).map(input)
        let rows: [[String: Any]] = [
            try await benchmark("general_3x20", cases: generalBase, model: .general, service: native),
            try await benchmark("general_5x20", cases: general5, model: .general, service: native),
            try await benchmark("advanced_3x20", cases: Array(advanced5.prefix(3)), model: .advanced, service: native),
            try await benchmark("advanced_5x20", cases: advanced5, model: .advanced, service: native)
        ]
        let data = try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "MultiCaseSweepNativePerformance"; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func service(_ provider: MultiSweepTestProvider) -> MultiCasePropertySweepService {
        MultiCasePropertySweepService(
            registry: ProviderRegistry(providers: [provider], extraDescriptors: []), clientVersion: "tests",
            applicationIdentity: ApplicationIdentity(version: "test", build: "1")
        )
    }
    private func pressureDefinition(points: Int, start: Double, end: Double) -> MultiCaseSweepDefinition {
        MultiCaseSweepDefinition(axis: .pressure, property: .density, startValueSI: start,
                                 endValueSI: end, pointCount: points,
                                 fixedMode: .preserveEachCase, commonFixedValueSI: nil)
    }
    private func builtIns(_ ids: [String]) throws -> [BatchCaseInput] {
        try ids.map { BatchCaseInput.builtIn(try XCTUnwrap(BuiltInCaseCatalog.caseWithID($0))) }
    }
    private func h2Input() -> BatchCaseInput {
        BatchCaseInput(id: "h2", name: "H₂ validated branches", origin: .saved,
                       pressurePa: 1_000_000, temperatureK: 293.15,
                       composition: [.init(component: .carbonDioxide, moleFraction: 0.94638),
                                     .init(component: .hydrogen, moleFraction: 0.05362)],
                       originalInput: nil, sourceCalculationID: nil)
    }
    private func pureCO2Input(_ index: Int) -> BatchCaseInput {
        BatchCaseInput(id: "co2:\(index)", name: "CO₂ benchmark \(index + 1)", origin: .saved,
                       pressurePa: 5_000_000, temperatureK: 300 + Double(index),
                       composition: [.init(component: .carbonDioxide, moleFraction: 1)],
                       originalInput: nil, sourceCalculationID: nil)
    }
    private func input(_ option: ValidatedStateOption) throws -> BatchCaseInput {
        BatchCaseInput(id: "gate:\(option.id)", name: option.name, origin: .saved,
                       pressurePa: option.pressurePa, temperatureK: option.temperatureK,
                       composition: option.composition, originalInput: nil, sourceCalculationID: nil)
    }
    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<200 { if condition() { return }; try await Task.sleep(for: .milliseconds(10)) }
        XCTFail("Timed out")
    }
    private func milliseconds(_ duration: Duration) -> Double {
        let c = duration.components; return Double(c.seconds) * 1_000 + Double(c.attoseconds) / 1e15
    }
    private func benchmark(_ name: String, cases: [BatchCaseInput], model: BatchCalculationModel,
                           service: MultiCasePropertySweepService) async throws -> [String: Any] {
        let first = cases[0]
        let center = first.pressurePa ?? 2_000_000
        let start = max(100_000, center - 100_000), end = center + 100_000
        let begin = ContinuousClock.now
        let result = try await service.run(cases: cases, model: model,
            definition: pressureDefinition(points: 20, start: start, end: end))
        let total = milliseconds(begin.duration(to: .now))
        XCTAssertEqual(result.totalPointCount, cases.count * 20)
        return ["batch": name, "cases": cases.count, "points": result.totalPointCount,
                "total_ms": total, "per_point_ms": total / Double(result.totalPointCount)]
    }
}

private final class MultiCaseDryMixtureRoutingRecorder: @unchecked Sendable {
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

private struct MultiCaseDryMixtureEngine: CoolPropEngine {
    let isAvailable = true
    let libraryVersion = "8.0.0-multi-sweep-routing-test"
    let recorder: MultiCaseDryMixtureRoutingRecorder

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

private actor MultiSweepTestProvider: ThermodynamicModelProvider {
    nonisolated let descriptor: ModelDescriptor
    private(set) var callCount = 0
    let failingPressures: Set<Double>
    let delayNanoseconds: UInt64
    init(id: String, failingPressures: Set<Double> = [], delayNanoseconds: UInt64 = 0) {
        descriptor = ModelDescriptor(id: id, name: id == "coolprop-heos" ? "General Properties" : "Advanced CCS Properties",
            modelVersion: "test", providerVersion: "test", availability: .available, calculationMode: .local,
            supportedComponents: Set(ComponentID.allCases), supportedProperties: Set(PropertyID.allCases),
            domain: ScientificDomain(minimumPressurePa: 100_000, maximumPressurePa: 100_000_000,
                                     minimumTemperatureK: 200, maximumTemperatureK: 600),
            scientificBasis: "Test", equationOrMethod: "Test", limitations: [], references: [])
        self.failingPressures = failingPressures; self.delayNanoseconds = delayNanoseconds
    }
    nonisolated func applicabilityIssues(for composition: [MixtureComponent]) -> [ValidationIssue] { [] }
    nonisolated func operatingRangeGuidance(for context: OperatingGuidanceContext) -> OperatingRangeGuidance? { nil }
    func calculate(_ request: CalculationRequest) async throws -> CalculationResponse {
        callCount += 1
        if delayNanoseconds > 0 { try await Task.sleep(nanoseconds: delayNanoseconds) }
        if failingPressures.contains(request.pressurePa) { throw ProviderError.malformedResponse("Injected point failure") }
        let density = request.pressurePa / 100_000 + request.temperatureK / 1_000 + Double(callCount) / 10_000
        return CalculationResponse(requestID: request.requestID, model: descriptor, phase: .gas,
            properties: [PropertyValue(property: request.requestedProperties.first ?? .density,
                                       value: density, unit: "kg/m³", status: .calculated)],
            solver: SolverMetadata(method: "test", converged: true, durationMilliseconds: 0.1),
            warnings: [], isScientificResult: true)
    }
    nonisolated func phaseEnvelope(_ request: PhaseEnvelopeRequest) async throws -> PhaseEnvelopeResponse {
        PhaseEnvelopeResponse(requestID: request.requestID, points: [], warnings: [], isAvailable: false)
    }
}
