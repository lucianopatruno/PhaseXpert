import SwiftData
import SwiftUI

@main
struct PhaseXpertApp: App {
    @AppStorage("prefersDarkAppearance") private var prefersDarkAppearance = false
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue
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
                .environment(\.locale, Locale(identifier: appLanguage))
        }
        .modelContainer(modelContainer)
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case norwegian = "nb"

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .english: "English"
        case .norwegian: "Norsk"
        }
    }
}
