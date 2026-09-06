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
                    Text("Engineering thermodynamic calculations for CO₂ and CO₂-rich mixtures.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, IFESpacing.small)
            }

            Section("General Properties") {
                Text("Engineering property calculations for CO₂ and supported CO₂-rich mixtures.")
            }

            Section("ENCASE") {
                VStack(alignment: .leading, spacing: IFESpacing.regular) {
                    Image("ENCASELogo")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 190)
                        .accessibilityLabel("ENCASE")
                    Text("European Network of Research Infrastructures for CO₂ Transport and Injection (ENCASE). ENCASE has received funding from the European Union’s Horizon Europe Research and Innovation programme under grant agreement No 101094664.")
                        .font(.subheadline)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, IFESpacing.small)
                .listRowBackground(Color.white)
            }

            Section("Validation") {
                Text(ValidationInformationView.summary)
            }

            Section("IFE Model") {
                LabeledContent("Status") {
                    Text("Under development")
                }
                NavigationLink {
                    IFEModelInformationView()
                } label: {
                    Label("About the IFE Model", systemImage: "atom")
                }
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

            Section("FALCON") {
                Text("IFE's experimental facility for CO₂ transport and flow research.")
                NavigationLink {
                    FalconView()
                } label: {
                    Label("FALCON CO₂ flow loop", systemImage: "point.3.connected.trianglepath.dotted")
                }
            }

            Section("Contact") {
                Link(destination: contactURL) {
                    Label("Contact IFE Flow Department", systemImage: "envelope")
                }
                .accessibilityHint("Opens a new email with the subject PhaseXpert.")
            }

            Section("Application") {
                LabeledContent("Version", value: Bundle.main.releaseVersion)
                LabeledContent("Minimum iOS", value: "18.0")
                LabeledContent("Data handling") {
                    Text("On-device")
                }
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
        List {
            Section("Validation") {
                Text(Self.summary)
            }

            Section("Calculation") {
                Text("General Properties is used for calculations.")
                Text("Independent validation is evaluated for each property and state.")
            }
        }
        .navigationTitle("Validation")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .ifeDottedBackground()
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
        List {
            Section("IFE Model") {
                Text("The IFE Flow Technology department is developing a proprietary thermodynamic model for CO₂ and CO₂-rich systems. Model development is supported by experimental validation, including measurements performed in IFE's FALCON CO₂ facility.")
                LabeledContent("Status") {
                    Text("Under development")
                }
            }
            Section("FALCON") {
                NavigationLink {
                    FalconView()
                } label: {
                    Label("FALCON CO₂ flow loop", systemImage: "point.3.connected.trianglepath.dotted")
                }
            }
        }
        .navigationTitle("IFE Model")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .ifeDottedBackground()
    }
}

enum IFEContactMailLink {
    static let recipient = "luciano.patruno@ife.no"
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
