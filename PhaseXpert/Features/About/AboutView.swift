import SwiftUI

struct AboutView: View {
    private let wrapsInNavigationStack: Bool

    init(wrapsInNavigationStack: Bool = true) {
        self.wrapsInNavigationStack = wrapsInNavigationStack
    }

    var body: some View {
        if wrapsInNavigationStack {
            NavigationStack { content }
        } else {
            content
        }
    }

    private var content: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: IFESpacing.regular) {
                    Image("IFELogoEnglish")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 240)
                        .accessibilityLabel("IFE — Institute for Energy Technology")
                    Text("PhaseXpert")
                        .font(.largeTitle.weight(.semibold))
                    Text("Developed by IFE")
                        .font(.headline)
                    Text("Flow Technology Department")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Traceable thermophysical and phase-property calculations for CO₂-rich mixtures, developed by IFE's Flow Technology Department.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, IFESpacing.small)
            }

            Section("General Properties — CoolProp") {
                Text("CoolProp 8.0.0 HEOS provides pure-CO₂ properties and calculable CO₂-rich dry mixtures with N₂, CH₄, O₂, Ar, H₂, CO and H₂S. The General Properties capability matrix separates calculable states from independently validated property domains.")
                Text("Dry-mixture density, molar mass, specific volume and Z are limited-production only for the committed CO₂/CH₄ xCH₄ = 0.05 Ghafri density slices, CO₂/O₂ xO₂ = 0.05032089 Lozano-Martín gas-density isotherms, and CO₂/H₂ xH₂ = 0.05362 Souissi gas-density isotherms. N₂, Ar, CO, H₂S and dry multicomponent states remain preliminary or validation pending.")
                Text("Binary CO₂/H₂O homogeneous-gas density, molar mass, specific volume and Z remain preliminary at xH₂O = 1–1000 ppm, 76.85–150 °C and 5–50 bar(a).")
                Text("Homogeneous wet-gas properties do not predict water equilibrium, dropout or aqueous chemistry. H₂O mixtures do not use the Phase Map, and mixture Cp/Cv, sound speed and transport properties remain unavailable.")
                    .foregroundStyle(.secondary)
            }

            Section("Advanced CCS Properties — teqp / EOS-CG") {
                Text("teqp v0.23.1 evaluates Helmholtz-energy models locally. Pure CO₂ properties are available; CO₂+H₂ and CO₂+CH₄ density, CO₂+CH₄ VLE, and CO₂+O₂ density are enabled only in their independently validated composition and T/P gates.")
                Text("The O₂ gate requires xO₂ = 0.05032089 and the seven Lozano-Martín isotherm bands. N₂ and ternary mixtures remain diagnostic; Ar, CO and H₂S are research-only; wet Advanced mixtures are diagnostic. Unsupported requests never fall back to CoolProp or drop components.")
                    .foregroundStyle(.secondary)
            }

            Section("CO₂/H₂O Water Equilibrium") {
                Text("The Spycher–Pruess–Ennis-King (2003) pure-water model reports equilibrium H₂O in the CO₂-rich phase, CO₂ in the water-rich phase, water saturation and margin, aqueous-phase expectation, and bounded water-dropout pressure/temperature where supported.")
                Text("Limited-production equilibrium domains are 30–80 °C at 4.999–50.055 bar(a), plus 100 °C at 47.0–150.9 bar(a). Dropout temperature is production-enabled only in the first region; dropout pressure remains preliminary. Validation uses Meyer–Harvey (2015) and Sánchez-Vicente–Trusler (2022) measurements.")
                Text("Brine, wet multicomponent equilibrium, pH and aqueous speciation remain unsupported or research-only.")
                    .foregroundStyle(.secondary)
            }

            Section("References") {
                reference("CoolProp: Open-source thermophysical property library", url: "https://doi.org/10.1021/ie4033999")
                reference("Span–Wagner CO₂ equation of state", url: "https://doi.org/10.1063/1.555991")
                reference("IAPWS-95 water formulation", url: "https://doi.org/10.1063/1.1461829")
                reference("CO₂-rich binary p-ρ-T measurements", url: "https://doi.org/10.1021/je300590v")
                reference("CO₂/O₂ density measurements", url: "https://doi.org/10.1021/acs.jced.0c00484")
                reference("EOS-CG-2021 CCS mixture model", url: "https://doi.org/10.1007/s10765-023-03263-6")
                reference("Spycher–Pruess–Ennis-King CO₂/H₂O model", url: "https://doi.org/10.1016/S0016-7037(03)00273-4")
            }

            Section("FALCON / IFE") {
                Text("The IFE logo is the bundled official English IFE SVG asset already present in PhaseXpert. The FALCON page links to IFE's official CO₂ flow-loop webpage and loads its photograph remotely from IFE rather than redistributing a copy.")
                    .foregroundStyle(.secondary)
                NavigationLink {
                    FalconView()
                } label: {
                    Label("FALCON CO₂ flow loop", systemImage: "point.3.connected.trianglepath.dotted")
                }
            }

            Section("Contact") {
                Link(destination: contactURL) {
                    Label("firmapost@ife.no", systemImage: "envelope")
                }
                .accessibilityHint("Opens a new email with the subject PhaseXpert.")
            }

            Section("Application") {
                LabeledContent("Version", value: Bundle.main.releaseVersion)
                LabeledContent("Minimum iOS", value: "18.0")
                LabeledContent("Data handling", value: "On-device")
            }

            Section {
                Text("© \(Date.now.formatted(.dateTime.year())) Institute for Energy Technology (IFE)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.ifeBackground)
        .navigationTitle("About")
    }

    private var contactURL: URL {
        IFEContactMailLink.url
    }

    private func reference(_ title: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

enum IFEContactMailLink {
    static let recipient = "firmapost@ife.no"
    static let subject = "PhaseXpert"

    static var url: URL {
        guard
            let encodedSubject = subject.addingPercentEncoding(
                withAllowedCharacters: mailtoQueryAllowedCharacters
            ),
            let url = URL(string: "mailto:\(recipient)?subject=\(encodedSubject)")
        else {
            preconditionFailure("PhaseXpert contact mail URL could not be constructed.")
        }
        return url
    }

    private static var mailtoQueryAllowedCharacters: CharacterSet {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?")
        return allowed
    }
}
