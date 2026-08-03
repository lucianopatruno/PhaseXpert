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
        case .preliminary: .ifePrimary
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
                    value: "\((descriptor.domain.minimumTemperatureK - 273.15).formatted())–\((descriptor.domain.maximumTemperatureK - 273.15).formatted()) °C"
                )
                LabeledContent(
                    "Pressure",
                    value: "\((descriptor.domain.minimumPressurePa / 100_000).formatted())–\((descriptor.domain.maximumPressurePa / 100_000).formatted()) bar(a)"
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
                        if let url = reference.destinationURL {
                            Link(destination: url) {
                                referenceLabel(
                                    reference,
                                    address: reference.doiOrURL
                                )
                            }
                            .accessibilityLabel(
                                "\(reference.authors), \(reference.title), open reference"
                            )
                            .accessibilityHint("Opens this reference in the browser.")
                        } else {
                            referenceLabel(reference, address: nil)
                        }
                    }
                }
            }
        }
        .navigationTitle(descriptor.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func referenceLabel(
        _ reference: SourceReference,
        address: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(reference.title)
                .font(.headline)
                .foregroundStyle(.primary)
            Text("\(reference.authors) (\(reference.year))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let address {
                Label(address, systemImage: "arrow.up.right.square")
                    .font(.caption)
                    .foregroundStyle(Color.ifePrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
