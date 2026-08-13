import Foundation

public enum TeqpFormulationFamily: String, Codable, Equatable, Sendable {
    case multifluid
    case multifluidActivity
    case gergResidual
}

public enum TeqpValidationStatus: String, Codable, Equatable, Sendable {
    case productionEnabled
    case diagnosticOnly
    case failedValidation
    case surveyPending
}

public struct TeqpCompositionLimit: Codable, Equatable, Sendable {
    public let component: ComponentID
    public let minimumMoleFraction: Double
    public let maximumMoleFraction: Double

    public init(
        component: ComponentID,
        minimumMoleFraction: Double,
        maximumMoleFraction: Double
    ) {
        self.component = component
        self.minimumMoleFraction = minimumMoleFraction
        self.maximumMoleFraction = maximumMoleFraction
    }
}

public struct TeqpFormulation: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let family: TeqpFormulationFamily
    public let status: TeqpValidationStatus
    public let components: Set<ComponentID>
    public let compositionLimits: [TeqpCompositionLimit]
    public let supportedProperties: Set<PropertyID>
    public let supportsPhaseEnvelope: Bool
    public let provenance: String
    public let limitations: [String]
    public let references: [SourceReference]

    public init(
        id: String,
        name: String,
        family: TeqpFormulationFamily,
        status: TeqpValidationStatus,
        components: Set<ComponentID>,
        compositionLimits: [TeqpCompositionLimit],
        supportedProperties: Set<PropertyID>,
        supportsPhaseEnvelope: Bool,
        provenance: String,
        limitations: [String],
        references: [SourceReference]
    ) {
        self.id = id
        self.name = name
        self.family = family
        self.status = status
        self.components = components
        self.compositionLimits = compositionLimits
        self.supportedProperties = supportedProperties
        self.supportsPhaseEnvelope = supportsPhaseEnvelope
        self.provenance = provenance
        self.limitations = limitations
        self.references = references
    }
}

public enum TeqpFormulationCatalog {
    public static let teqpVersion = "v0.23.1"
    public static let teqpCommit = "a68eb9cabf47af2c4aba0d272ac10fbca4c10eca"

    public static let pureCarbonDioxide = TeqpFormulation(
        id: "teqp-v0.23.1-pure-co2-span-wagner-density",
        name: "Pure CO₂ Span-Wagner multifluid density",
        family: .multifluid,
        status: .productionEnabled,
        components: [.carbonDioxide],
        compositionLimits: [
            TeqpCompositionLimit(
                component: .carbonDioxide,
                minimumMoleFraction: 1,
                maximumMoleFraction: 1
            )
        ],
        supportedProperties: [
            .density,
            .molarMass,
            .compressibilityFactor,
            .specificVolume
        ],
        supportsPhaseEnvelope: false,
        provenance: "usnistgov/teqp v0.23.1 \(teqpCommit); CarbonDioxide.json BibTeX_EOS Span-JPCRD-1996.",
        limitations: [
            "Experimental local provider; no production accuracy claim.",
            "Only exactly 100 mol% CO₂ is production-enabled for teqp.",
            "Phase-envelope and expanded thermodynamic properties are not enabled for teqp."
        ],
        references: [
            SourceReference(
                authors: "Span and Wagner",
                title: "A New Equation of State for Carbon Dioxide Covering the Fluid Region from the Triple-Point Temperature to 1100 K at Pressures up to 800 MPa",
                year: 1996,
                doiOrURL: "https://doi.org/10.1063/1.555991"
            )
        ]
    )

    public static let co2NitrogenGernertGergDiagnostic = TeqpFormulation(
        id: "teqp-v0.23.1-co2-n2-gerg-diagnostic",
        name: "CO₂+N₂ Gernert/GERG diagnostic model",
        family: .multifluid,
        status: .failedValidation,
        components: [.carbonDioxide, .nitrogen],
        compositionLimits: [],
        supportedProperties: [],
        supportsPhaseEnvelope: false,
        provenance: "CarbonDioxide.json Span-JPCRD-1996; Nitrogen.json Span-JPCRD-2000; Gernert-Thesis-2013 reducing parameters; Kunz-JCED-2012 GERG-2008 departure function.",
        limitations: [
            "Gate C failed for user-facing CO₂+N₂ support with this pinned binary model.",
            "Retained only for native bridge diagnostics and future model comparison."
        ],
        references: [
            SourceReference(
                authors: "Kunz and Wagner",
                title: "The GERG-2008 Wide-Range Equation of State for Natural Gases and Other Mixtures",
                year: 2012,
                doiOrURL: "https://doi.org/10.1021/je300655b"
            )
        ]
    )

    public static let surveyedBinaryImpurities: Set<ComponentID> = [
        .nitrogen,
        .oxygen,
        .argon,
        .hydrogen,
        .methane
    ]

    public static var productionFormulations: [TeqpFormulation] {
        [pureCarbonDioxide]
    }

    public static var researchFormulations: [TeqpFormulation] {
        [co2NitrogenGernertGergDiagnostic]
    }

    public static var productionSupportedComponents: Set<ComponentID> {
        productionFormulations.reduce(into: []) { result, formulation in
            result.formUnion(formulation.components)
        }
    }

    public static var productionSupportedProperties: Set<PropertyID> {
        productionFormulations.reduce(into: []) { result, formulation in
            result.formUnion(formulation.supportedProperties)
        }
    }
}
