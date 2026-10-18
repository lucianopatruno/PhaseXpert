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
        IFEPage {
            IFEHeroCard(tint: .ifeLavender) {
                VStack(alignment: .leading, spacing: IFESpacing.regular) {
                    Image("IFELogoEnglish")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 240)
                        .ifeLogoPlate()
                        .accessibilityLabel("IFE — Institute for Energy Technology")
                    Text("PhaseXpert")
                        .font(IFETypography.screenTitle)
                        .foregroundStyle(Color.ifeText)
                    Text("Engineering thermodynamic calculations for CO₂ and CO₂-rich mixtures.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            IFEGroup("General Properties") {
                Text("Engineering property calculations for CO₂ and supported CO₂-rich mixtures.")
            }

            IFEGroup("ENCASE") {
                Image("ENCASELogo")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 190)
                    .padding(IFESpacing.small)
                    .background(
                        Color.white,
                        in: RoundedRectangle(cornerRadius: IFECornerRadius.field, style: .continuous)
                    )
                    .accessibilityLabel("ENCASE")
                Text("European Network of Research Infrastructures for CO₂ Transport and Injection (ENCASE). ENCASE has received funding from the European Union’s Horizon Europe Research and Innovation programme under grant agreement No 101094664.")
                    .font(.subheadline)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            IFEGroup("Validation") {
                Text(ValidationInformationView.summary)
            }

            IFEGroup("IFE Model") {
                LabeledContent("Status") {
                    Text("Under development")
                }
                .accessibilityIdentifier("ife-model-development-status")
            }
            IFENavigationRow(
                "About the IFE Model",
                systemImage: "atom",
                tint: .ifeCoral
            ) {
                IFEModelInformationView()
            }

            IFEGroup("References") {
                ForEach(Array(references.enumerated()), id: \.offset) { index, item in
                    if index > 0 {
                        Divider()
                    }
                    reference(item.title, url: item.url)
                }
            }

            IFEGroup("FALCON") {
                Text("IFE's experimental facility for CO₂ transport and flow research.")
            }
            IFENavigationRow(
                "FALCON CO₂ flow loop",
                systemImage: "point.3.connected.trianglepath.dotted",
                tint: .ifePrimary
            ) {
                FalconView()
            }

            IFEGroup("Contact") {
                Link(destination: contactURL) {
                    Label("Contact IFE Flow Department", systemImage: "envelope")
                }
                .buttonStyle(.ifeTonal)
                .accessibilityHint("Opens a new email with the subject PhaseXpert.")
            }

            IFEGroup("Application") {
                IFEInfoRow("Version", value: Text(verbatim: Bundle.main.releaseVersion))
                Divider()
                IFEInfoRow("Minimum iOS", value: Text(verbatim: "18.0"))
                Divider()
                IFEInfoRow("Data handling", value: Text("On-device"))
            }

            Text("© \(Date.now.formatted(.dateTime.year())) Institute for Energy Technology (IFE)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .navigationTitle("About")
    }

    private var references: [(title: String, url: String)] {
        [
            ("CoolProp: Open-source thermophysical property library", "https://doi.org/10.1021/ie4033999"),
            ("Span–Wagner CO₂ equation of state", "https://doi.org/10.1063/1.555991"),
            ("IAPWS-95 water formulation", "https://doi.org/10.1063/1.1461829"),
            ("CO₂-rich binary p-ρ-T measurements", "https://doi.org/10.1021/je300590v"),
            ("CO₂/O₂ density measurements", "https://doi.org/10.1021/acs.jced.0c00484"),
            ("EOS-CG-2021 CCS mixture model", "https://doi.org/10.1007/s10765-023-03263-6"),
            ("Spycher–Pruess–Ennis-King CO₂/H₂O model", "https://doi.org/10.1016/S0016-7037(03)00273-4")
        ]
    }

    private var contactURL: URL {
        IFEContactMailLink.url
    }

    private func reference(_ title: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(Color.ifeText)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: IFESpacing.small)
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(Color.ifeViolet)
            }
            .contentShape(Rectangle())
        }
    }
}

struct ValidationInformationView: View {
    static let summary: LocalizedStringKey = "PhaseXpert identifies properties and operating states supported by independent experimental evidence. Validation is property-specific and may only apply to defined compositions and temperature/pressure ranges. Where evidence exists, PhaseXpert shows the relevant formulation, experimental source and applicable range."

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
        IFEPage {
            IFEPageHeader(
                systemImage: "checkmark.shield",
                message: "Results are checked against experimental data wherever evidence exists.",
                tint: .ifeBlue
            )
            IFEGroup("Validation") {
                Text(Self.summary)
            }
            IFEGroup("Calculation") {
                Text("General Properties is used for calculations.")
                Divider()
                Text("Independent validation is evaluated for each property and state.")
            }
        }
        .navigationTitle("Validation")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct IFEModelInformationView: View {
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
        IFEPage {
            IFEPageHeader(
                systemImage: "atom",
                message: "IFE is developing its own thermodynamic model for CO₂ systems.",
                tint: .ifePeach
            )
            IFEGroup("IFE Model") {
                Text("The IFE Flow Technology department is developing a proprietary thermodynamic model for CO₂ and CO₂-rich systems. Model development is supported by experimental validation, including measurements performed in IFE's FALCON CO₂ facility.")
                Divider()
                LabeledContent("Status") {
                    Text("Under development")
                }
                .accessibilityIdentifier("ife-model-development-status")
            }
            IFENavigationRow(
                "FALCON CO₂ flow loop",
                systemImage: "point.3.connected.trianglepath.dotted",
                tint: .ifePrimary
            ) {
                FalconView()
            }
        }
        .navigationTitle("IFE Model")
        .navigationBarTitleDisplayMode(.inline)
    }
}

enum IFEContactMailLink {
    static let recipient = "luciano.patruno@ife.no"
    static let subject = "PhaseXpert"
    static let validationQuoteSubject = "PhaseXpert: Request for case validation"

    static var url: URL {
        url(subject: subject)
    }

    static func url(subject: String) -> URL {
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
