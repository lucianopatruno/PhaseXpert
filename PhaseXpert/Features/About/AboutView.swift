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
                Text("General Properties uses CoolProp to provide broad thermodynamic property coverage for engineering calculations across a wide range of CO₂-rich compositions and operating conditions.")
                Text("Its key question is: can this state be calculated? A successful General Properties calculation is useful engineering output, but it does not by itself mean PhaseXpert has independently validated every property at that state.")
                Text("CoolProp 8.0.0 HEOS provides pure-CO₂ properties and calculable CO₂-rich dry mixtures with N₂, CH₄, O₂, Ar, H₂, CO and H₂S. The General Properties capability matrix separates calculable states from independently validated property domains.")
                Text("Dry-mixture density, molar mass, specific volume and Z have limited-production validation only for the committed CO₂/CH₄, CO₂/O₂ and CO₂/H₂ density slices; other dry mixtures remain preliminary or validation pending.")
                Text("Binary CO₂/H₂O homogeneous-gas density, molar mass, specific volume and Z remain preliminary at xH₂O = 1–1000 ppm, 76.85–150 °C and 5–50 bar(a).")
                Text("Homogeneous wet-gas properties do not predict water equilibrium, dropout or aqueous chemistry. H₂O mixtures do not use the Phase Map, and mixture Cp/Cv, sound speed and transport properties remain unavailable.")
                    .foregroundStyle(.secondary)
            }

            Section("Advanced CCS Properties — teqp / EOS-CG") {
                Text("Advanced CCS Properties uses CCS-focused teqp models. PhaseXpert exposes production properties only where that specific property has been independently validated against experimental data within defined composition, temperature, pressure and, where relevant, phase-domain limits.")
                Text("Its key question is: is this specific property at this state independently validated? Advanced validation is property-specific: density may be validated while speed of sound is not, and speed of sound may be validated while density is not.")
                Text("A state may therefore be calculable with General Properties while being outside the validated range in Advanced CCS Properties. That is not necessarily a contradiction or calculation error; it means PhaseXpert does not currently have sufficient independent validation evidence to expose that Advanced property/state as validated production capability.")
                Text("teqp v0.23.1 evaluates Helmholtz-energy models locally. Pure CO₂ properties are available; binary CO₂+N₂, CO₂+H₂, CO₂+CH₄ and CO₂+O₂ density, plus CO₂+CH₄ VLE, are enabled only in their independently validated gates.")
                Text("Limited dry multicomponent density and density-derived M, v and Z are available at four exact Razmjoo compositions: CO₂/N₂/O₂/Ar 92.0/4.3/1.6/2.1 mol%, CO₂/CH₄/H₂ 95.0/3.3/1.7 mol%, CO₂/N₂/CH₄/H₂ 94.2/2.3/2.2/1.3 mol%, and CO₂/N₂/Ar/CH₄/H₂ 95.2/2.8/0.5/1.0/0.5 mol%. The operating guidance is the authoritative source for their measured T/P slices.")
                Text("A generic multicomponent phase-equilibrium solver is under research evaluation. CO₂+N₂+CH₄ bubble/dew comparisons, stability and TP flash are not production calculator capabilities; interior flash phase fractions are not independently validated. Phase maps, caloric, acoustic and transport properties remain unsupported. Unsupported requests never fall back to CoolProp, normalize compositions or drop components.")
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
        .ifeDottedBackground()
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
