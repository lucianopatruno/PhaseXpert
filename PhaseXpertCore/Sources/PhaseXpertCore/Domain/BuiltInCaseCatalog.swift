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
    public let defaultPressurePa: Double?
    public let defaultTemperatureK: Double?
    public let composition: [MixtureComponent]?
    public let sources: [BuiltInCaseSource]
    public let projectFacts: [String]
    public let modelingBasis: String
    public let assumptions: [String]
    public let limitations: [String]

    public init(
        id: String,
        name: String,
        shortDescription: String,
        defaultPressurePa: Double?,
        defaultTemperatureK: Double?,
        composition: [MixtureComponent]?,
        sources: [BuiltInCaseSource],
        projectFacts: [String] = [],
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
        self.projectFacts = projectFacts
        self.modelingBasis = modelingBasis
        self.assumptions = assumptions
        self.limitations = limitations
    }

    public var hasCalculationPreset: Bool {
        defaultPressurePa != nil && defaultTemperatureK != nil && composition?.isEmpty == false
    }

    public var label: String {
        hasCalculationPreset ? "Representative source-based case" : "Project information"
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
            projectFacts: [
                "Four ships planned for CO₂ transport.",
                "Transport distance is approximately 700 km for Norwegian projects.",
                "Liquefied CO₂ transport condition is approximately 15 barg and -26 °C.",
                "Onshore terminal in Øygarden includes buffer storage, pumps and heating.",
                "Phase 1 terminal capacity is approximately 1.5 million tonnes CO₂/year.",
                "Each storage tank is approximately 680 m³ and over 30 m tall.",
                "Offshore pipeline is approximately 110 km, 12 inch diameter, and sized for about 5 million tonnes CO₂/year."
            ],
            modelingBasis: "Supported thermodynamic impurities set at the published Northern Lights limits, with CO2 as balance. This is a specification-limit example, not an asserted operating or measured composition.",
            assumptions: [
                "Published specifications are limits or design conditions and do not define a continuously fixed project stream.",
                "Water, reactive trace compounds, metals and other components outside PhaseXpert's thermodynamic catalog are not modeled."
            ],
            limitations: [
                "Representative source-based case, not actual composition or measured composition.",
                "The published 15 barg and -26 °C transport condition is rounded; at the encoded 1.600 MPa(a) and 247.15 K, the pinned CoolProp dry-mixture model places this specification-limit composition just below the saturation boundary."
            ]
        ),
        BuiltInCase(
            id: "brevik-ccs-conditioned-export-example",
            name: "Heidelberg Materials – Brevik CCS conditioned export example",
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
            projectFacts: [
                "Heidelberg Materials – Brevik CCS captures approximately 400,000 tonnes CO₂/year.",
                "The capture plant uses post-combustion amine technology.",
                "The scope includes CO₂ cleaning, liquefaction and buffer storage.",
                "CO₂ is delivered to Northern Lights at quayside."
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
            id: "hafslund-celsio-oslo-ccs-project-information",
            name: "Hafslund Celsio – Oslo CCS",
            shortDescription: "Project information for the planned Klemetsrud waste-to-energy CO₂ capture chain; no public exact stream composition/P/T preset is encoded.",
            defaultPressurePa: nil,
            defaultTemperatureK: nil,
            composition: nil,
            sources: [
                source(
                    "CCS Norway chain summary for Hafslund Celsio – Oslo CCS",
                    "https://ccsnorway.com/full-scale-capture-transport-and-storage/",
                    "2026"
                ),
                source(
                    "Hafslund press release: Carbon capture in Oslo becomes a reality",
                    "https://kommunikasjon.ntb.no/pressemelding/18397537/carbon-capture-in-oslo-becomes-a-reality?lang=en&publisherId=17848223",
                    "2025-01-27"
                )
            ],
            projectFacts: [
                "Capture target is approximately 350,000 tonnes CO₂/year.",
                "The project uses amine capture technology.",
                "The chain includes CO₂ cleaning, liquefaction and four days of buffer storage.",
                "Captured CO₂ is delivered to Northern Lights at the quay in the port area of Oslo.",
                "Hafslund reports a CO₂ terminal at the Port of Oslo and planned operation in the third quarter of 2029."
            ],
            modelingBasis: "Information-only project entry. No public authoritative exact CO₂ composition, impurity composition or representative transport/loading P/T was found for a PhaseXpert thermodynamic preset.",
            assumptions: [
                "PhaseXpert does not infer a Celsio stream from Northern Lights or Brevik specifications.",
                "Project facts are separate from thermodynamic validation status."
            ],
            limitations: [
                "No calculation preset is provided because exact public composition and operating state were not identified."
            ]
        ),
        BuiltInCase(
            id: "ravenna-ccs-phase-1-project-information",
            name: "Ravenna CCS – Phase 1",
            shortDescription: "Project information for Italy's first offshore CO₂ storage project; no public exact conditioned-stream composition or operating P/T preset is encoded.",
            defaultPressurePa: nil,
            defaultTemperatureK: nil,
            composition: nil,
            sources: [
                source(
                    "Eni and Snam launch Ravenna CCS",
                    "https://www.eni.com/content/dam/enicom/documents/press-release/migrated/2024-en/09/pr-eni-snam-launch-first-carbon-capture-and-storage-project.pdf",
                    "2024-09-03"
                ),
                source(
                    "Ravenna CCS project overview",
                    "https://ravennaccs.com/en-IT/project",
                    nil
                )
            ],
            projectFacts: [
                "Phase 1 began CO₂ injection in September 2024.",
                "The initial capture capacity is approximately 25,000 tonnes CO₂/year from Eni's Casalborsetti natural-gas treatment plant.",
                "The reported capture efficiency exceeds 90%, with peaks up to 96%.",
                "The source gas contains less than 3% CO₂ at close to atmospheric pressure; this describes the capture inlet, not the conditioned transport stream.",
                "Captured CO₂ is transported through converted gas pipelines to the offshore Porto Corsini Mare Ovest field.",
                "CO₂ is injected into a depleted gas reservoir at approximately 3,000 m depth."
            ],
            modelingBasis: "Information-only project entry. The authoritative public sources reviewed do not publish an exact conditioned CO₂ composition or representative transport/injection pressure and temperature suitable for a PhaseXpert thermodynamic preset.",
            assumptions: [
                "Capture-inlet concentration and pressure are not treated as transport-stream operating conditions.",
                "PhaseXpert does not infer a Ravenna stream from other CCS project specifications.",
                "Project facts are separate from thermodynamic validation status."
            ],
            limitations: [
                "No calculation preset is provided because exact public conditioned-stream composition and operating state were not identified."
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
