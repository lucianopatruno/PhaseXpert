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
            IFEPage {
                VStack(alignment: .leading, spacing: IFESpacing.small) {
                    IFESectionTitle("Tools")
                    IFENavigationRow(
                        "Stream Mixing",
                        subtitle: "Combine streams and compute the mixed composition",
                        systemImage: "arrow.triangle.merge",
                        tint: .ifeCoral
                    ) {
                        StreamMixingView(
                            viewModel: state.streamMixingViewModel,
                            wrapsInNavigationStack: false
                        )
                    }
                    .accessibilityIdentifier("more-stream-mixing")

                    IFENavigationRow(
                        "Impurity Reactions",
                        subtitle: "Preview: what reactive impurities could turn into",
                        systemImage: "testtube.2",
                        tint: .ifeGreen
                    ) {
                        ImpurityReactionsView(viewModel: state.impurityReactionsViewModel)
                    }
                    .accessibilityIdentifier("more-impurity-reactions")
                }

                VStack(alignment: .leading, spacing: IFESpacing.small) {
                    IFESectionTitle("Research Infrastructure")
                    IFENavigationRow(
                        "FALCON",
                        subtitle: "IFE's CO₂ flow research facility",
                        systemImage: "building.2",
                        tint: .ifePrimary
                    ) {
                        FalconView()
                    }
                    .accessibilityIdentifier("more-falcon")
                }

                VStack(alignment: .leading, spacing: IFESpacing.small) {
                    IFESectionTitle("Models & Information")
                    IFENavigationRow(
                        "General Properties",
                        subtitle: "Property coverage and model details",
                        systemImage: "function",
                        tint: .ifeViolet
                    ) {
                        ModelInformationView(
                            wrapsInNavigationStack: false,
                            modelID: "coolprop-heos"
                        )
                    }
                    .accessibilityIdentifier("more-general-model")

                    IFENavigationRow(
                        "IFE Model",
                        subtitle: "IFE's own model, under development",
                        systemImage: "atom",
                        tint: .ifeCoral
                    ) {
                        IFEModelInformationView(wrapsInNavigationStack: false)
                    }
                    .accessibilityIdentifier("more-ife-model")

                    IFENavigationRow(
                        "Validation",
                        subtitle: "How results are checked against experiments",
                        systemImage: "checkmark.shield",
                        tint: .ifeGreen
                    ) {
                        ValidationInformationView(wrapsInNavigationStack: false)
                    }
                    .accessibilityIdentifier("more-validation")
                }

                VStack(alignment: .leading, spacing: IFESpacing.small) {
                    IFESectionTitle("Settings & About")
                    IFENavigationRow(
                        "Language & Appearance",
                        subtitle: "Language, light and dark mode",
                        systemImage: "gearshape",
                        tint: .ifeViolet
                    ) {
                        SettingsView()
                    }
                    .accessibilityIdentifier("more-appearance")

                    IFENavigationRow(
                        "About",
                        subtitle: "Credits and contact",
                        systemImage: "info.circle",
                        tint: .ifeViolet
                    ) {
                        AboutView(wrapsInNavigationStack: false)
                    }
                    .accessibilityIdentifier("more-about")
                }
            }
            .navigationTitle("More")
        }
    }
}

private struct SettingsView: View {
    @AppStorage("prefersDarkAppearance") private var prefersDarkAppearance = false
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue

    var body: some View {
        IFEPage {
            IFEGroup("Language") {
                Picker("Language", selection: $appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.label).tag(language.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("settings-language")
            }

            IFEGroup("Appearance") {
                Toggle(isOn: $prefersDarkAppearance) {
                    Label("Dark mode", systemImage: "moon.fill")
                        .labelStyle(IFEIconLabelStyle(tint: .ifeViolet))
                }
                .tint(.ifePrimary)
                .accessibilityIdentifier("appearance-dark-mode")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

@MainActor
@Observable
final class MoreTabState {
    let streamMixingViewModel: StreamMixingViewModel
    let impurityReactionsViewModel: ImpurityReactionsViewModel

    init(
        streamMixingViewModel: StreamMixingViewModel = StreamMixingViewModel(),
        impurityReactionsViewModel: ImpurityReactionsViewModel = ImpurityReactionsViewModel()
    ) {
        self.streamMixingViewModel = streamMixingViewModel
        self.impurityReactionsViewModel = impurityReactionsViewModel
    }
}

#Preview {
    RootView()
}
