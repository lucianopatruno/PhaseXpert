import SwiftUI

struct PhaseDiagramView: View {
    var body: some View {
        NavigationStack {
            FeaturePlaceholder(
                title: "Phase Diagram",
                systemImage: "chart.xyaxis.line",
                message: "No curve is drawn until a validated provider generates a real phase envelope."
            )
        }
    }
}

