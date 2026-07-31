import Observation
import PhaseXpertCore
import SwiftUI

enum AppTab: Hashable {
    case calculator
    case savedCases
    case phaseDiagram
    case models
    case about
}

@MainActor
@Observable
final class AppNavigationState {
    var selectedTab: AppTab = .calculator
    var pendingCalculationRecord: CalculationRecord?
    var latestCalculationRecord: CalculationRecord?

    func editAndRerun(_ record: CalculationRecord) {
        pendingCalculationRecord = record
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

            Tab("Saved Cases", systemImage: "tray.full", value: .savedCases) {
                SavedCasesView()
            }

            Tab("Phase Diagram", systemImage: "chart.xyaxis.line", value: .phaseDiagram) {
                PhaseDiagramView()
            }

            Tab("Models", systemImage: "books.vertical", value: .models) {
                ModelInformationView()
            }

            Tab("About", systemImage: "info.circle", value: .about) {
                AboutView()
            }
        }
        .environment(navigationState)
        .accessibilityIdentifier("main-tab-view")
    }
}

#Preview {
    RootView()
}
