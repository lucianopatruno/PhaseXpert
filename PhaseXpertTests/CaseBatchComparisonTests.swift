import PDFKit
import PhaseXpertCore
import XCTest
@testable import PhaseXpert

@MainActor
final class CaseBatchComparisonTests: XCTestCase {
    func testNormalBatchWorkflowOffersGeneralOnly() {
        XCTAssertEqual(BatchCalculationModel.allCases, [.general])
    }

    func testGeneralBatchKeepsProviderAndOneFailureDoesNotStopOtherBuiltIns() async throws {
        let provider = BatchTestProvider(id: BatchCalculationModel.general.id, failingNames: ["request-2"])
        let service = service(provider)
        let inputs = try ["northern-lights-cargo-specification-example", "brevik-ccs-conditioned-export-example",
                          "porthos-pipeline-specification-example", "aramis-ship-specification-example"]
            .map { BatchCaseInput.builtIn(try XCTUnwrap(BuiltInCaseCatalog.caseWithID($0))) }
        let results = await calculate(inputs, service: service, model: .general)

        XCTAssertEqual(results.count, 4)
        XCTAssertEqual(results.filter(\.isSuccessful).count, 3)
        XCTAssertEqual(results.filter { $0.state == .failed }.count, 1)
        XCTAssertTrue(results.allSatisfy { $0.model == .general })
        XCTAssertTrue(results.compactMap(\.record).allSatisfy { $0.request.modelID == BatchCalculationModel.general.id })
        XCTAssertTrue(results.flatMap(\.validatedProperties).isEmpty)
    }

    func testAdvancedBatchPreservesEveryGateAndClassifiesOutsideRangeWithoutFallback() async throws {
        let provider = BatchTestProvider(id: BatchCalculationModel.advanced.id)
        let service = service(provider)
        let valid = try requiredAdvancedFixtureInputs()
        let outside = BatchCaseInput.builtIn(try XCTUnwrap(BuiltInCaseCatalog.caseWithID("porthos-pipeline-specification-example")))
        let results = await calculate(valid + [outside], service: service, model: .advanced)

        XCTAssertEqual(results.count, 5)
        XCTAssertEqual(results.filter(\.isSuccessful).count, 4)
        let rejected = try XCTUnwrap(results.first { $0.id == outside.id })
        XCTAssertEqual(rejected.state, .outsideValidatedRange)
        XCTAssertNil(rejected.record)
        XCTAssertTrue(rejected.message?.contains("not substituted") == true)
        XCTAssertTrue(results.filter(\.isSuccessful).allSatisfy { !$0.validatedProperties.isEmpty })
        XCTAssertTrue(results.compactMap(\.record).allSatisfy { $0.request.modelID == BatchCalculationModel.advanced.id })
        let callCount = await provider.callCount
        XCTAssertEqual(callCount, 4, "Outside-range state must not call either provider")
    }

    func testInputAndProviderProvenanceAreImmutableAndCalculatorLoadsExactSnapshot() async throws {
        let builtIn = try XCTUnwrap(BuiltInCaseCatalog.caseWithID("brevik-ccs-conditioned-export-example"))
        let input = BatchCaseInput.builtIn(builtIn)
        let result = await service(BatchTestProvider(id: BatchCalculationModel.general.id)).calculate(input, model: .general)
        let record = try XCTUnwrap(result.record)
        let fingerprint = result.input.fingerprint
        let viewModel = CalculatorViewModel(registry: ProviderRegistry(providers: [BatchTestProvider(id: BatchCalculationModel.general.id)], extraDescriptors: []))
        viewModel.loadInputs(from: record)

        XCTAssertEqual(result.input.fingerprint, fingerprint)
        XCTAssertEqual(record.request.composition, input.composition)
        XCTAssertEqual(record.request.pressurePa, input.pressurePa)
        XCTAssertEqual(record.request.temperatureK, input.temperatureK)
        XCTAssertEqual(viewModel.selectedModelID, BatchCalculationModel.general.id)
        XCTAssertNil(viewModel.calculationRecord, "Open in Calculator must not automatically calculate")

        viewModel.loadInputs(from: input, model: .general)
        XCTAssertEqual(viewModel.selectedModelID, BatchCalculationModel.general.id)
        XCTAssertNil(viewModel.calculationRecord)
        XCTAssertEqual(viewModel.pressureDisplayUnit.displayValue(from: input.pressurePa!),
                       try XCTUnwrap(Double(viewModel.pressureText)), accuracy: 1e-10)
    }

    func testModelChangeInvalidatesExistingResults() async throws {
        let controller = CaseBatchComparisonController(service: service(BatchTestProvider(id: BatchCalculationModel.general.id)))
        let inputs = try ["northern-lights-cargo-specification-example", "brevik-ccs-conditioned-export-example"]
            .map { BatchCaseInput.builtIn(try XCTUnwrap(BuiltInCaseCatalog.caseWithID($0))) }
        controller.calculate(inputs)
        try await waitUntil { !controller.isCalculating }
        XCTAssertEqual(controller.results.count, 2)
        controller.selectedModel = .advanced
        XCTAssertTrue(controller.results.isEmpty)
        XCTAssertNil(controller.resultModel)
    }

    func testCancellationLeavesOnlyCoherentCompletedSnapshots() async throws {
        let provider = BatchTestProvider(id: BatchCalculationModel.general.id, delayNanoseconds: 500_000_000)
        let controller = CaseBatchComparisonController(service: service(provider))
        let base = BatchCaseInput.builtIn(try XCTUnwrap(BuiltInCaseCatalog.caseWithID("brevik-ccs-conditioned-export-example")))
        let inputs = (0..<10).map { index in
            BatchCaseInput(id: "\(base.id)-\(index)", name: "Case \(index)", origin: base.origin,
                           pressurePa: base.pressurePa, temperatureK: base.temperatureK,
                           composition: base.composition, originalInput: nil, sourceCalculationID: nil)
        }
        controller.calculate(inputs)
        controller.cancel()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertFalse(controller.isCalculating)
        XCTAssertEqual(controller.completedCount, controller.results.count)
        XCTAssertTrue(controller.results.allSatisfy { $0.record?.request.modelID == BatchCalculationModel.general.id })
    }

    func testCSVHasOneRowPerCaseStableComponentColumnsAndValidationLabels() async throws {
        let inputs = try advancedInputsForDistinctComponentSets(count: 2)
        let results = await calculate(inputs, service: service(BatchTestProvider(id: BatchCalculationModel.advanced.id)), model: .advanced)
        let csv = String(decoding: BatchComparisonCSVExporter().data(results: results), as: UTF8.self)
        let lines = csv.split(whereSeparator: \.isNewline)
        XCTAssertEqual(lines.count, 3)
        for component in ComponentID.allCases { XCTAssertTrue(lines[0].contains("mole_fraction_\(component.rawValue)")) }
        for input in inputs {
            XCTAssertTrue(csv.contains(input.name))
            for component in input.composition {
                XCTAssertTrue(csv.contains(String(format: "%.17g", component.moleFraction)))
            }
        }
        XCTAssertTrue(csv.contains("Validated"))
        XCTAssertTrue(csv.contains(BatchCalculationModel.advanced.id))
    }

    func testPDFContainsEveryCaseModelProvenanceAndValidationLegend() async throws {
        let inputs = try advancedInputsForDistinctComponentSets(count: 3)
        let results = await calculate(inputs, service: service(BatchTestProvider(id: BatchCalculationModel.general.id)), model: .general)
        let data = BatchComparisonPDFExporter().data(results: results, model: .general, date: Date(timeIntervalSince1970: 0))
        let document = try XCTUnwrap(PDFDocument(data: data))
        let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
        inputs.forEach { XCTAssertTrue(text.contains($0.name)) }
        XCTAssertTrue(text.contains("Calculation model: General Properties"))
        XCTAssertFalse(text.contains("Selected model: Advanced CCS"))
        XCTAssertTrue(text.contains("property-specific"))
        XCTAssertTrue(text.contains("input snapshot and validation evidence"))
    }

    func testSavedCaseSnapshotDoesNotChangeWhenSourceRecordChanges() async throws {
        let first = try advancedInputsForDistinctComponentSets(count: 1)[0]
        let source = await service(BatchTestProvider(id: BatchCalculationModel.advanced.id)).calculate(first, model: .advanced)
        let saved = BatchCaseInput.saved(id: UUID(), name: "Snapshot", record: try XCTUnwrap(source.record))
        let fingerprint = saved.fingerprint
        _ = BatchCaseInput.saved(id: UUID(), name: "Edited", record: nil)
        XCTAssertEqual(saved.fingerprint, fingerprint)
        XCTAssertEqual(saved.composition, first.composition)
    }

    func testDisplayFormattingDoesNotRecalculateOrMutateSIResults() async throws {
        let provider = BatchTestProvider(id: BatchCalculationModel.general.id)
        let input = BatchCaseInput.builtIn(try XCTUnwrap(BuiltInCaseCatalog.caseWithID("brevik-ccs-conditioned-export-example")))
        let result = await service(provider).calculate(input, model: .general)
        let record = try XCTUnwrap(result.record)
        _ = PressureDisplayUnit.psiAbsolute.displayValue(from: record.input.pressurePa)
        _ = TemperatureDisplayUnit.fahrenheit.displayValue(from: record.input.temperatureK)
        let callCount = await provider.callCount
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(result.record, record)
    }

    func testRepeatedGeneralBatchUsesScreenedCoolPropDryMixtureRoute() async throws {
        let recorder = BatchDryMixtureRoutingRecorder()
        let provider = CoolPropProvider(
            engine: BatchDryMixtureEngine(recorder: recorder)
        )
        let inputs = try Array((builtInGeneralInputs() + builtInGeneralInputs()).prefix(5))
            .enumerated()
            .map { index, input in copied(input, suffix: index) }
        let batchService = CaseBatchCalculationService(
            registry: ProviderRegistry(providers: [provider], extraDescriptors: []),
            clientVersion: "batch-coolprop-routing-tests",
            applicationIdentity: ApplicationIdentity(version: "test", build: "1")
        )

        let first = await calculate(inputs, service: batchService, model: .general)
        let second = await calculate(inputs, service: batchService, model: .general)

        XCTAssertEqual(first.count, 5)
        XCTAssertEqual(second.count, 5)
        XCTAssertTrue((first + second).allSatisfy(\.isSuccessful))
        XCTAssertEqual(recorder.phaseClassificationCount, 10)
        XCTAssertEqual(recorder.imposedPhaseCount, 10)
        XCTAssertEqual(recorder.unhintedCalculationCount, 0)
    }

    func testRepresentativeNativeBatchPerformance() async throws {
        let native = CaseBatchCalculationService()
        let presets = BuiltInCaseCatalog.cases.filter(\.hasCalculationPreset).map(BatchCaseInput.builtIn)
        let general5 = Array((presets + presets).prefix(5)).enumerated().map { index, value in copied(value, suffix: index) }
        let general10 = Array((presets + presets + presets).prefix(10)).enumerated().map { index, value in copied(value, suffix: index) }
        let advanced5 = try advancedInputsForDistinctComponentSets(count: 5)
        let mixed = Array(advanced5.prefix(4)) + [BatchCaseInput.builtIn(try XCTUnwrap(BuiltInCaseCatalog.caseWithID("porthos-pipeline-specification-example")))]

        let measurements = [
            try await timed("general_5", inputs: general5, model: .general, service: native),
            try await timed("general_10", inputs: general10, model: .general, service: native),
            try await timed("advanced_5", inputs: advanced5, model: .advanced, service: native),
            try await timed("advanced_mixed_5", inputs: mixed, model: .advanced, service: native)
        ]
        let data = try JSONSerialization.data(withJSONObject: measurements, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "CaseBatchNativePerformance"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func service(_ provider: BatchTestProvider) -> CaseBatchCalculationService {
        CaseBatchCalculationService(
            registry: ProviderRegistry(providers: [provider], extraDescriptors: []),
            clientVersion: "batch-tests",
            applicationIdentity: ApplicationIdentity(version: "test", build: "1")
        )
    }

    private func calculate(_ inputs: [BatchCaseInput], service: CaseBatchCalculationService, model: BatchCalculationModel) async -> [BatchCaseResult] {
        var output: [BatchCaseResult] = []
        for input in inputs { output.append(await service.calculate(input, model: model)) }
        return output
    }

    private func timed(_ name: String, inputs: [BatchCaseInput], model: BatchCalculationModel, service: CaseBatchCalculationService) async throws -> [String: Any] {
        let start = ContinuousClock.now
        let results = await calculate(inputs, service: service, model: model)
        let elapsed = start.duration(to: .now).components
        let total = Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15
        XCTAssertEqual(results.count, inputs.count)
        return ["batch": name, "case_count": inputs.count, "total_ms": total,
                "per_case_ms": total / Double(inputs.count),
                "successful": results.filter(\.isSuccessful).count,
                "outside_validated_range": results.filter { $0.state == .outsideValidatedRange }.count,
                "failed": results.filter { $0.state == .failed || $0.state == .unsupported }.count]
    }

    private func copied(_ input: BatchCaseInput, suffix: Int) -> BatchCaseInput {
        BatchCaseInput(id: "\(input.id):\(suffix)", name: "\(input.name) #\(suffix + 1)", origin: input.origin,
                       pressurePa: input.pressurePa, temperatureK: input.temperatureK,
                       composition: input.composition, originalInput: input.originalInput,
                       sourceCalculationID: input.sourceCalculationID)
    }

    private func advancedInputsForDistinctComponentSets(count: Int) throws -> [BatchCaseInput] {
        var seen: Set<Set<ComponentID>> = []
        let options = AdvancedValidationPresentation.stateOptions(currentPressurePa: nil, currentTemperatureK: nil)
        return Array(options.compactMap { option -> BatchCaseInput? in
            let components = Set(option.composition.map(\.component))
            guard seen.insert(components).inserted else { return nil }
            return BatchCaseInput(id: "gate:\(option.id)", name: option.name, origin: .saved,
                                  pressurePa: option.pressurePa, temperatureK: option.temperatureK,
                                  composition: option.composition, originalInput: nil, sourceCalculationID: nil)
        }.prefix(count))
    }

    private func requiredAdvancedFixtureInputs() throws -> [BatchCaseInput] {
        let options = AdvancedValidationPresentation.stateOptions(currentPressurePa: nil, currentTemperatureK: nil)
        let targets: [Set<ComponentID>] = [
            [.carbonDioxide, .nitrogen],
            [.carbonDioxide, .hydrogen],
            [.carbonDioxide, .hydrogenSulfide]
        ]
        var selected = try targets.map { target -> ValidatedStateOption in
            try XCTUnwrap(options.first { Set($0.composition.map(\.component)) == target })
        }
        selected.append(try XCTUnwrap(options.first { $0.composition.count > 2 }))
        return selected.map { option in
            BatchCaseInput(id: "gate:\(option.id)", name: option.name, origin: .saved,
                           pressurePa: option.pressurePa, temperatureK: option.temperatureK,
                           composition: option.composition, originalInput: nil, sourceCalculationID: nil)
        }
    }

    private func builtInGeneralInputs() throws -> [BatchCaseInput] {
        try [
            "northern-lights-cargo-specification-example",
            "brevik-ccs-conditioned-export-example",
            "porthos-pipeline-specification-example",
            "aramis-ship-specification-example"
        ].map { BatchCaseInput.builtIn(try XCTUnwrap(BuiltInCaseCatalog.caseWithID($0))) }
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for batch")
    }
}

private final class BatchDryMixtureRoutingRecorder: @unchecked Sendable {
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

private struct BatchDryMixtureEngine: CoolPropEngine {
    let isAvailable = true
    let libraryVersion = "8.0.0-batch-routing-test"
    let recorder: BatchDryMixtureRoutingRecorder

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
        return CoolPropPhaseEngineResult(phaseIdentifier: "gas")
    }

    func pureCarbonDioxideSaturationLimits() async throws -> CoolPropSaturationLimits {
        throw ProviderError.modelUnavailable("Pure CO₂ saturation is not used by this test engine.")
    }

    func pureCarbonDioxideSaturationPressure(temperatureK: Double) async throws -> Double {
        throw ProviderError.modelUnavailable("Pure CO₂ saturation is not used by this test engine.")
    }
}

private actor BatchTestProvider: ThermodynamicModelProvider {
    nonisolated let descriptor: ModelDescriptor
    private(set) var callCount = 0
    let failingNames: Set<String>
    let delayNanoseconds: UInt64

    init(id: String, failingNames: Set<String> = [], delayNanoseconds: UInt64 = 0) {
        descriptor = ModelDescriptor(
            id: id, name: id == "coolprop-heos" ? "General Properties" : "Advanced CCS Properties",
            modelVersion: "test", providerVersion: "test", availability: .available,
            calculationMode: .local, supportedComponents: Set(ComponentID.allCases),
            supportedProperties: Set(PropertyID.allCases), domain: .initialCO2Transport,
            scientificBasis: "Test provider", equationOrMethod: "Test provider", limitations: [], references: []
        )
        self.failingNames = failingNames
        self.delayNanoseconds = delayNanoseconds
    }

    nonisolated func applicabilityIssues(for composition: [MixtureComponent]) -> [ValidationIssue] { [] }
    nonisolated func operatingRangeGuidance(for context: OperatingGuidanceContext) -> OperatingRangeGuidance? { nil }
    func calculate(_ request: CalculationRequest) async throws -> CalculationResponse {
        callCount += 1
        if delayNanoseconds > 0 { try await Task.sleep(nanoseconds: delayNanoseconds) }
        if failingNames.contains("request-\(callCount)") { throw ProviderError.malformedResponse("Injected failure") }
        return CalculationResponse(
            requestID: request.requestID, model: descriptor, phase: .gas,
            properties: [
                PropertyValue(property: .density, value: 810 + Double(callCount), unit: "kg/m³", status: .calculated),
                PropertyValue(property: .compressibilityFactor, value: 0.9, unit: "", status: .calculated),
                PropertyValue(property: .speedOfSound, value: 230, unit: "m/s", status: .calculated)
            ],
            solver: SolverMetadata(method: "test", converged: true, durationMilliseconds: 1),
            warnings: [], isScientificResult: true
        )
    }
    nonisolated func phaseEnvelope(_ request: PhaseEnvelopeRequest) async throws -> PhaseEnvelopeResponse {
        PhaseEnvelopeResponse(requestID: request.requestID, points: [], warnings: [], isAvailable: false)
    }
}
