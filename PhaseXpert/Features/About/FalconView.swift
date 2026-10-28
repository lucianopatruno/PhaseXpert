import SwiftUI

struct FalconView: View {
    /// The only network request in the app. It runs when the user asks for the photo.
    @State private var showsPhoto = false

    private let officialPage = URL(string: "https://ife.no/en/laboratory/falcon-co2-flow-loop/")!

    // Displayed remotely from IFE's official FALCON page so PhaseXpert does not
    // redistribute a copy of the photograph. Source: IFE, picture1.jpg.
    private let officialPhoto = URL(string: "https://ife.no/wp-content/uploads/2018/12/picture1.jpg")!

    @ViewBuilder
    private var photo: some View {
        if showsPhoto {
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
            .accessibilityLabel("FALCON inclined CO₂ flow-loop test section")
        } else {
            ZStack {
                Color.ifePrimary.opacity(0.12)
                VStack(spacing: IFESpacing.small) {
                    Button("Show photo from the IFE website", systemImage: "photo") {
                        showsPhoto = true
                    }
                    .buttonStyle(.ifeTonal)
                    Text("The photo is loaded from ife.no when you tap this button.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(IFESpacing.medium)
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: IFESpacing.large) {
                photo
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: IFESpacing.regular))

                Text("Photo: IFE official FALCON webpage")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: IFESpacing.small) {
                    Text("FALCON CO₂ flow loop")
                        .font(.title2.weight(.semibold))
                    Text("IFE's experimental facility for CO₂ transport and flow research.")
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

                Link(destination: officialPage) {
                    Label("Open the official FALCON website", systemImage: "safari")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Opens IFE's FALCON webpage in Safari.")
            }
            .padding(IFESpacing.large)
        }
        .ifeDottedBackground()
        .navigationTitle("FALCON")
        .navigationBarTitleDisplayMode(.inline)
    }
}
