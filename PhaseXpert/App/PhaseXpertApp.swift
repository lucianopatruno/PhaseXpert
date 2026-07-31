import SwiftData
import SwiftUI

@main
struct PhaseXpertApp: App {
    @AppStorage("prefersDarkAppearance") private var prefersDarkAppearance = false
    private let modelContainer: ModelContainer

    init() {
        let schema = Schema(versionedSchema: PhaseXpertSchemaV1.self)
        let configuration = ModelConfiguration(
            "PhaseXpert",
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        do {
            modelContainer = try ModelContainer(
                for: schema,
                migrationPlan: PhaseXpertMigrationPlan.self,
                configurations: [configuration]
            )
        } catch {
            fatalError("Unable to initialize the PhaseXpert data store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(.ifePrimary)
                .preferredColorScheme(prefersDarkAppearance ? .dark : .light)
        }
        .modelContainer(modelContainer)
    }
}
