import PhaseXpertCore
import SwiftData
import XCTest
@testable import PhaseXpert

final class PhaseXpertTests: XCTestCase {
    private struct DelayedPhaseEnvelopeProvider: ThermodynamicModelProvider {
        let descriptor = ArchitectureDemoProvider().descriptor
        let delayNanoseconds: UInt64

        func calculate(_ request: CalculationRequest) async throws -> CalculationResponse {
            try await ArchitectureDemoProvider().calculate(request)
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
        XCTAssertEqual(
            registry.provider(id: "coolprop-heos")?.descriptor.availability,
            expectedDefaultCoolPropAvailability
        )
    }

    #if os(iOS) && canImport(PhaseXpertCoolPropBridge)
    func testNativeCoolPropThreeAndTenPercentNitrogenContinuationStopsAtPointCap() async throws {
        for nitrogenMoleFraction in [0.03, 0.10] {
            let result = try await NativeCoolPropEngine()
                .dryCarbonDioxideMixturePhaseEnvelope(
                    composition: [
                        .init(
                            component: .carbonDioxide,
                            moleFraction: 1 - nitrogenMoleFraction
                        ),
                        .init(
                            component: .nitrogen,
                            moleFraction: nitrogenMoleFraction
                        )
                    ]
                )

            XCTAssertLessThanOrEqual(result.points.count, 256)
            XCTAssertGreaterThanOrEqual(
                result.points.filter { $0.branch == .bubble }.count,
                2,
                "Missing bubble branch at \(nitrogenMoleFraction * 100) mol% N₂"
            )
            XCTAssertGreaterThanOrEqual(
                result.points.filter { $0.branch == .dew }.count,
                2,
                "Missing dew branch at \(nitrogenMoleFraction * 100) mol% N₂"
            )
            XCTAssertTrue(result.points.allSatisfy {
                $0.temperatureK.isFinite && $0.temperatureK > 0
                    && $0.pressurePa.isFinite && $0.pressurePa >= 80_000
            })
            XCTAssertTrue(result.solverMethod.contains("maximum 256"))
        }
    }
    #endif

    @MainActor
    func testPhaseDiagramStopsSpinningAndAcceptsLateProviderCompletion() async throws {
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
        XCTAssertTrue(viewModel.errorMessage?.contains("continues in the background") == true)

        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNotNil(viewModel.response)
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
        let provider = ArchitectureDemoProvider()
        let request = CalculationRequest(
            modelID: provider.descriptor.id,
            pressurePa: 15_000_000,
            temperatureK: 293.15,
            composition: [.init(component: .carbonDioxide, moleFraction: 1)],
            requestedProperties: [.density],
            clientVersion: "test"
        )
        let response = try await provider.calculate(request)
        return CalculationRecord(
            request: request,
            input: CalculationInputSnapshot(
                pressureValue: 150,
                pressureUnit: .bara,
                pressurePa: 15_000_000,
                temperatureValue: 20,
                temperatureUnit: .celsius,
                temperatureK: 293.15,
                originalComposition: [
                    .init(component: .carbonDioxide, value: 100, unit: .molePercent)
                ]
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
}
