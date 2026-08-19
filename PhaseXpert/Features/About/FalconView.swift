import SwiftUI

struct FalconView: View {
    private let officialPage = URL(string: "https://ife.no/en/laboratory/falcon-co2-flow-loop/")!

    // Displayed remotely from IFE's official FALCON page so PhaseXpert does not
    // redistribute a copy of the photograph. Source: IFE, picture1.jpg.
    private let officialPhoto = URL(string: "https://ife.no/wp-content/uploads/2018/12/picture1.jpg")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: IFESpacing.large) {
                AsyncImage(url: officialPhoto) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().scaledToFill()
                    case .empty:
                        ZStack {
                            Color.ifePrimary.opacity(0.12)
                            ProgressView()
                        }
                    case .failure:
                        ZStack {
                            Color.ifePrimary.opacity(0.12)
                            Label("Photo available on the IFE website", systemImage: "photo")
                                .foregroundStyle(.secondary)
                        }
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: IFESpacing.regular))
                .accessibilityLabel("FALCON inclined CO₂ flow-loop test section")

                Text("Photo: IFE official FALCON webpage")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: IFESpacing.small) {
                    Text("FALCON CO₂ flow loop")
                        .font(.title2.weight(.semibold))
                    Text("FALCON is IFE's CO₂ flow-assurance research infrastructure for transport by pipeline and well injection. It supports pure CO₂ and mixtures, phase-transition and multiphase-flow studies, instrumentation development, and validation of predictive models.")
                }

                IFECard {
                    VStack(alignment: .leading, spacing: IFESpacing.small) {
                        Label("Up to 150 bar(a)", systemImage: "gauge.with.dots.needle.67percent")
                        Label("−30 to +50 °C", systemImage: "thermometer.medium")
                        Label("44 mm internal diameter; 13 m test section", systemImage: "ruler")
                        Label("Inclination from −90° to +90°", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                        Label("CO₂ mixtures can include N₂, CH₄, H₂O and O₂", systemImage: "circle.grid.2x2")
                    }
                }

                Text("FALCON contributes to ECCSEL's European research-infrastructure network for carbon capture, utilisation and storage.")
                    .foregroundStyle(.secondary)

                Link(destination: officialPage) {
                    Label("Open the official FALCON website", systemImage: "safari")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Opens IFE's FALCON webpage in Safari.")
            }
            .padding(IFESpacing.large)
        }
        .background(Color.ifeBackground)
        .navigationTitle("FALCON")
        .navigationBarTitleDisplayMode(.inline)
    }
}
