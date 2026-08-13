import Foundation

public enum TeqpFormulationFamily: String, Codable, Equatable, Sendable {
    case multifluid
    case multifluidActivity
    case gergResidual
    case eosCG2021
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
            .isobaricHeatCapacity,
            .isochoricHeatCapacity,
            .heatCapacityRatio,
            .molarMass,
            .compressibilityFactor,
            .specificVolume,
            .speedOfSound
        ],
        supportsPhaseEnvelope: true,
        provenance: "usnistgov/teqp v0.23.1 \(teqpCommit); CarbonDioxide.json BibTeX_EOS Span-JPCRD-1996.",
        limitations: [
            "Experimental local provider; no production accuracy claim.",
            "Only exactly 100 mol% CO₂ is production-enabled for teqp.",
            "Pure-CO₂ phase-envelope generation is enabled through teqp VLE saturation.",
            "Cv, Cp and speed of sound are calculated from complete ideal-gas plus residual Helmholtz derivatives.",
            "Absolute internal energy, enthalpy and entropy are not enabled until reference-state validation is complete."
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

    public static let co2OxygenGernertDiagnostic = TeqpFormulation(
        id: "teqp-v0.23.1-co2-o2-gernert-diagnostic",
        name: "CO₂+O₂ Gernert diagnostic model",
        family: .multifluid,
        status: .failedValidation,
        components: [.carbonDioxide, .oxygen],
        compositionLimits: [],
        supportedProperties: [],
        supportsPhaseEnvelope: false,
        provenance: "CarbonDioxide.json Span-JPCRD-1996; Oxygen.json Schmidt-FPE-1985,Stewart-JPCRD-1991; Gernert-Thesis-2013 reducing parameters with F=0 and no departure function.",
        limitations: [
            "Direct teqp density bake-off against Mantovani 2012 CO₂+O₂ PVT rows failed to establish a defensible user-facing domain.",
            "Retained only for formulation inventory and future model comparison."
        ],
        references: [
            SourceReference(
                authors: "Mantovani, Chiesa, Valenti, Gatti and Consonni",
                title: "Supercritical pressure-density-temperature measurements on CO₂-N₂, CO₂-O₂ and CO₂-Ar binary mixtures",
                year: 2012,
                doiOrURL: "https://doi.org/10.1016/j.supflu.2011.09.001"
            )
        ]
    )

    public static let co2ArgonGernertDiagnostic = TeqpFormulation(
        id: "teqp-v0.23.1-co2-ar-gernert-diagnostic",
        name: "CO₂+Ar Gernert/GERG diagnostic model",
        family: .multifluid,
        status: .failedValidation,
        components: [.carbonDioxide, .argon],
        compositionLimits: [],
        supportedProperties: [],
        supportsPhaseEnvelope: false,
        provenance: "CarbonDioxide.json Span-JPCRD-1996; Argon.json Tegeler-JPCRD-1999; Gernert-Thesis-2013 reducing parameters and Argon-CarbonDioxide GERG-2008 departure function.",
        limitations: [
            "Direct teqp density bake-off against Mantovani 2012 CO₂+Ar PVT rows showed low-argon density promise but failed at the broader audited composition and has no completed independent VLE gate.",
            "Retained only for formulation inventory and future model comparison."
        ],
        references: [
            SourceReference(
                authors: "Mantovani, Chiesa, Valenti, Gatti and Consonni",
                title: "Supercritical pressure-density-temperature measurements on CO₂-N₂, CO₂-O₂ and CO₂-Ar binary mixtures",
                year: 2012,
                doiOrURL: "https://doi.org/10.1016/j.supflu.2011.09.001"
            )
        ]
    )

    public static let co2OxygenEOSCGDiagnostic = TeqpFormulation(
        id: "teqp-v0.23.1-eoscg2021-co2-o2-diagnostic",
        name: "CO₂+O₂ EOS-CG-2021 diagnostic model",
        family: .eosCG2021,
        status: .failedValidation,
        components: [.carbonDioxide, .oxygen],
        compositionLimits: [],
        supportedProperties: [],
        supportsPhaseEnvelope: false,
        provenance: "EOS-CG-2021 Table 4 CO₂+O₂ reducing parameters, F=0 and no departure function; native construction confirmed through pinned teqp v0.23.1 custom multifluid model data.",
        limitations: [
            "Direct teqp density probe against Mantovani 2012 CO₂+O₂ PVT rows reproduced the existing failed density gate.",
            "Retained only for explicit model-comparison traceability; not exposed to users."
        ],
        references: [
            SourceReference(
                authors: "Neumann, Herrig, Bell, Beckmüller, Lemmon, Thol and Span",
                title: "EOS-CG-2021: A Mixture Model for the Calculation of Thermodynamic Properties of CCS Mixtures",
                year: 2023,
                doiOrURL: "https://doi.org/10.1007/s10765-023-03263-6"
            ),
            SourceReference(
                authors: "Mantovani, Chiesa, Valenti, Gatti and Consonni",
                title: "Supercritical pressure-density-temperature measurements on CO₂-N₂, CO₂-O₂ and CO₂-Ar binary mixtures",
                year: 2012,
                doiOrURL: "https://doi.org/10.1016/j.supflu.2011.09.001"
            )
        ]
    )

    public static let co2ArgonEOSCGDiagnostic = TeqpFormulation(
        id: "teqp-v0.23.1-eoscg2021-co2-ar-diagnostic",
        name: "CO₂+Ar EOS-CG-2021 diagnostic model",
        family: .eosCG2021,
        status: .failedValidation,
        components: [.carbonDioxide, .argon],
        compositionLimits: [],
        supportedProperties: [],
        supportsPhaseEnvelope: false,
        provenance: "EOS-CG-2021 Table 4 CO₂+Ar reducing parameters and Table 5 Løvseth et al. GERG-2008 departure function; native construction confirmed through pinned teqp v0.23.1 custom multifluid model data.",
        limitations: [
            "Direct teqp density probe against Mantovani 2012 CO₂+Ar PVT rows still failed the broad audited matrix.",
            "The 3.08 mol% Ar subset remains density-only diagnostic evidence because no audited independent VLE gate has passed.",
            "Retained only for explicit model-comparison traceability; not exposed to users."
        ],
        references: [
            SourceReference(
                authors: "Neumann, Herrig, Bell, Beckmüller, Lemmon, Thol and Span",
                title: "EOS-CG-2021: A Mixture Model for the Calculation of Thermodynamic Properties of CCS Mixtures",
                year: 2023,
                doiOrURL: "https://doi.org/10.1007/s10765-023-03263-6"
            ),
            SourceReference(
                authors: "Mantovani, Chiesa, Valenti, Gatti and Consonni",
                title: "Supercritical pressure-density-temperature measurements on CO₂-N₂, CO₂-O₂ and CO₂-Ar binary mixtures",
                year: 2012,
                doiOrURL: "https://doi.org/10.1016/j.supflu.2011.09.001"
            )
        ]
    )

    public static let co2HydrogenEOSCGDiagnostic = TeqpFormulation(
        id: "teqp-v0.23.1-eoscg2021-co2-h2-diagnostic",
        name: "CO₂+H₂ EOS-CG-2021 diagnostic model",
        family: .eosCG2021,
        status: .surveyPending,
        components: [.carbonDioxide, .hydrogen],
        compositionLimits: [],
        supportedProperties: [],
        supportsPhaseEnvelope: false,
        provenance: "EOS-CG-2021 Table 4 CO₂+H₂ reducing parameters and Table 5 Beckmüller et al. Gaussian+Exponential departure function; native construction confirmed through pinned teqp v0.23.1 custom multifluid model data.",
        limitations: [
            "No audited PhaseXpert primary-source PVT+VLE validation matrix is complete yet.",
            "EOS-CG-2021 reports known property-dependent limitations for CO₂+H₂ speed-of-sound data.",
            "Retained only for model-construction diagnostics; not exposed to users."
        ],
        references: [
            SourceReference(
                authors: "Neumann, Herrig, Bell, Beckmüller, Lemmon, Thol and Span",
                title: "EOS-CG-2021: A Mixture Model for the Calculation of Thermodynamic Properties of CCS Mixtures",
                year: 2023,
                doiOrURL: "https://doi.org/10.1007/s10765-023-03263-6"
            )
        ]
    )

    public static let co2MethaneEOSCGDiagnostic = TeqpFormulation(
        id: "teqp-v0.23.1-eoscg2021-co2-ch4-diagnostic",
        name: "CO₂+CH₄ EOS-CG-2021/GERG diagnostic model",
        family: .eosCG2021,
        status: .surveyPending,
        components: [.carbonDioxide, .methane],
        compositionLimits: [],
        supportedProperties: [],
        supportsPhaseEnvelope: false,
        provenance: "EOS-CG-2021 inherits the GERG-2008 CH₄+CO₂ binary formulation; reciprocal beta handling is required for CO₂+CH₄ order. Native construction confirmed through pinned teqp v0.23.1 custom multifluid model data.",
        limitations: [
            "No audited PhaseXpert primary-source CO₂-rich PVT+VLE validation matrix is complete yet.",
            "Retained only for model-construction diagnostics; not exposed to users."
        ],
        references: [
            SourceReference(
                authors: "Neumann, Herrig, Bell, Beckmüller, Lemmon, Thol and Span",
                title: "EOS-CG-2021: A Mixture Model for the Calculation of Thermodynamic Properties of CCS Mixtures",
                year: 2023,
                doiOrURL: "https://doi.org/10.1007/s10765-023-03263-6"
            ),
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
        [
            co2NitrogenGernertGergDiagnostic,
            co2OxygenGernertDiagnostic,
            co2ArgonGernertDiagnostic,
            co2OxygenEOSCGDiagnostic,
            co2ArgonEOSCGDiagnostic,
            co2HydrogenEOSCGDiagnostic,
            co2MethaneEOSCGDiagnostic
        ]
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
