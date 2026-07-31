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
}
