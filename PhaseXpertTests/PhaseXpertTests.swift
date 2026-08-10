import PhaseXpertCore
import SwiftData
import XCTest
@testable import PhaseXpert

final class PhaseXpertTests: XCTestCase {
    private static let testDescriptor = ModelDescriptor(
        id: "test-calculation-provider",
        name: "Test calculation provider",
        modelVersion: "test",
        providerVersion: "test",
        availability: .available,
        calculationMode: .local,
        supportedComponents: [.carbonDioxide, .nitrogen],
        supportedProperties: [.density],
        domain: .initialCO2Transport,
        scientificBasis: "Test double for app-state tests.",
        equationOrMethod: "Test double",
        limitations: ["Not a production provider."],
        references: []
    )

    private struct TestCalculationProvider: ThermodynamicModelProvider {
        let descriptor = PhaseXpertTests.testDescriptor

        func calculate(_ request: CalculationRequest) async throws -> CalculationResponse {
            CalculationResponse(
                requestID: request.requestID,
                model: descriptor,
                phase: .dense,
                properties: [
                    PropertyValue(
                        property: .density,
                        value: 800,
                        unit: "kg/m³",
                        status: .calculated,
                        message: "Test density."
                    )
                ],
                solver: SolverMetadata(
                    method: "Test calculation",
                    converged: true,
                    durationMilliseconds: 1
                ),
                warnings: [],
                isScientificResult: false
            )
        }

        func phaseEnvelope(_ request: PhaseEnvelopeRequest) async throws -> PhaseEnvelopeResponse {
            PhaseEnvelopeResponse(
                requestID: request.requestID,
                points: [],
                warnings: [],
                isAvailable: false
            )
        }
    }

    private final class PhaseEnvelopeCallCounter: @unchecked Sendable {
        private(set) var callCount = 0

        func recordCall() {
            callCount += 1
        }
    }

    private struct CountingPhaseEnvelopeProvider: ThermodynamicModelProvider {
        let descriptor = PhaseXpertTests.testDescriptor
        let counter: PhaseEnvelopeCallCounter
        var delayNanoseconds: UInt64 = 0

        func calculate(_ request: CalculationRequest) async throws -> CalculationResponse {
            try await TestCalculationProvider().calculate(request)
        }

        func phaseEnvelope(
            _ request: PhaseEnvelopeRequest
        ) async throws -> PhaseEnvelopeResponse {
            counter.recordCall()
            if delayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            }
            return PhaseEnvelopeResponse(
                requestID: request.requestID,
                points: [
                    .init(temperatureK: 250, pressurePa: 1_800_000, branch: .bubble),
                    .init(temperatureK: 304.1282, pressurePa: 7_377_300, branch: .critical)
                ],
                warnings: ["PRELIMINARY — validation pending."],
                isAvailable: true,
                boundaryKind: .pureFluidSaturation,
                model: descriptor,
                generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                solver: .init(
                    method: "Deterministic test saturation",
                    converged: true,
                    durationMilliseconds: 1
                )
            )
        }
    }

    private struct DelayedPhaseEnvelopeProvider: ThermodynamicModelProvider {
        let descriptor = PhaseXpertTests.testDescriptor
        let delayNanoseconds: UInt64

        func calculate(_ request: CalculationRequest) async throws -> CalculationResponse {
            try await TestCalculationProvider().calculate(request)
        }

        func phaseEnvelope(
            _ request: PhaseEnvelopeRequest
        ) async throws -> PhaseEnvelopeResponse {
            try await Task.sleep(nanoseconds: delayNanoseconds)
            return PhaseEnvelopeResponse(
                requestID: request.requestID,
                points: [],
                warnings: ["Delayed test provider completed."],
                isAvailable: false
            )
        }
    }

    func testDefaultRegistryContainsBothFutureProductionProviders() {
        let registry = ProviderRegistry()
        let identifiers = Set(registry.descriptors.map(\.id))
        XCTAssertTrue(identifiers.contains("coolprop-heos"))
        XCTAssertTrue(identifiers.contains("ife-model"))
        XCTAssertFalse(identifiers.contains("architecture-demo"))
        XCTAssertNil(registry.provider(id: "ife-model"))
        XCTAssertEqual(
            registry.provider(id: "coolprop-heos")?.descriptor.availability,
            expectedDefaultCoolPropAvailability
        )
    }

    @MainActor
    func testIFEModelIsVisibleUnavailableAndCannotCalculateOrFallback() async throws {
        let viewModel = CalculatorViewModel()
        viewModel.selectedModelID = "ife-model"
        viewModel.validate()

        XCTAssertEqual(viewModel.selectedDescriptor?.name, "IFE Model")
        XCTAssertEqual(viewModel.selectedDescriptor?.availability, .unavailable)
        XCTAssertTrue(viewModel.validationReport.issues.contains {
            $0.code == .modelUnavailable
                && $0.message == "This model is not available in this version."
        })

        await viewModel.calculate()

        XCTAssertNil(viewModel.calculationRecord)
        XCTAssertNil(viewModel.calculationError)
        XCTAssertNil(ProviderRegistry().provider(id: "ife-model"))
    }

    @MainActor
    func testLegacyIFESavedCaseLoadsAsUnavailableWithoutChangingProvenance() async throws {
        let legacy = try await makeRecord(
            modelID: "ife-model",
            modelDescriptor: ProviderRegistry.ifeModelDescriptor,
            composition: [.init(component: .carbonDioxide, moleFraction: 1)]
        )
        let viewModel = CalculatorViewModel()

        viewModel.loadInputs(from: legacy)

        XCTAssertEqual(viewModel.selectedModelID, "ife-model")
        XCTAssertEqual(viewModel.selectedDescriptor?.availability, .unavailable)
        XCTAssertEqual(legacy.response.model.id, "ife-model")
        XCTAssertTrue(viewModel.validationReport.issues.contains {
            $0.code == .modelUnavailable
        })
    }

    @MainActor
    func testPhaseDiagramStopsSpinningAndAcceptsLatePureCO2Completion() async throws {
        let record = try await makeRecord()
        let viewModel = PhaseDiagramViewModel(
            registry: ProviderRegistry(providers: [
                DelayedPhaseEnvelopeProvider(delayNanoseconds: 120_000_000)
            ]),
            timeoutNanoseconds: 20_000_000
        )

        viewModel.load(for: record)
        XCTAssertTrue(viewModel.isLoading)

        try await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertTrue(viewModel.errorMessage?.contains("will appear automatically") == true)

        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNotNil(viewModel.response)
    }

    @MainActor
    func testMixturePhaseDiagramShowsScopeMessageWithoutProviderCall() async throws {
        let counter = PhaseEnvelopeCallCounter()
        let viewModel = PhaseDiagramViewModel(
            registry: ProviderRegistry(providers: [
                CountingPhaseEnvelopeProvider(counter: counter)
            ])
        )

        viewModel.load(for: try await makeRecord(composition: [
            .init(component: .carbonDioxide, moleFraction: 0.999999),
            .init(component: .nitrogen, moleFraction: 0.000001)
        ]))

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.response)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(
            viewModel.scopeMessage,
            PhaseDiagramEligibility.pureCarbonDioxideScopeMessage
        )
        XCTAssertFalse(viewModel.scopeMessage?.localizedCaseInsensitiveContains("failed") == true)
        XCTAssertFalse(viewModel.scopeMessage?.localizedCaseInsensitiveContains("error") == true)
        XCTAssertFalse(viewModel.scopeMessage?.localizedCaseInsensitiveContains("provider") == true)
        XCTAssertFalse(viewModel.scopeMessage?.localizedCaseInsensitiveContains("CoolProp") == true)
        XCTAssertEqual(counter.callCount, 0)
    }

    @MainActor
    func testPureToMixtureTransitionClearsResultAndRejectsLateCompletion() async throws {
        let counter = PhaseEnvelopeCallCounter()
        let viewModel = PhaseDiagramViewModel(
            registry: ProviderRegistry(providers: [
                CountingPhaseEnvelopeProvider(
                    counter: counter,
                    delayNanoseconds: 80_000_000
                )
            ])
        )
        let pure = try await makeRecord()
        let mixture = try await makeRecord(composition: [
            .init(component: .carbonDioxide, moleFraction: 0.99),
            .init(component: .nitrogen, moleFraction: 0.01)
        ])

        viewModel.load(for: pure)
        XCTAssertTrue(viewModel.isLoading)

        viewModel.load(for: mixture)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(
            viewModel.scopeMessage,
            PhaseDiagramEligibility.pureCarbonDioxideScopeMessage
        )
        XCTAssertNil(viewModel.response)

        try await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertNil(viewModel.response)
        XCTAssertEqual(counter.callCount, 1)
    }

    @MainActor
    func testMixtureToPureTransitionRestoresPhaseDiagramAvailability() async throws {
        let counter = PhaseEnvelopeCallCounter()
        let viewModel = PhaseDiagramViewModel(
            registry: ProviderRegistry(providers: [
                CountingPhaseEnvelopeProvider(counter: counter)
            ])
        )
        let mixture = try await makeRecord(composition: [
            .init(component: .carbonDioxide, moleFraction: 0.99),
            .init(component: .nitrogen, moleFraction: 0.01)
        ])

        viewModel.load(for: mixture)
        XCTAssertEqual(counter.callCount, 0)
        XCTAssertNotNil(viewModel.scopeMessage)

        viewModel.load(for: try await makeRecord())
        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertNil(viewModel.scopeMessage)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNotNil(viewModel.response)
        XCTAssertEqual(counter.callCount, 1)
    }

    @MainActor
    func testPhaseDiagramExportRejectsMulticomponentAndPreservesPureCO2Export() async throws {
        let pure = try await makeRecord()
        let mixture = try await makeRecord(composition: [
            .init(component: .carbonDioxide, moleFraction: 0.99),
            .init(component: .nitrogen, moleFraction: 0.01)
        ])
        let pureResponse = PhaseEnvelopeResponse(
            requestID: pure.request.requestID,
            points: [
                .init(temperatureK: 250, pressurePa: 1_800_000, branch: .bubble),
                .init(temperatureK: 260, pressurePa: 2_400_000, branch: .bubble),
                .init(temperatureK: 304.1282, pressurePa: 7_377_300, branch: .critical)
            ],
            warnings: [],
            isAvailable: true,
            boundaryKind: .pureFluidSaturation,
            model: pure.response.model
        )
        let mixtureResponse = PhaseEnvelopeResponse(
            requestID: mixture.request.requestID,
            points: [
                .init(temperatureK: 240, pressurePa: 1_000_000, branch: .bubble),
                .init(temperatureK: 268, pressurePa: 2_900_000, branch: .dew)
            ],
            warnings: [],
            isAvailable: true,
            boundaryKind: .mixtureEnvelope,
            model: mixture.response.model
        )

        XCTAssertNoThrow(
            try PhaseDiagramImageExporter().attachment(
                for: pure,
                response: pureResponse
            )
        )
        let artifacts = try PhaseDiagramImageExporter().writeTemporaryReportFiles(
            for: pure,
            response: pureResponse
        )
        XCTAssertEqual(Set(artifacts.files.map(\.pathExtension)), ["pdf", "csv"])
        for file in artifacts.files {
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
            try? FileManager.default.removeItem(at: file)
        }
        XCTAssertThrowsError(
            try PhaseDiagramImageExporter().attachment(
                for: mixture,
                response: mixtureResponse
            )
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                PhaseDiagramEligibility.pureCarbonDioxideScopeMessage
            )
        }
    }

    @MainActor
    func testPhaseBoundarySegmentsTerminateAtInvalidPointsBranchChangesAndCriticalPoints() {
        let response = PhaseEnvelopeResponse(
            requestID: UUID(),
            points: [
                .init(temperatureK: 230, pressurePa: 1_000_000, branch: .bubble),
                .init(temperatureK: 240, pressurePa: 1_500_000, branch: .bubble),
                .init(temperatureK: .nan, pressurePa: 1_800_000, branch: .bubble),
                .init(temperatureK: 250, pressurePa: 2_000_000, branch: .bubble),
                .init(temperatureK: 260, pressurePa: -1, branch: .bubble),
                .init(temperatureK: 270, pressurePa: 2_500_000, branch: .bubble),
                .init(temperatureK: 280, pressurePa: 2_800_000, branch: .dew),
                .init(temperatureK: 290, pressurePa: 3_000_000, branch: .dew),
                .init(temperatureK: 304.1282, pressurePa: 7_377_300, branch: .critical),
                .init(temperatureK: 300, pressurePa: 6_000_000, branch: .bubble),
                .init(temperatureK: 301, pressurePa: 6_100_000, branch: .bubble)
            ],
            warnings: [],
            isAvailable: true,
            boundaryKind: .pureFluidSaturation
        )

        let plotData = PhaseBoundarySeriesBuilder.plotData(for: response)

        XCTAssertEqual(plotData.receivedPointCount, 11)
        XCTAssertEqual(plotData.validPointCount, 9)
        XCTAssertEqual(plotData.plottedPointCount, 7)
        XCTAssertEqual(plotData.criticalPoints.map(\.originalIndex), [8])
        XCTAssertEqual(plotData.segments.map { $0.points.map(\.originalIndex) }, [
            [0, 1],
            [6, 7],
            [9, 10]
        ])
        XCTAssertTrue(plotData.segments.allSatisfy { segment in
            Set(segment.points.map(\.branch)) == [segment.branch]
        })
    }

    @MainActor
    func testPhaseBoundaryPlotCountsSingletonBoundaryAsValidButNotPlotted() {
        let plotData = PhaseBoundarySeriesBuilder.plotData(for: PhaseEnvelopeResponse(
            requestID: UUID(),
            points: [.init(temperatureK: 250, pressurePa: 1_800_000, branch: .bubble)],
            warnings: [],
            isAvailable: true,
            boundaryKind: .pureFluidSaturation
        ))

        XCTAssertEqual(plotData.receivedPointCount, 1)
        XCTAssertEqual(plotData.validPointCount, 1)
        XCTAssertEqual(plotData.plottedPointCount, 0)
        XCTAssertTrue(plotData.segments.isEmpty)
    }

    @MainActor
    func testPhaseBoundaryPlotCountsTwoAdjacentBoundaryPointsAsPlotted() {
        let plotData = PhaseBoundarySeriesBuilder.plotData(for: PhaseEnvelopeResponse(
            requestID: UUID(),
            points: [
                .init(temperatureK: 250, pressurePa: 1_800_000, branch: .bubble),
                .init(temperatureK: 260, pressurePa: 2_100_000, branch: .bubble)
            ],
            warnings: [],
            isAvailable: true,
            boundaryKind: .pureFluidSaturation
        ))

        XCTAssertEqual(plotData.validPointCount, 2)
        XCTAssertEqual(plotData.plottedPointCount, 2)
        XCTAssertEqual(plotData.segments.first?.points.map(\.originalIndex), [0, 1])
    }

    @MainActor
    func testPhaseBoundaryPlotDropsSingletonBetweenGaps() {
        let plotData = PhaseBoundarySeriesBuilder.plotData(for: PhaseEnvelopeResponse(
            requestID: UUID(),
            points: [
                .init(temperatureK: .nan, pressurePa: 1_000_000, branch: .bubble),
                .init(temperatureK: 250, pressurePa: 1_800_000, branch: .bubble),
                .init(temperatureK: 260, pressurePa: -1, branch: .bubble)
            ],
            warnings: [],
            isAvailable: true,
            boundaryKind: .pureFluidSaturation
        ))

        XCTAssertEqual(plotData.receivedPointCount, 3)
        XCTAssertEqual(plotData.validPointCount, 1)
        XCTAssertEqual(plotData.plottedPointCount, 0)
        XCTAssertTrue(plotData.segments.isEmpty)
    }

    @MainActor
    func testPhaseBoundaryPlotCountsCriticalOnlyWhenRenderedButNoLineSegment() {
        let plotData = PhaseBoundarySeriesBuilder.plotData(for: PhaseEnvelopeResponse(
            requestID: UUID(),
            points: [.init(temperatureK: 304.1282, pressurePa: 7_377_300, branch: .critical)],
            warnings: [],
            isAvailable: true,
            boundaryKind: .pureFluidSaturation
        ))

        XCTAssertEqual(plotData.validPointCount, 1)
        XCTAssertEqual(plotData.plottedPointCount, 1)
        XCTAssertEqual(plotData.criticalPoints.map(\.originalIndex), [0])
        XCTAssertTrue(plotData.segments.isEmpty)
    }

    @MainActor
    func testPhaseBoundaryPlotCountsLineSegmentPlusCriticalPoint() {
        let plotData = PhaseBoundarySeriesBuilder.plotData(for: PhaseEnvelopeResponse(
            requestID: UUID(),
            points: [
                .init(temperatureK: 250, pressurePa: 1_800_000, branch: .bubble),
                .init(temperatureK: 260, pressurePa: 2_100_000, branch: .bubble),
                .init(temperatureK: 304.1282, pressurePa: 7_377_300, branch: .critical)
            ],
            warnings: [],
            isAvailable: true,
            boundaryKind: .pureFluidSaturation
        ))

        XCTAssertEqual(plotData.validPointCount, 3)
        XCTAssertEqual(plotData.plottedPointCount, 3)
        XCTAssertEqual(plotData.segments.first?.points.count, 2)
        XCTAssertEqual(plotData.criticalPoints.count, 1)
    }

    @MainActor
    func testPhaseDiagramExportRejectsResponseWithoutRenderableBoundarySegment() async throws {
        let record = try await makeRecord()
        let response = PhaseEnvelopeResponse(
            requestID: record.request.requestID,
            points: [
                .init(temperatureK: 250, pressurePa: 1_800_000, branch: .bubble),
                .init(temperatureK: 304.1282, pressurePa: 7_377_300, branch: .critical)
            ],
            warnings: [],
            isAvailable: true,
            boundaryKind: .pureFluidSaturation,
            model: record.response.model,
            solver: .init(method: "test", converged: true, durationMilliseconds: 1)
        )

        XCTAssertThrowsError(
            try PhaseDiagramImageExporter().writeTemporaryReportFiles(
                for: record,
                response: response
            )
        )
    }

    @MainActor
    func testPhaseDiagramExportRejectsNonConvergedResponse() async throws {
        let record = try await makeRecord()
        let response = PhaseEnvelopeResponse(
            requestID: record.request.requestID,
            points: [
                .init(temperatureK: 250, pressurePa: 1_800_000, branch: .bubble),
                .init(temperatureK: 260, pressurePa: 2_100_000, branch: .bubble)
            ],
            warnings: ["Synthetic non-converged response."],
            isAvailable: true,
            boundaryKind: .pureFluidSaturation,
            model: record.response.model,
            solver: .init(method: "test", converged: false, durationMilliseconds: 1)
        )

        XCTAssertThrowsError(
            try PhaseDiagramImageExporter().writeTemporaryReportFiles(
                for: record,
                response: response
            )
        )
    }

    @MainActor
    func testPhaseDiagramTemporaryStoreCleansOnlyOwnedArtifacts() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = PhaseDiagramTemporaryExportStore(baseDirectory: base)
        try FileManager.default.createDirectory(
            at: store.directory,
            withIntermediateDirectories: true
        )
        let owned = store.directory.appendingPathComponent("PhaseXpert-Phase-Diagram-test.pdf")
        let unrelated = store.directory.appendingPathComponent("Other.txt")
        try Data("owned".utf8).write(to: owned)
        try Data("other".utf8).write(to: unrelated)

        try store.cleanStaleArtifacts()

        XCTAssertFalse(FileManager.default.fileExists(atPath: owned.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
        try? FileManager.default.removeItem(at: base)
    }

    @MainActor
    func testPhaseDiagramExportLifecycleCleansPreparedArtifactsWhenViewCleansUp() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = PhaseDiagramTemporaryExportStore(baseDirectory: base)
        let lifecycle = PhaseDiagramExportLifecycle(store: store)
        let artifacts = try makeTemporaryDiagramArtifacts(in: store, id: "cleanup")

        try lifecycle.prepareReplacement { artifacts }
        lifecycle.cleanupIfIdle()

        XCTAssertNil(lifecycle.artifacts)
        XCTAssertFalse(FileManager.default.fileExists(atPath: artifacts.files[0].path))
        try? FileManager.default.removeItem(at: base)
    }

    @MainActor
    func testPhaseDiagramExportLifecycleCleansAfterShareCompletionAndCancellation() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = PhaseDiagramTemporaryExportStore(baseDirectory: base)
        let lifecycle = PhaseDiagramExportLifecycle(store: store)

        try lifecycle.prepareReplacement {
            try makeTemporaryDiagramArtifacts(in: store, id: "completed")
        }
        let completed = try XCTUnwrap(lifecycle.artifacts)
        lifecycle.beginSharing()
        lifecycle.cleanupIfIdle()
        XCTAssertTrue(FileManager.default.fileExists(atPath: completed.files[0].path))
        lifecycle.completeSharing()
        XCTAssertNil(lifecycle.artifacts)
        XCTAssertFalse(FileManager.default.fileExists(atPath: completed.files[0].path))

        try lifecycle.prepareReplacement {
            try makeTemporaryDiagramArtifacts(in: store, id: "cancelled")
        }
        let cancelled = try XCTUnwrap(lifecycle.artifacts)
        lifecycle.beginSharing()
        lifecycle.completeSharing()
        XCTAssertFalse(FileManager.default.fileExists(atPath: cancelled.files[0].path))
        try? FileManager.default.removeItem(at: base)
    }

    @MainActor
    func testPhaseDiagramExportLifecycleCleansOnCalculationChangeWhenIdle() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = PhaseDiagramTemporaryExportStore(baseDirectory: base)
        let lifecycle = PhaseDiagramExportLifecycle(store: store)
        let artifacts = try makeTemporaryDiagramArtifacts(in: store, id: "changed")

        try lifecycle.prepareReplacement { artifacts }
        lifecycle.calculationChanged()

        XCTAssertNil(lifecycle.artifacts)
        XCTAssertFalse(FileManager.default.fileExists(atPath: artifacts.files[0].path))
        try? FileManager.default.removeItem(at: base)
    }

    @MainActor
    func testPhaseDiagramExportLifecycleReplacementCleansStaleOwnedFilesOnly() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = PhaseDiagramTemporaryExportStore(baseDirectory: base)
        let lifecycle = PhaseDiagramExportLifecycle(store: store)
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let stale = store.directory.appendingPathComponent("PhaseXpert-Phase-Diagram-stale.pdf")
        let unrelated = store.directory.appendingPathComponent("external.pdf")
        try Data("stale".utf8).write(to: stale)
        try Data("external".utf8).write(to: unrelated)

        try lifecycle.prepareReplacement {
            try makeTemporaryDiagramArtifacts(in: store, id: "replacement")
        }
        let replacement = try XCTUnwrap(lifecycle.artifacts)

        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: replacement.files[0].path))
        try? FileManager.default.removeItem(at: base)
    }

    @MainActor
    func testPhaseDiagramExportRemovesPDFWhenCSVWriteFails() async throws {
        let record = try await makeRecord()
        let response = PhaseEnvelopeResponse(
            requestID: record.request.requestID,
            points: [
                .init(temperatureK: 250, pressurePa: 1_800_000, branch: .bubble),
                .init(temperatureK: 260, pressurePa: 2_100_000, branch: .bubble)
            ],
            warnings: [],
            isAvailable: true,
            boundaryKind: .pureFluidSaturation,
            model: record.response.model,
            solver: .init(method: "test", converged: true, durationMilliseconds: 1)
        )

        XCTAssertThrowsError(
            try PhaseDiagramImageExporter().writeTemporaryReportFiles(
                for: record,
                response: response,
                csvWriter: { _, _ in throw CalculationExportError.textEncodingFailed }
            )
        )

        let store = PhaseDiagramTemporaryExportStore()
        let pdfURL = store.directory.appendingPathComponent(
            "PhaseXpert-Phase-Diagram-\(record.response.calculationID.uuidString.prefix(8)).pdf"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: pdfURL.path))
    }

    @MainActor
    func testCalculatorStartsWithCoolPropSelected() {
        let viewModel = CalculatorViewModel()
        XCTAssertEqual(viewModel.selectedModelID, "coolprop-heos")
        XCTAssertEqual(viewModel.compositionBasis, .partsPerMillion)
        XCTAssertEqual(viewModel.carbonDioxidePartsPerMillion, 1_000_000)
    }

    @MainActor
    func testSavedCaseDefaultNameIncludesActiveMixtureComposition() {
        XCTAssertEqual(
            SavedCaseNameFormatter.compositionLabel(for: [
                .init(component: .carbonDioxide, moleFraction: 0.95),
                .init(component: .nitrogen, moleFraction: 0.05)
            ]),
            "CO₂ 95 mol% + N₂ 5 mol%"
        )
        XCTAssertEqual(
            SavedCaseNameFormatter.compositionLabel(for: [
                .init(component: .carbonDioxide, moleFraction: 1)
            ]),
            "CO₂"
        )
    }

    @MainActor
    func testNewImpurityStartsEmptyAndReturnsItsFocusIdentity() {
        let viewModel = CalculatorViewModel()

        let addedID = viewModel.addImpurity()

        XCTAssertEqual(viewModel.composition.count, 2)
        XCTAssertEqual(viewModel.composition.last?.id, addedID)
        XCTAssertEqual(viewModel.composition.last?.value, "")
    }

    @MainActor
    func testPPMInputCompletesCarbonDioxideRemainderWithoutNormalization() throws {
        let viewModel = CalculatorViewModel()
        _ = viewModel.addImpurity()
        let impurityIndex = try XCTUnwrap(
            viewModel.composition.firstIndex { $0.component != .carbonDioxide }
        )
        viewModel.composition[impurityIndex].value = "12500"
        viewModel.validate()

        XCTAssertEqual(viewModel.carbonDioxidePartsPerMillion, 987_500, accuracy: 1e-12)
        XCTAssertFalse(viewModel.canNormalize)
        XCTAssertFalse(viewModel.validationReport.issues.contains { $0.code == .compositionTotal })
    }

    @MainActor
    func testMolePercentInputCompletesCarbonDioxideRemainderWithoutNormalization() throws {
        let viewModel = CalculatorViewModel()
        viewModel.changeCompositionBasis(to: .molePercent)
        _ = viewModel.addImpurity()
        let impurityIndex = try XCTUnwrap(
            viewModel.composition.firstIndex { $0.component != .carbonDioxide }
        )
        viewModel.composition[impurityIndex].value = "12.5"
        viewModel.validate()

        XCTAssertEqual(viewModel.carbonDioxideMolePercent, 87.5, accuracy: 1e-12)
        XCTAssertEqual(
            viewModel.displayedCompositionValue(for: viewModel.composition[0]),
            "87.5"
        )
        XCTAssertFalse(viewModel.canNormalize)
        XCTAssertFalse(
            viewModel.validationReport.issues.contains { $0.code == .compositionTotal }
        )
    }

    @MainActor
    func testImpurityCanBeRemovedByIdentityAndRemainderUpdates() throws {
        let viewModel = CalculatorViewModel()
        let firstID = try XCTUnwrap(viewModel.addImpurity())
        let secondID = try XCTUnwrap(viewModel.addImpurity())
        _ = try XCTUnwrap(viewModel.addImpurity())

        for index in viewModel.composition.indices
        where viewModel.composition[index].component != .carbonDioxide {
            viewModel.composition[index].value = "10000"
        }
        XCTAssertEqual(viewModel.carbonDioxidePartsPerMillion, 970_000, accuracy: 1e-12)

        viewModel.removeImpurity(id: secondID)

        XCTAssertEqual(viewModel.composition.count, 3)
        XCTAssertEqual(viewModel.composition.first?.component, .carbonDioxide)
        XCTAssertTrue(viewModel.composition.contains { $0.id == firstID })
        XCTAssertFalse(viewModel.composition.contains { $0.id == secondID })
        XCTAssertEqual(viewModel.carbonDioxidePartsPerMillion, 980_000, accuracy: 1e-12)
    }

    @MainActor
    func testCompositionBasisRoundTripPreservesMoleFractions() throws {
        let viewModel = CalculatorViewModel()
        _ = viewModel.addImpurity()
        let impurityIndex = try XCTUnwrap(
            viewModel.composition.firstIndex { $0.component != .carbonDioxide }
        )
        viewModel.composition[impurityIndex].value = "10000"

        viewModel.changeCompositionBasis(to: .molePercent)
        XCTAssertEqual(viewModel.carbonDioxideMolePercent, 99, accuracy: 1e-12)
        XCTAssertEqual(
            viewModel.displayedCompositionValue(for: viewModel.composition[0]),
            "99"
        )
        XCTAssertEqual(viewModel.composition[impurityIndex].value, "1")

        viewModel.changeCompositionBasis(to: .partsPerMillion)
        XCTAssertEqual(viewModel.carbonDioxidePartsPerMillion, 990_000, accuracy: 1e-12)
        XCTAssertEqual(viewModel.composition[impurityIndex].value, "10000")
    }

    @MainActor
    func testPressureUnitChangePreservesPhysicalSIValue() {
        let viewModel = CalculatorViewModel()
        viewModel.pressureText = "150"
        viewModel.validate()

        viewModel.changePressureDisplayUnit(to: .megapascalAbsolute)

        XCTAssertEqual(Double(viewModel.pressureText) ?? .nan, 15, accuracy: 1e-12)
        XCTAssertEqual(viewModel.pressureDisplayUnit, .megapascalAbsolute)
        XCTAssertTrue(viewModel.validationReport.canCalculate)

        viewModel.changePressureDisplayUnit(to: .psiAbsolute)
        XCTAssertEqual(
            Double(viewModel.pressureText) ?? .nan,
            15_000_000 / UnitConstants.psiToPascal,
            accuracy: 1e-7
        )
        XCTAssertTrue(viewModel.validationReport.canCalculate)

        for _ in 0..<10 {
            viewModel.changePressureDisplayUnit(to: .barAbsolute)
            viewModel.changePressureDisplayUnit(to: .megapascalAbsolute)
            viewModel.changePressureDisplayUnit(to: .psiAbsolute)
        }
        XCTAssertEqual(
            PressureDisplayUnit.psiAbsolute.pascal(from: Double(viewModel.pressureText) ?? .nan),
            15_000_000,
            accuracy: 1e-3
        )
    }

    @MainActor
    func testPSIAbsolutePressureDisplayUnitConvertsToAndFromPascal() {
        XCTAssertEqual(
            PressureDisplayUnit.psiAbsolute.pascal(from: 1),
            6_894.757_293_168,
            accuracy: 1e-12
        )
        XCTAssertEqual(
            PressureDisplayUnit.psiAbsolute.displayValue(from: 6_894.757_293_168),
            1,
            accuracy: 1e-12
        )
        XCTAssertEqual(
            CalculationInputSnapshot(
                pressureValue: 2_175.566_119_4,
                pressureUnit: .psia,
                pressurePa: 15_000_000,
                temperatureValue: 20,
                temperatureUnit: .celsius,
                temperatureK: 293.15,
                originalComposition: []
            ).pressureDisplayUnitLabel,
            "psi(a)"
        )
        XCTAssertEqual(
            CalculationInputSnapshot(
                pressureValue: 2_175.566_119_4,
                pressureUnit: .psi,
                pressurePa: 15_000_000,
                temperatureValue: 20,
                temperatureUnit: .celsius,
                temperatureK: 293.15,
                originalComposition: []
            ).pressureDisplayUnitLabel,
            "psi"
        )
    }

    @MainActor
    func testCalculationSnapshotPreservesMegapascalAndKelvinEntryUnits() async throws {
        let record = try await makeRecord(
            pressureValue: 15,
            pressureUnit: .megapascal,
            pressurePa: 15_000_000,
            temperatureValue: 293.15,
            temperatureUnit: .kelvin,
            temperatureK: 293.15,
            composition: [.init(component: .carbonDioxide, moleFraction: 1)]
        )

        XCTAssertEqual(record.input.pressureValue, 15, accuracy: 1e-12)
        XCTAssertEqual(record.input.pressureUnit, .megapascal)
        XCTAssertEqual(record.input.pressureDisplayUnitLabel, "MPa(a)")
        XCTAssertEqual(record.input.pressurePa, 15_000_000, accuracy: 1e-12)
        XCTAssertEqual(record.input.temperatureValue, 293.15, accuracy: 1e-12)
        XCTAssertEqual(record.input.temperatureUnit, .kelvin)
        XCTAssertEqual(record.input.temperatureK, 293.15, accuracy: 1e-12)
    }

    @MainActor
    func testCalculationSnapshotPreservesPSIAndFahrenheitEntryUnits() async throws {
        let pressurePsi = 2_175.566_119_4
        let pressurePa = PressureUnit.psia.toPascal(pressurePsi)
        let record = try await makeRecord(
            pressureValue: pressurePsi,
            pressureUnit: .psia,
            pressurePa: pressurePa,
            temperatureValue: 68,
            temperatureUnit: .fahrenheit,
            temperatureK: TemperatureUnit.fahrenheit.toKelvin(68),
            composition: [.init(component: .carbonDioxide, moleFraction: 1)]
        )

        XCTAssertEqual(record.input.pressureValue, pressurePsi, accuracy: 1e-12)
        XCTAssertEqual(record.input.pressureUnit, .psia)
        XCTAssertEqual(record.input.pressureDisplayUnitLabel, "psi(a)")
        XCTAssertEqual(record.input.pressurePa, pressurePa, accuracy: 1e-6)
        XCTAssertEqual(record.input.temperatureValue, 68, accuracy: 1e-12)
        XCTAssertEqual(record.input.temperatureUnit, .fahrenheit)
        XCTAssertEqual(record.input.temperatureK, 293.15, accuracy: 1e-12)
    }

    @MainActor
    func testViewModelCalculationPreservesPSIAndFahrenheitProvenance() async throws {
        let viewModel = CalculatorViewModel()
        let pressurePsi = PressureUnit.psia.fromPascal(15_000_000)
        viewModel.pressureDisplayUnit = .psiAbsolute
        viewModel.temperatureDisplayUnit = .fahrenheit
        viewModel.pressureText = String(pressurePsi)
        viewModel.temperatureText = "68"
        viewModel.validate()

        await viewModel.calculate()

        let record = try XCTUnwrap(viewModel.calculationRecord)
        XCTAssertEqual(record.input.pressureUnit, .psia)
        XCTAssertEqual(record.input.pressureDisplayUnitLabel, "psi(a)")
        XCTAssertEqual(record.input.pressureValue, pressurePsi, accuracy: 1e-10)
        XCTAssertEqual(record.input.pressurePa, 15_000_000, accuracy: 1e-3)
        XCTAssertEqual(record.input.temperatureUnit, .fahrenheit)
        XCTAssertEqual(record.input.temperatureValue, 68, accuracy: 1e-12)
        XCTAssertEqual(record.input.temperatureK, 293.15, accuracy: 1e-12)
    }

    @MainActor
    func testHistoricalBarCelsiusRecordDecodesWithoutReinterpretingUnits() async throws {
        let historical = try await makeRecord(
            pressureValue: 150,
            pressureUnit: .bara,
            pressurePa: 15_000_000,
            temperatureValue: 20,
            temperatureUnit: .celsius,
            temperatureK: 293.15,
            composition: [.init(component: .carbonDioxide, moleFraction: 1)]
        )
        let data = try JSONEncoder().encode(historical)

        let decoded = try JSONDecoder().decode(CalculationRecord.self, from: data)

        XCTAssertEqual(decoded.input.pressureValue, 150, accuracy: 1e-12)
        XCTAssertEqual(decoded.input.pressureUnit, .bara)
        XCTAssertEqual(decoded.input.pressureDisplayUnitLabel, "bar(a)")
        XCTAssertEqual(decoded.input.temperatureValue, 20, accuracy: 1e-12)
        XCTAssertEqual(decoded.input.temperatureUnit, .celsius)
    }

    @MainActor
    func testTemperatureUnitChangePreservesPhysicalSIValue() {
        let viewModel = CalculatorViewModel()
        viewModel.temperatureText = "20"
        viewModel.validate()

        viewModel.changeTemperatureDisplayUnit(to: .kelvin)

        XCTAssertEqual(Double(viewModel.temperatureText) ?? .nan, 293.15, accuracy: 1e-12)
        XCTAssertEqual(viewModel.temperatureDisplayUnit, .kelvin)
        XCTAssertTrue(viewModel.validationReport.canCalculate)

        viewModel.changeTemperatureDisplayUnit(to: .fahrenheit)
        XCTAssertEqual(Double(viewModel.temperatureText) ?? .nan, 68, accuracy: 1e-10)
        XCTAssertTrue(viewModel.validationReport.canCalculate)

        for _ in 0..<10 {
            viewModel.changeTemperatureDisplayUnit(to: .celsius)
            viewModel.changeTemperatureDisplayUnit(to: .kelvin)
            viewModel.changeTemperatureDisplayUnit(to: .fahrenheit)
        }
        XCTAssertEqual(
            TemperatureDisplayUnit.fahrenheit.kelvin(from: Double(viewModel.temperatureText) ?? .nan),
            293.15,
            accuracy: 1e-10
        )
    }

    @MainActor
    func testFahrenheitTemperatureDisplayUnitConvertsToAndFromKelvin() {
        XCTAssertEqual(
            TemperatureDisplayUnit.fahrenheit.kelvin(from: 0),
            255.3722222222222,
            accuracy: 1e-12
        )
        XCTAssertEqual(TemperatureDisplayUnit.fahrenheit.kelvin(from: 32), 273.15, accuracy: 1e-12)
        XCTAssertEqual(TemperatureDisplayUnit.fahrenheit.kelvin(from: 212), 373.15, accuracy: 1e-12)
        XCTAssertEqual(TemperatureDisplayUnit.fahrenheit.displayValue(from: 273.15), 32, accuracy: 1e-12)
        XCTAssertEqual(TemperatureDisplayUnit.fahrenheit.displayValue(from: 373.15), 212, accuracy: 1e-12)
    }

    @MainActor
    func testInvalidOperatingPointEntryDoesNotCorruptLastValidDisplayUnitConversion() {
        let viewModel = CalculatorViewModel()
        viewModel.pressureText = "150"
        viewModel.temperatureText = "20"
        viewModel.validate()

        viewModel.pressureText = "not-a-number"
        viewModel.validate()
        XCTAssertFalse(viewModel.validationReport.canCalculate)

        viewModel.changePressureDisplayUnit(to: .megapascalAbsolute)

        XCTAssertEqual(Double(viewModel.pressureText) ?? .nan, 15, accuracy: 1e-12)
        XCTAssertEqual(viewModel.pressureDisplayUnit, .megapascalAbsolute)

        viewModel.pressureText = "-"
        viewModel.validate()
        XCTAssertFalse(viewModel.validationReport.canCalculate)

        viewModel.changePressureDisplayUnit(to: .psiAbsolute)

        XCTAssertEqual(
            PressureDisplayUnit.psiAbsolute.pascal(from: Double(viewModel.pressureText) ?? .nan),
            15_000_000,
            accuracy: 1e-3
        )
        XCTAssertEqual(viewModel.pressureDisplayUnit, .psiAbsolute)

        viewModel.temperatureText = ""
        viewModel.validate()
        XCTAssertFalse(viewModel.validationReport.canCalculate)

        viewModel.changeTemperatureDisplayUnit(to: .kelvin)

        XCTAssertEqual(Double(viewModel.temperatureText) ?? .nan, 293.15, accuracy: 1e-12)
        XCTAssertEqual(viewModel.temperatureDisplayUnit, .kelvin)

        viewModel.temperatureText = "-"
        viewModel.validate()
        XCTAssertFalse(viewModel.validationReport.canCalculate)

        viewModel.changeTemperatureDisplayUnit(to: .fahrenheit)

        XCTAssertEqual(Double(viewModel.temperatureText) ?? .nan, 68, accuracy: 1e-10)
        XCTAssertEqual(viewModel.temperatureDisplayUnit, .fahrenheit)
    }

    @MainActor
    func testMovingImpuritiesKeepsCO2FirstAndPreservesStableIDs() throws {
        let viewModel = CalculatorViewModel()
        let firstID = try XCTUnwrap(viewModel.addImpurity())
        let secondID = try XCTUnwrap(viewModel.addImpurity())
        viewModel.composition[1].value = "100"
        viewModel.composition[2].value = "200"

        viewModel.moveImpurities(from: IndexSet(integer: 2), to: 1)

        XCTAssertEqual(viewModel.composition.first?.component, .carbonDioxide)
        XCTAssertEqual(viewModel.composition.map(\.id).dropFirst(), [secondID, firstID])
        XCTAssertEqual(viewModel.composition[1].value, "200")
        XCTAssertEqual(viewModel.composition[2].value, "100")
    }

    @MainActor
    func testEngineeringFormatterConvertsDisplayUnitsWithoutChangingSIValue() {
        let enthalpy = PropertyValue(
            property: .enthalpy,
            value: 300_000,
            unit: "J/kg",
            status: .calculated
        )
        let viscosity = PropertyValue(
            property: .dynamicViscosity,
            value: 0.000_093,
            unit: "Pa·s",
            status: .calculated
        )

        let displayedEnthalpy = EngineeringPropertyFormatter.measurement(for: enthalpy)
        let displayedViscosity = EngineeringPropertyFormatter.measurement(for: viscosity)
        XCTAssertEqual(displayedEnthalpy?.value ?? .nan, 300, accuracy: 1e-12)
        XCTAssertEqual(displayedEnthalpy?.unit, "kJ/kg")
        XCTAssertEqual(displayedViscosity?.value ?? .nan, 0.093, accuracy: 1e-12)
        XCTAssertEqual(displayedViscosity?.unit, "mPa·s")
        XCTAssertEqual(enthalpy.value, 300_000)
        XCTAssertEqual(enthalpy.unit, "J/kg")
    }

    @MainActor
    func testUnsupportedPropertyFormattingRemainsExplicitlyUnavailable() {
        let property = PropertyValue(
            property: .enthalpy,
            value: nil,
            unit: "J/kg",
            status: .unavailable,
            message: "Expanded pure-fluid property unavailable for this composition."
        )

        XCTAssertEqual(EngineeringPropertyFormatter.text(for: property), "Unavailable")
        XCTAssertEqual(EngineeringPropertyFormatter.effectiveStatus(for: property), .unavailable)
    }

    @MainActor
    func testPropertyResultRowPresentationExposesCopyOnlyForFiniteValues() {
        let available = PropertyResultPresentation(property: PropertyValue(
            property: .density,
            value: 903.5,
            unit: "kg/m³",
            status: .calculated,
            message: "Calculated density."
        ))
        let unavailable = PropertyResultPresentation(property: PropertyValue(
            property: .enthalpy,
            value: nil,
            unit: "J/kg",
            status: .unavailable,
            message: "Unavailable for this composition."
        ))
        let nonFinite = PropertyResultPresentation(property: PropertyValue(
            property: .density,
            value: .nan,
            unit: "kg/m³",
            status: .calculated
        ))

        XCTAssertEqual(available.title, "Density")
        XCTAssertFalse(available.value.isEmpty)
        XCTAssertNotEqual(available.value, "Unavailable")
        XCTAssertEqual(available.unit, "kg/m³")
        XCTAssertEqual(available.copyValue, "903.5 kg/m³")
        XCTAssertTrue(available.statusText.contains("Calculated"))
        XCTAssertNil(unavailable.copyValue)
        XCTAssertNil(nonFinite.copyValue)
        XCTAssertEqual(unavailable.value, "Unavailable")
    }

    @MainActor
    func testReferenceLinkResolverAcceptsOnlyHTTPSAndDOIIdentifiers() {
        XCTAssertEqual(
            ReferenceLinkResolver.url(for: "10.1016/j.fluid.2020.112"),
            URL(string: "https://doi.org/10.1016/j.fluid.2020.112")
        )
        XCTAssertEqual(
            ReferenceLinkResolver.url(for: "doi:10.1021/acs.jced.1c00123"),
            URL(string: "https://doi.org/10.1021/acs.jced.1c00123")
        )
        XCTAssertEqual(
            ReferenceLinkResolver.url(for: "https://example.org/reference"),
            URL(string: "https://example.org/reference")
        )
        XCTAssertNil(ReferenceLinkResolver.url(for: "http://example.org/reference"))
        XCTAssertNil(ReferenceLinkResolver.url(for: "10/not-a-doi"))
        XCTAssertNil(ReferenceLinkResolver.url(for: "   "))
        XCTAssertNil(ReferenceLinkResolver.url(for: "ftp://example.org/reference"))
    }

    private var expectedDefaultCoolPropAvailability: ModelAvailability {
        #if os(iOS) && canImport(PhaseXpertCoolPropBridge)
        .preliminary
        #else
        .unavailable
        #endif
    }

    @MainActor
    func testSavedCalculationPersistsAndPreservesRecord() async throws {
        let record = try await makeRecord()
        let schema = Schema(versionedSchema: PhaseXpertSchemaV1.self)
        let configuration = ModelConfiguration(
            "PhaseXpertTests",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: PhaseXpertMigrationPlan.self,
            configurations: [configuration]
        )
        let context = ModelContext(container)
        let savedCase = try SavedCalculation(
            name: "Pipeline inlet",
            notes: "Reference operating point",
            record: record
        )

        context.insert(savedCase)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<SavedCalculation>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.name, "Pipeline inlet")
        XCTAssertEqual(fetched.first?.calculationRecord, record)
        XCTAssertEqual(fetched.first?.recordFormatVersion, 1)
    }

    @MainActor
    func testSavedCalculationDuplicateGetsNewIdentityAndKeepsProvenance() async throws {
        let record = try await makeRecord()
        let savedCase = try SavedCalculation(name: "Ship tank", record: record)
        let duplicate = savedCase.duplicate()

        XCTAssertNotEqual(duplicate.id, savedCase.id)
        XCTAssertEqual(duplicate.name, "Ship tank — Copy")
        XCTAssertEqual(duplicate.calculationID, savedCase.calculationID)
        XCTAssertEqual(duplicate.calculationRecord, record)
    }

    @MainActor
    func testComparisonComputesDifferencesInDisplayedEngineeringUnits() async throws {
        let reference = try await makeComparisonRecord(
            pressureBar: 150,
            temperatureCelsius: 20,
            density: 900,
            viscosityPascalSeconds: 0.00009
        )
        let compared = try await makeComparisonRecord(
            pressureBar: 120,
            temperatureCelsius: -20,
            density: 1_000,
            viscosityPascalSeconds: 0.00012
        )

        let comparison = CalculationComparison(
            reference: reference,
            compared: compared
        )
        let density = try XCTUnwrap(
            comparison.properties.first { $0.id == .density }
        )
        let viscosity = try XCTUnwrap(
            comparison.properties.first { $0.id == .dynamicViscosity }
        )

        XCTAssertEqual(comparison.pressureDifferenceBar, -30, accuracy: 1e-12)
        XCTAssertEqual(comparison.temperatureDifferenceCelsius, -40, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(density.difference), 100, accuracy: 1e-12)
        XCTAssertEqual(density.displayUnit, "kg/m³")
        XCTAssertEqual(try XCTUnwrap(viscosity.difference), 0.03, accuracy: 1e-12)
        XCTAssertEqual(viscosity.displayUnit, "mPa·s")
    }

    @MainActor
    func testComparisonDoesNotCreateDifferenceForUnavailableValue() async throws {
        let reference = try await makeComparisonRecord(
            pressureBar: 150,
            temperatureCelsius: 20,
            density: 900,
            viscosityPascalSeconds: 0.00009
        )
        let compared = try await makeComparisonRecord(
            pressureBar: 150,
            temperatureCelsius: 20,
            density: nil,
            viscosityPascalSeconds: 0.00009
        )

        let comparison = CalculationComparison(
            reference: reference,
            compared: compared
        )
        let density = try XCTUnwrap(
            comparison.properties.first { $0.id == .density }
        )

        XCTAssertNil(density.difference)
        XCTAssertTrue(comparison.nonComparableProperties.contains(density))
    }

    @MainActor
    private func makeRecord() async throws -> CalculationRecord {
        try await makeRecord(composition: [.init(component: .carbonDioxide, moleFraction: 1)])
    }

    @MainActor
    private func makeRecord(
        modelID: String = PhaseXpertTests.testDescriptor.id,
        modelDescriptor: ModelDescriptor = PhaseXpertTests.testDescriptor,
        pressureValue: Double = 150,
        pressureUnit: PressureUnit = .bara,
        pressurePa: Double = 15_000_000,
        temperatureValue: Double = 20,
        temperatureUnit: TemperatureUnit = .celsius,
        temperatureK: Double = 293.15,
        composition: [MixtureComponent]
    ) async throws -> CalculationRecord {
        let request = CalculationRequest(
            modelID: modelID,
            pressurePa: pressurePa,
            temperatureK: temperatureK,
            composition: composition,
            requestedProperties: [.density],
            clientVersion: "test"
        )
        let response = CalculationResponse(
            requestID: request.requestID,
            model: modelDescriptor,
            phase: .dense,
            properties: [
                PropertyValue(
                    property: .density,
                    value: 800,
                    unit: "kg/m³",
                    status: .calculated,
                    message: "Test density."
                )
            ],
            solver: SolverMetadata(
                method: "Test calculation",
                converged: true,
                durationMilliseconds: 1
            ),
            warnings: [],
            isScientificResult: false
        )
        return CalculationRecord(
            request: request,
            input: CalculationInputSnapshot(
                pressureValue: pressureValue,
                pressureUnit: pressureUnit,
                pressurePa: pressurePa,
                temperatureValue: temperatureValue,
                temperatureUnit: temperatureUnit,
                temperatureK: temperatureK,
                originalComposition: composition.map {
                    .init(
                        component: $0.component,
                        value: $0.moleFraction * 100,
                        unit: .molePercent
                    )
                }
            ),
            response: response,
            application: .init(version: "1.0", build: "1")
        )
    }

    @MainActor
    private func makeComparisonRecord(
        pressureBar: Double,
        temperatureCelsius: Double,
        density: Double?,
        viscosityPascalSeconds: Double
    ) async throws -> CalculationRecord {
        let base = try await makeRecord()
        let request = CalculationRequest(
            modelID: base.response.model.id,
            pressurePa: pressureBar * 100_000,
            temperatureK: temperatureCelsius + 273.15,
            composition: [.init(component: .carbonDioxide, moleFraction: 1)],
            requestedProperties: [.density, .dynamicViscosity],
            clientVersion: "test"
        )
        let response = CalculationResponse(
            requestID: request.requestID,
            model: base.response.model,
            phase: .dense,
            properties: [
                PropertyValue(
                    property: .density,
                    value: density,
                    unit: "kg/m³",
                    status: density == nil ? .unavailable : .calculated
                ),
                PropertyValue(
                    property: .dynamicViscosity,
                    value: viscosityPascalSeconds,
                    unit: "Pa·s",
                    status: .calculated
                )
            ],
            solver: base.response.solver,
            warnings: [],
            isScientificResult: false
        )
        return CalculationRecord(
            request: request,
            input: CalculationInputSnapshot(
                pressureValue: pressureBar,
                pressureUnit: .bara,
                pressurePa: request.pressurePa,
                temperatureValue: temperatureCelsius,
                temperatureUnit: .celsius,
                temperatureK: request.temperatureK,
                originalComposition: [
                    .init(component: .carbonDioxide, value: 100, unit: .molePercent)
                ]
            ),
            response: response,
            application: base.application
        )
    }

    @MainActor
    private func makeTemporaryDiagramArtifacts(
        in store: PhaseDiagramTemporaryExportStore,
        id: String
    ) throws -> PhaseDiagramExportArtifacts {
        try FileManager.default.createDirectory(
            at: store.directory,
            withIntermediateDirectories: true
        )
        let pdf = store.directory.appendingPathComponent(
            "PhaseXpert-Phase-Diagram-\(id).pdf"
        )
        let csv = store.directory.appendingPathComponent(
            "PhaseXpert-Phase-Diagram-\(id).csv"
        )
        try Data("pdf".utf8).write(to: pdf)
        try Data("csv".utf8).write(to: csv)
        return PhaseDiagramExportArtifacts(files: [pdf, csv])
    }

    @MainActor
    func testStreamMixingStartsWithTwoEditableStreams() {
        let viewModel = StreamMixingViewModel()

        XCTAssertEqual(viewModel.streams.count, 2)
        XCTAssertEqual(viewModel.streams[0].name, "Stream 1")
        XCTAssertEqual(viewModel.streams[1].name, "Stream 2")
        XCTAssertTrue(viewModel.canCalculate)
    }

    @MainActor
    func testStreamMixingAddsOnlyUpToSixStreams() {
        let viewModel = StreamMixingViewModel()

        XCTAssertNotNil(viewModel.addStream())
        XCTAssertNotNil(viewModel.addStream())
        XCTAssertNotNil(viewModel.addStream())
        XCTAssertNotNil(viewModel.addStream())
        XCTAssertEqual(viewModel.streams.count, 6)
        XCTAssertFalse(viewModel.canAddStream)
        XCTAssertNil(viewModel.addStream())
        XCTAssertEqual(viewModel.streams.count, 6)
    }

    @MainActor
    func testStreamMixingDuplicateUsesNewIdentifierAndCopiesValues() {
        let viewModel = StreamMixingViewModel()
        let source = viewModel.streams[0]

        let duplicateID = viewModel.duplicateStream(id: source.id)

        let duplicate = viewModel.streams.first { $0.id == duplicateID }
        XCTAssertNotNil(duplicateID)
        XCTAssertNotEqual(duplicate?.id, source.id)
        XCTAssertEqual(duplicate?.flowText, source.flowText)
        XCTAssertEqual(duplicate?.flowUnit, source.flowUnit)
        XCTAssertEqual(duplicate?.compositionBasis, source.compositionBasis)
        XCTAssertEqual(duplicate?.composition.map(\.component), source.composition.map(\.component))
        XCTAssertTrue(duplicate?.name.contains("copy") == true)
    }

    @MainActor
    func testStreamMixingRemoveEnforcesTwoStreamMinimum() {
        let viewModel = StreamMixingViewModel()
        _ = viewModel.addStream()
        let removableID = viewModel.streams[2].id

        viewModel.removeStream(id: removableID)
        viewModel.removeStream(id: viewModel.streams[0].id)

        XCTAssertEqual(viewModel.streams.count, 2)
        XCTAssertFalse(viewModel.canRemoveStream)
    }

    @MainActor
    func testStreamMixingReorderPreservesNumericalResult() {
        let viewModel = StreamMixingViewModel()
        viewModel.calculate()
        let first = viewModel.result

        viewModel.moveStreams(from: IndexSet(integer: 0), to: 2)
        viewModel.calculate()
        let second = viewModel.result

        XCTAssertEqual(first?.totalMolarFlowMolesPerSecond, second?.totalMolarFlowMolesPerSecond)
        XCTAssertEqual(first?.totalMassFlowKilogramsPerSecond, second?.totalMassFlowKilogramsPerSecond)
        XCTAssertEqual(first?.composition, second?.composition)
        XCTAssertEqual(viewModel.streams[1].name, "Stream 1")
    }

    @MainActor
    func testStreamMixingFlowPressureAndTemperatureUnitsReachCoreRequest() throws {
        let viewModel = StreamMixingViewModel()
        viewModel.streams[0].flowText = "3600"
        viewModel.streams[0].flowUnit = .kilogramsPerHour
        viewModel.streams[0].pressureText = "12"
        viewModel.streams[0].pressureDisplayUnit = .megapascalAbsolute
        viewModel.streams[0].temperatureText = "68"
        viewModel.streams[0].temperatureDisplayUnit = .fahrenheit
        viewModel.outletPressureText = "1500"
        viewModel.outletPressureDisplayUnit = .psiAbsolute
        viewModel.outletTemperatureText = "298.15"
        viewModel.outletTemperatureDisplayUnit = .kelvin
        viewModel.markInputsChanged()

        let request = try XCTUnwrap(viewModel.request())

        XCTAssertEqual(request.streams[0].flowUnit, .kilogramsPerHour)
        XCTAssertEqual(request.streams[0].flowBasis, .mass)
        XCTAssertEqual(request.streams[0].pressureUnit, .megapascal)
        XCTAssertEqual(request.streams[0].temperatureUnit, .fahrenheit)
        XCTAssertEqual(request.outlet.pressureUnit, .psia)
        XCTAssertEqual(request.outlet.temperatureUnit, .kelvin)
    }

    @MainActor
    func testStreamMixingSuccessfulTwoStreamCalculationDisplaysHandCheckedTotals() {
        let viewModel = StreamMixingViewModel()

        viewModel.calculate()

        XCTAssertEqual(viewModel.result?.status, .calculated)
        XCTAssertEqual(viewModel.result?.totalMolarFlowMolesPerSecond ?? .nan, 15, accuracy: 1e-12)
        let carbonDioxide = viewModel.result?.composition.first {
            $0.component == .carbonDioxide
        }?.moleFraction
        let nitrogen = viewModel.result?.composition.first {
            $0.component == .nitrogen
        }?.moleFraction
        XCTAssertEqual(carbonDioxide ?? .nan, 14.5 / 15, accuracy: 1e-12)
        XCTAssertEqual(nitrogen ?? .nan, 0.5 / 15, accuracy: 1e-12)
    }

    @MainActor
    func testStreamMixingDifferentInletPressuresProduceOneWarning() {
        let viewModel = StreamMixingViewModel()
        viewModel.streams[0].pressureText = "120"
        viewModel.streams[1].pressureText = "150"
        viewModel.markInputsChanged()

        viewModel.calculate()

        XCTAssertEqual(viewModel.result?.warnings.count, 1)
        XCTAssertEqual(viewModel.result?.warnings.first?.code, .inletPressureDifference)
    }

    @MainActor
    func testStreamMixingValidationAndExplicitNormalization() {
        let viewModel = StreamMixingViewModel()
        viewModel.streams[0].composition = [
            CompositionInput(component: .carbonDioxide, value: "97.05"),
            CompositionInput(component: .nitrogen, value: "3")
        ]
        viewModel.markInputsChanged()

        viewModel.calculate()
        XCTAssertNil(viewModel.result)
        XCTAssertTrue(viewModel.validationReport.issues.contains {
            $0.code == .normalizationRequired
        })

        viewModel.applyExplicitNormalization(for: viewModel.streams[0].id)
        viewModel.calculate()

        XCTAssertEqual(viewModel.result?.status, .calculated)
        XCTAssertEqual(
            viewModel.result?.assumptions.filter {
                $0.code == .explicitCompositionNormalization
            }.count,
            1
        )
    }

    @MainActor
    func testStreamMixingMarksResultStaleAfterInputChange() {
        let viewModel = StreamMixingViewModel()

        viewModel.calculate()
        XCTAssertFalse(viewModel.isResultStale)

        viewModel.streams[0].flowText = "20"
        viewModel.markInputsChanged()

        XCTAssertTrue(viewModel.isResultStale)
        XCTAssertNotNil(viewModel.result)
    }

    @MainActor
    func testStreamMixingCalculatesWithoutProviderSelectionOrProviderCall() {
        let viewModel = StreamMixingViewModel()
        viewModel.calculate()

        XCTAssertEqual(viewModel.result?.status, .calculated)
        XCTAssertFalse(viewModel.statusMessage.localizedCaseInsensitiveContains("provider"))
        XCTAssertFalse(viewModel.statusMessage.localizedCaseInsensitiveContains("CoolProp"))
    }
}
