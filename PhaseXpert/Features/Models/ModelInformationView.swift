import PhaseXpertCore
import SwiftUI

struct ModelInformationView: View {
    private let descriptors = ProviderRegistry().descriptors

    var body: some View {
        NavigationStack {
            List(descriptors) { descriptor in
                NavigationLink {
                    ModelDetailView(descriptor: descriptor)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(descriptor.name)
                            .font(.headline)
                        Text(descriptor.availability.rawValue.capitalized)
                            .font(.subheadline)
                            .foregroundStyle(statusColor(descriptor.availability))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.ifeBackground)
            .navigationTitle("Model Information")
        }
    }

    private func statusColor(_ availability: ModelAvailability) -> Color {
        switch availability {
        case .available: .green
        case .preliminary: .ifeSignal
        case .unavailable: .secondary
        }
    }
}

private struct ModelDetailView: View {
    let descriptor: ModelDescriptor

    var body: some View {
        List {
            Section("Identity") {
                LabeledContent("Model version", value: descriptor.modelVersion)
                LabeledContent("Provider version", value: descriptor.providerVersion)
                LabeledContent("Mode", value: descriptor.calculationMode.rawValue.capitalized)
            }

            Section("Scientific basis") {
                Text(descriptor.scientificBasis)
                LabeledContent("Equation or method", value: descriptor.equationOrMethod)
                LabeledContent(
                    "Coefficient set",
                    value: descriptor.coefficientSetVersion ?? "Not applicable or not supplied"
                )
            }

            Section("Supported components") {
                if descriptor.supportedComponents.isEmpty {
                    Text("None declared")
                        .foregroundStyle(.secondary)
                } else {
                    Text(descriptor.supportedComponents.map(\.symbol).sorted().joined(separator: ", "))
                }
            }

            Section("Validity domain") {
                LabeledContent(
                    "Temperature",
                    value: "\(descriptor.domain.minimumTemperatureK.formatted())–\(descriptor.domain.maximumTemperatureK.formatted()) K"
                )
                LabeledContent(
                    "Pressure",
                    value: "\((descriptor.domain.minimumPressurePa / 1_000_000).formatted())–\((descriptor.domain.maximumPressurePa / 1_000_000).formatted()) MPa abs"
                )
            }

            Section("Limitations") {
                ForEach(descriptor.limitations, id: \.self) { limitation in
                    Label(limitation, systemImage: "exclamationmark.triangle")
                }
            }

            if !descriptor.references.isEmpty {
                Section("References") {
                    ForEach(descriptor.references, id: \.title) { reference in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(reference.title)
                                .font(.headline)
                            Text("\(reference.authors) (\(reference.year))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if let value = reference.doiOrURL {
                                Text(value)
                                    .font(.caption)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(descriptor.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
