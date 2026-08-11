import Foundation

public struct BuiltInCaseSource: Codable, Equatable, Sendable {
    public let title: String
    public let url: URL
    public let dateOrVersion: String?

    public init(title: String, url: URL, dateOrVersion: String?) {
        self.title = title
        self.url = url
        self.dateOrVersion = dateOrVersion
    }
}

public struct BuiltInCase: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let shortDescription: String
    public let defaultPressurePa: Double
    public let defaultTemperatureK: Double
    public let composition: [MixtureComponent]
    public let sources: [BuiltInCaseSource]
    public let modelingBasis: String
    public let assumptions: [String]
    public let limitations: [String]

    public init(
        id: String,
        name: String,
        shortDescription: String,
        defaultPressurePa: Double,
        defaultTemperatureK: Double,
        composition: [MixtureComponent],
        sources: [BuiltInCaseSource],
        modelingBasis: String,
        assumptions: [String],
        limitations: [String]
    ) {
        self.id = id
        self.name = name
        self.shortDescription = shortDescription
        self.defaultPressurePa = defaultPressurePa
        self.defaultTemperatureK = defaultTemperatureK
        self.composition = composition
        self.sources = sources
        self.modelingBasis = modelingBasis
        self.assumptions = assumptions
        self.limitations = limitations
    }

    public var label: String {
        "Representative source-based case"
    }
}

public enum BuiltInCaseCatalog {
    public static let cases: [BuiltInCase] = [
        BuiltInCase(
            id: "northern-lights-cargo-specification-example",
            name: "Northern Lights cargo specification example",
            shortDescription: "Supported thermodynamic impurities set at published Northern Lights limits, with CO2 as balance.",
            defaultPressurePa: 1_600_000,
            defaultTemperatureK: 247.15,
            composition: molPercent([
                (.carbonDioxide, 99.9831),
                (.carbonMonoxide, 0.0100),
                (.hydrogen, 0.0050),
                (.oxygen, 0.0010),
                (.hydrogenSulfide, 0.0009)
            ]),
            sources: [
                source(
                    "Northern Lights Project Concept Report, Table 3-5 and sections 3.2.2-3.2.3",
                    "https://norlights.com/wp-content/uploads/2021/03/Northern-Lights-Project-Concept-report.pdf",
                    "2021"
                ),
                source(
                    "CCS Norway transport conditions",
                    "https://ccsnorway.com/full-scale-capture-transport-and-storage/",
                    nil
                )
            ],
            modelingBasis: "Supported thermodynamic impurities set at the published Northern Lights limits, with CO2 as balance. This is a specification-limit example, not an asserted operating or measured composition.",
            assumptions: [
                "Published specifications are limits or design conditions and do not define a continuously fixed project stream.",
                "Water, reactive trace compounds, metals and other components outside PhaseXpert's thermodynamic catalog are not modeled."
            ],
            limitations: [
                "Representative source-based case, not actual composition or measured composition."
            ]
        ),
        BuiltInCase(
            id: "brevik-ccs-conditioned-export-example",
            name: "Brevik CCS conditioned export example",
            shortDescription: "Approximately 99 mol% CO2 representative conditioned product with N2 closure and supported trace limits.",
            defaultPressurePa: 1_600_000,
            defaultTemperatureK: 247.15,
            composition: molPercent([
                (.carbonDioxide, 99.0000),
                (.nitrogen, 0.9831),
                (.carbonMonoxide, 0.0100),
                (.hydrogen, 0.0050),
                (.oxygen, 0.0010),
                (.hydrogenSulfide, 0.0009)
            ]),
            sources: [
                source(
                    "Heidelberg Materials Sustainability-Linked Financing Framework V2",
                    "https://www.heidelbergmaterials.com/sites/default/files/2022-09/HeidelbergCement_SustainabilityLinkedFinancingFramework_V2_20220916.pdf",
                    "2022-09-16"
                ),
                source(
                    "CCS Norway Brevik delivery and liquid transport conditions",
                    "https://ccsnorway.com/full-scale-capture-transport-and-storage/",
                    nil
                )
            ],
            modelingBasis: "Approximately 99 mol% CO2 representative conditioned product, with the remaining modeled balance assigned to N2 and the supported Northern Lights trace limits retained.",
            assumptions: [
                "The N2 closure is an explicit PhaseXpert modeling assumption, not a published Brevik measurement.",
                "Published specifications are limits or design conditions and do not define a continuously fixed project stream."
            ],
            limitations: [
                "Representative source-based case, not actual composition or measured composition."
            ]
        ),
        BuiltInCase(
            id: "porthos-pipeline-specification-example",
            name: "Porthos pipeline specification example",
            shortDescription: "Constructed limit-compliant representative pipeline case within the published delivery envelope.",
            defaultPressurePa: 3_100_000,
            defaultTemperatureK: 293.15,
            composition: molPercent([
                (.carbonDioxide, 96.0000),
                (.nitrogen, 2.4000),
                (.methane, 1.0000),
                (.argon, 0.4000),
                (.hydrogen, 0.2000)
            ]),
            sources: [
                source(
                    "Porthos CO2 specifications",
                    "https://www.porthosco2.nl/wp-content/uploads/2021/09/CO2-specifications.pdf",
                    "2021-09"
                ),
                source(
                    "Porthos Standard CO2 Transport and Storage Conditions",
                    "https://www.porthosco2.nl/wp-content/uploads/2022/03/Porthos-standard-CO2-Transport-and-Storage-Conditions.pdf",
                    "2022-03"
                )
            ],
            modelingBasis: "A deliberately constructed, limit-compliant representative case. The modeled non-condensables total 4 mol%, CO2 remains above the published 95 mol% minimum, and each included impurity remains within its individual published maximum.",
            assumptions: [
                "This is not a customer-specific or measured Porthos stream.",
                "31 bar(a) and 20 °C are PhaseXpert defaults selected within the published delivery envelope, not claimed actual operating values.",
                "Published specifications are limits or design conditions and do not define a continuously fixed project stream."
            ],
            limitations: [
                "Representative source-based case, not actual composition or measured composition."
            ]
        ),
        BuiltInCase(
            id: "aramis-ship-specification-example",
            name: "Aramis ship specification example",
            shortDescription: "Constructed ship-specification example using the published aggregate inert limit.",
            defaultPressurePa: 1_600_000,
            defaultTemperatureK: 248.15,
            composition: molPercent([
                (.carbonDioxide, 99.8000),
                (.carbonMonoxide, 0.1200),
                (.hydrogen, 0.0500),
                (.nitrogen, 0.0290),
                (.oxygen, 0.0010)
            ]),
            sources: [
                source(
                    "Aramis CO2 specifications for transport infrastructure",
                    "https://www.aramis-ccs.com/news/co2-specifications-for-aramis-transport-infrastructure/",
                    nil
                )
            ],
            modelingBasis: "A constructed ship-specification example using the published 2,000 ppmmol aggregate inert limit. Published maxima are used for CO, H2 and O2, with N2 closing the aggregate and CO2 as balance.",
            assumptions: [
                "It is not a measured Aramis stream.",
                "16 bar(a) and -25 °C are PhaseXpert shipping defaults, not published fixed Aramis operating conditions.",
                "Published specifications are limits or design conditions and do not define a continuously fixed project stream."
            ],
            limitations: [
                "Representative source-based case, not actual composition or measured composition."
            ]
        )
    ]

    public static func caseWithID(_ id: String) -> BuiltInCase? {
        cases.first { $0.id == id }
    }

    private static func molPercent(_ values: [(ComponentID, Double)]) -> [MixtureComponent] {
        values.map { MixtureComponent(component: $0.0, moleFraction: $0.1 / 100) }
    }

    private static func source(
        _ title: String,
        _ url: String,
        _ dateOrVersion: String?
    ) -> BuiltInCaseSource {
        guard let sourceURL = URL(string: url) else {
            preconditionFailure("Built-in case source URL is invalid: \(url)")
        }
        return BuiltInCaseSource(title: title, url: sourceURL, dateOrVersion: dateOrVersion)
    }
}
