import PhaseXpertCore
import SwiftData
import XCTest
@testable import PhaseXpert

final class PhaseXpertTests: XCTestCase {
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
        XCTAssertEqual(viewModel.composition.last?.molPercent, "")
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
