import Observation
import PhaseXpertCore
import SwiftUI

enum AppTab: Hashable {
    case calculator
    case streamMixing
    case savedCases
    case phaseDiagram
    case more
    case models
    case about
}

@MainActor
@Observable
final class AppNavigationState {
    var selectedTab: AppTab = .calculator
    var pendingCalculationRecord: CalculationRecord?
    var pendingBuiltInCase: BuiltInCase?
    var pendingValidatedCase: ValidatedStateOption?
    var pendingBatchCase: (input: BatchCaseInput, model: BatchCalculationModel)?
    var latestCalculationRecord: CalculationRecord?

    func editAndRerun(_ record: CalculationRecord) {
        pendingCalculationRecord = record
        selectedTab = .calculator
    }

    func openBuiltInCaseInCalculator(_ builtInCase: BuiltInCase) {
        pendingBuiltInCase = builtInCase
        selectedTab = .calculator
    }

    func openValidatedCaseInCalculator(_ validatedCase: ValidatedStateOption) {
        pendingValidatedCase = validatedCase
        selectedTab = .calculator
    }

    func openBatchCaseInCalculator(_ input: BatchCaseInput, model: BatchCalculationModel) {
        pendingBatchCase = (input, model)
        selectedTab = .calculator
    }

    func showPhaseDiagram(for record: CalculationRecord) {
        latestCalculationRecord = record
        selectedTab = .phaseDiagram
    }
}

struct RootView: View {
    @State private var navigationState = AppNavigationState()

    var body: some View {
        @Bindable var navigationState = navigationState

        TabView(selection: $navigationState.selectedTab) {
            Tab("Calculator", systemImage: "function", value: .calculator) {
                CalculatorView()
            }

            Tab("Phase Diagram", systemImage: "chart.xyaxis.line", value: .phaseDiagram) {
                PhaseDiagramView()
            }

            Tab("Saved Cases", systemImage: "tray.full", value: .savedCases) {
                SavedCasesView()
            }

            Tab("More", systemImage: "ellipsis", value: .more) {
                MoreView()
            }
        }
        .environment(navigationState)
        .accessibilityIdentifier("main-tab-view")
    }
}

private struct MoreView: View {
    @State private var state = MoreTabState()

    var body: some View {
        NavigationStack {
            List {
                Section("Settings") {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Language & Appearance", systemImage: "gearshape")
                    }
                    .accessibilityIdentifier("more-appearance")
                }

                Section("Tools") {
                    NavigationLink {
                        StreamMixingView(
                            viewModel: state.streamMixingViewModel,
                            wrapsInNavigationStack: false
                        )
                    } label: {
                        Label("Stream Mixing", systemImage: "arrow.triangle.merge")
                    }
                    .accessibilityIdentifier("more-stream-mixing")
                }

                Section("Models & Information") {
                    NavigationLink {
                        ModelInformationView(
                            wrapsInNavigationStack: false,
                            modelID: "coolprop-heos"
                        )
                    } label: {
                        Label("General Properties", systemImage: "function")
                    }
                    .accessibilityIdentifier("more-general-model")

                    NavigationLink {
                        ValidationInformationView(wrapsInNavigationStack: false)
                    } label: {
                        Label("Validation", systemImage: "checkmark.shield")
                    }
                    .accessibilityIdentifier("more-validation")

                    NavigationLink {
                        IFEModelInformationView(wrapsInNavigationStack: false)
                    } label: {
                        Label("IFE Model", systemImage: "atom")
                    }
                    .accessibilityIdentifier("more-ife-model")

                    NavigationLink {
                        AboutView(wrapsInNavigationStack: false)
                    } label: {
                        Label("About", systemImage: "info.circle")
                    }
                    .accessibilityIdentifier("more-about")
                }

                Section("Research Infrastructure") {
                    NavigationLink {
                        FalconView()
                    } label: {
                        Label("FALCON", systemImage: "building.2")
                    }
                    .accessibilityIdentifier("more-falcon")
                }
            }
            .scrollContentBackground(.hidden)
            .ifeDottedBackground()
            .navigationTitle("More")
        }
    }
}

private struct SettingsView: View {
    @AppStorage("prefersDarkAppearance") private var prefersDarkAppearance = false
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue

    var body: some View {
        Form {
            Section("Language") {
                Picker("Language", selection: $appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.label).tag(language.rawValue)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .accessibilityIdentifier("settings-language")
            }
            Section {
                Toggle(isOn: $prefersDarkAppearance) {
                    Label("Dark mode", systemImage: "moon.fill")
                }
                .tint(.ifePrimary)
                .accessibilityIdentifier("appearance-dark-mode")
            } header: {
                Text("Appearance")
            }
        }
        .scrollContentBackground(.hidden)
        .ifeDottedBackground()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

@MainActor
@Observable
final class MoreTabState {
    let streamMixingViewModel: StreamMixingViewModel

    init(streamMixingViewModel: StreamMixingViewModel = StreamMixingViewModel()) {
        self.streamMixingViewModel = streamMixingViewModel
    }
}

#Preview {
    RootView()
}
