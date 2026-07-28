import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Calculator", systemImage: "function") {
                CalculatorView()
            }

            Tab("Saved Cases", systemImage: "tray.full") {
                SavedCasesView()
            }

            Tab("Phase Diagram", systemImage: "chart.xyaxis.line") {
                PhaseDiagramView()
            }

            Tab("Models", systemImage: "books.vertical") {
                ModelInformationView()
            }

            Tab("About", systemImage: "info.circle") {
                AboutView()
            }
        }
        .accessibilityIdentifier("main-tab-view")
    }
}

#Preview {
    RootView()
}

