import SwiftData
import SwiftUI

@main
struct PhaseXpertApp: App {
    @AppStorage("prefersDarkAppearance") private var prefersDarkAppearance = false
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue
    private let modelContainer: ModelContainer
    @State private var showsLaunchSplash = true

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
            ZStack {
                RootView()
                    .opacity(showsLaunchSplash ? 0 : 1)
                    .allowsHitTesting(!showsLaunchSplash)

                if showsLaunchSplash {
                    LaunchSplashView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .tint(.ifePrimary)
            .preferredColorScheme(prefersDarkAppearance ? .dark : .light)
            .environment(\.locale, Locale(identifier: appLanguage))
            .task {
                guard showsLaunchSplash else { return }
                try? await Task.sleep(for: .milliseconds(850))
                withAnimation(.easeOut(duration: 0.25)) {
                    showsLaunchSplash = false
                }
            }
        }
        .modelContainer(modelContainer)
    }
}

private struct LaunchSplashView: View {
    var body: some View {
        VStack(spacing: 28) {
            Image("IFELogoEnglish")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 250)
                .accessibilityLabel("IFE — Institute for Energy Technology")

            Image("ENCASELogo")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 210)
                .accessibilityLabel("ENCASE")
        }
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.ignoresSafeArea())
        .accessibilityElement(children: .contain)
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
