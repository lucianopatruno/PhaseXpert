import SwiftUI

struct AboutView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: IFESpacing.large) {
                    Image("IFELogoEnglish")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 260)
                        .accessibilityLabel("IFE — Institute for Energy Technology")

                    VStack(alignment: .leading, spacing: IFESpacing.small) {
                        Text("PhaseXpert")
                            .font(.largeTitle.weight(.semibold))
                            .foregroundStyle(Color.ifeText)
                        Text("Developed by the IFE Flow Technology Department")
                            .font(.headline)
                    }

                    IFECard {
                        VStack(alignment: .leading, spacing: IFESpacing.small) {
                            Text("Purpose")
                                .font(.headline)
                            Text("PhaseXpert is being developed for traceable thermophysical and phase-property calculations for CO₂-rich mixtures.")
                        }
                    }

                    ScientificStatusBanner(
                        title: "Development build",
                        message: "No validated thermodynamic engine is included in this milestone. Do not use demonstration output for engineering, safety, commercial, or regulatory decisions."
                    )

                    IFECard {
                        VStack(alignment: .leading, spacing: IFESpacing.small) {
                            LabeledContent("Version", value: Bundle.main.releaseVersion)
                            LabeledContent("Minimum iOS", value: "18.0")
                            LabeledContent("Data handling", value: "On-device")
                        }
                    }

                    Text("© \(Date.now.formatted(.dateTime.year())) Institute for Energy Technology (IFE)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(IFESpacing.large)
            }
            .background(Color.ifeBackground)
            .navigationTitle("About")
        }
    }
}

