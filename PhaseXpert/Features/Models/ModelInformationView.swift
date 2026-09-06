import PhaseXpertCore
import SwiftUI

struct ModelInformationView: View {
    private let descriptors = ProviderRegistry().userFacingDescriptors
    private let wrapsInNavigationStack: Bool
    private let modelID: String?

    init(wrapsInNavigationStack: Bool = true, modelID: String? = nil) {
        self.wrapsInNavigationStack = wrapsInNavigationStack
        self.modelID = modelID
    }

    var body: some View {
        if wrapsInNavigationStack {
            NavigationStack {
                content
            }
        } else {
            content
        }
    }

    private var content: some View {
        Group {
            if let modelID, let descriptor = descriptors.first(where: { $0.id == modelID }) {
                if descriptor.id == "ife-model" {
                    IFEModelInformationView(wrapsInNavigationStack: false)
                } else {
                    ModelDetailView(descriptor: descriptor)
                }
            } else {
                List(descriptors) { descriptor in
                    NavigationLink {
                        if descriptor.id == "ife-model" {
                            IFEModelInformationView(wrapsInNavigationStack: false)
                        } else {
                            ModelDetailView(descriptor: descriptor)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(descriptor.name)
                                .font(.headline)
                            Text(statusText(for: descriptor))
                                .font(.subheadline)
                                .foregroundStyle(statusColor(descriptor.availability))
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .ifeDottedBackground()
                .navigationTitle("Model Information")
            }
        }
    }

    private func statusColor(_ availability: ModelAvailability) -> Color {
        switch availability {
        case .available: .green
        case .preliminary: .ifePrimary
        case .unavailable: .secondary
        }
    }

    private func statusText(for descriptor: ModelDescriptor) -> String {
        descriptor.id == "ife-model" ? "Under development" : descriptor.availability.rawValue.capitalized
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
                Text(scientificBasis)
                LabeledContent("Equation or method", value: equationOrMethod)
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
                    Label(localizedLimitation(limitation), systemImage: "exclamationmark.triangle")
                }
            }

            if !descriptor.references.isEmpty {
                Section("References") {
                    ForEach(descriptor.references, id: \.title) { reference in
                        if
                            let address = reference.doiOrURL,
                            let url = URL(string: address)
                        {
                            Link(destination: url) {
                                referenceLabel(reference, address: address)
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
        .navigationTitle(descriptor.id == "coolprop-heos" ? String(localized: "General Properties") : descriptor.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var scientificBasis: String {
        guard descriptor.id == "coolprop-heos" else { return descriptor.scientificBasis }
        return String(localized: "CoolProp HEOS pure-fluid CO₂, restricted dry CO₂-rich mixtures, and a preliminary homogeneous CO₂-rich water-vapor route. The General Properties capability matrix separates calculable states from independently validated states.")
    }

    private var equationOrMethod: String {
        guard descriptor.id == "coolprop-heos" else { return descriptor.equationOrMethod }
        return String(localized: "CoolProp HEOS; pure-CO₂ properties use one AbstractState(P,T) update. Dry mixtures use shipped interaction entries through the HEOS/multifluid route. Preliminary CO₂/H₂O gas density uses the shipped Gernert CO₂/Water pair with an imposed gas phase, never the unsafe high-level mixture PT flash.")
    }

    private func localizedLimitation(_ limitation: String) -> String {
        guard descriptor.id == "coolprop-heos" else { return limitation }
        return switch limitation {
        case "Pure CO₂ supports density, viscosity, caloric properties, heat capacities, speed of sound, thermal conductivity, Joule-Thomson coefficient and explicitly derived engineering properties.":
            String(localized: "Pure CO₂ supports density, viscosity, caloric properties, heat capacities, speed of sound, thermal conductivity, Joule-Thomson coefficient and explicitly derived engineering properties.")
        case "Dry CO₂-rich mixtures may contain N₂, O₂, Ar, CH₄, H₂, CO and H₂S with total impurity in (0, 10] mol%; this product guardrail remains calculability scope, not a validated accuracy range.":
            String(localized: "Dry CO₂-rich mixtures may contain N₂, O₂, Ar, CH₄, H₂, CO and H₂S with total impurity in (0, 10] mol%; this product guardrail remains calculability scope, not a validated accuracy range.")
        case "Mixtures remain restricted to density, phase and three explicitly derived engineering properties; expanded pure-fluid properties are unavailable.":
            String(localized: "Mixtures remain restricted to density, phase and three explicitly derived engineering properties; expanded pure-fluid properties are unavailable.")
        case "Preliminary integration; no production accuracy claim.":
            String(localized: "Preliminary integration; no production accuracy claim.")
        case "Mixture viscosity, caloric, acoustic, conductivity and derivative properties are unavailable pending separate validation.":
            String(localized: "Mixture viscosity, caloric, acoustic, conductivity and derivative properties are unavailable pending separate validation.")
        case "Production phase diagrams are scoped to pure CO₂; multicomponent compositions are not routed to phase-envelope generation.":
            String(localized: "Production phase diagrams are scoped to pure CO₂; multicomponent compositions are not routed to phase-envelope generation.")
        case "H₂O homogeneous properties remain preliminary for binary CO₂/H₂O at xH₂O = 1–1000 ppm, 350–423.15 K and 0.5–5 MPa.":
            String(localized: "H₂O homogeneous properties remain preliminary for binary CO₂/H₂O at xH₂O = 1–1000 ppm, 350–423.15 K and 0.5–5 MPa.")
        case "Binary pure-water equilibrium is separately limited-production in explicit 30–80 °C / 0.4999–5.0055 MPa and 100 °C / 4.70–15.09 MPa regions; brine, wet multicomponent equilibrium and pH are unsupported.":
            String(localized: "Binary pure-water equilibrium is separately limited-production in explicit 30–80 °C / 0.4999–5.0055 MPa and 100 °C / 4.70–15.09 MPa regions; brine, wet multicomponent equilibrium and pH are unsupported.")
        default:
            limitation
        }
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
