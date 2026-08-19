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
    var latestCalculationRecord: CalculationRecord?

    func editAndRerun(_ record: CalculationRecord) {
        pendingCalculationRecord = record
        selectedTab = .calculator
    }

    func openBuiltInCaseInCalculator(_ builtInCase: BuiltInCase) {
        pendingBuiltInCase = builtInCase
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
                        Label("General Properties / CoolProp", systemImage: "function")
                    }
                    .accessibilityIdentifier("more-general-model")

                    NavigationLink {
                        ModelInformationView(
                            wrapsInNavigationStack: false,
                            modelID: "teqp-pure-co2-experimental"
                        )
                    } label: {
                        Label("Advanced CCS / teqp / EOS-CG", systemImage: "atom")
                    }
                    .accessibilityIdentifier("more-advanced-model")

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
            .navigationTitle("More")
        }
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
