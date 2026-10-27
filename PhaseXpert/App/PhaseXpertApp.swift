import SwiftData
import SwiftUI

@main
struct PhaseXpertApp: App {
    @AppStorage("prefersDarkAppearance") private var prefersDarkAppearance = false
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue
    private let modelContainer: ModelContainer
    /// Set when the persistent store could not be opened. The app then shows a
    /// recovery screen on a throwaway in-memory container, so the on-disk store
    /// is never modified or replaced and no user data is silently dropped.
    private let dataStoreFailure: String?
    @State private var showsLaunchSplash = true

    init() {
        TemporaryExportCleanup.removeOldExports()
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
            dataStoreFailure = nil
        } catch {
            do {
                modelContainer = try ModelContainer(
                    for: schema,
                    configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
                )
            } catch {
                fatalError("Unable to initialize any PhaseXpert data store: \(error)")
            }
            dataStoreFailure = String(describing: error)
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if let dataStoreFailure {
                    DataStoreRecoveryView(details: dataStoreFailure)
                } else {
                    RootView()
                        .opacity(showsLaunchSplash ? 0 : 1)
                        .allowsHitTesting(!showsLaunchSplash)
                }

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


private struct DataStoreRecoveryView: View {
    let details: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(Color.pxUnavailable)
                .accessibilityHidden(true)
            Text("Saved cases could not be opened")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("PhaseXpert could not open its data store, so it has not started. Your saved cases have not been changed or deleted. Restart the app; if the problem persists, update PhaseXpert or contact support before reinstalling, because reinstalling removes saved cases.")
                .multilineTextAlignment(.center)
            Text(details)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(6)
        }
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("data-store-recovery")
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
