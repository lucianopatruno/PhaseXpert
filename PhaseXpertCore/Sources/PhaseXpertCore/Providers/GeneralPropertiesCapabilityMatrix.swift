import Foundation

public enum GeneralPropertiesValidationStatus: String, Codable, Equatable, Sendable {
    case validatedProduction
    case limitedProduction
    case preliminaryValidationPending
    case researchOnly
    case unsupported

    public var displayName: String {
        switch self {
        case .validatedProduction: "Validated / production"
        case .limitedProduction: "Limited production"
        case .preliminaryValidationPending: "Preliminary / validation pending"
        case .researchOnly: "Research-only"
        case .unsupported: "Unsupported"
        }
    }
}

public struct GeneralPropertiesReference: Codable, Equatable, Sendable {
    public let authors: String
    public let year: Int
    public let doi: String
    public let evidence: String

    public init(authors: String, year: Int, doi: String, evidence: String) {
        self.authors = authors
        self.year = year
        self.doi = doi
        self.evidence = evidence
    }
}

public struct GeneralPropertiesValidationMetric: Codable, Equatable, Sendable {
    public let propertyGroup: String
    public let assessedRowCount: Int
    public let convergedRowCount: Int
    public let aardPercent: Double?
    public let signedBiasPercent: Double?
    public let rmsRelativeDeviationPercent: Double?
    public let worstRelativeDeviationPercent: Double?
    public let note: String

    public init(
        propertyGroup: String,
        assessedRowCount: Int,
        convergedRowCount: Int,
        aardPercent: Double? = nil,
        signedBiasPercent: Double? = nil,
        rmsRelativeDeviationPercent: Double? = nil,
        worstRelativeDeviationPercent: Double? = nil,
        note: String
    ) {
        self.propertyGroup = propertyGroup
        self.assessedRowCount = assessedRowCount
        self.convergedRowCount = convergedRowCount
        self.aardPercent = aardPercent
        self.signedBiasPercent = signedBiasPercent
        self.rmsRelativeDeviationPercent = rmsRelativeDeviationPercent
        self.worstRelativeDeviationPercent = worstRelativeDeviationPercent
        self.note = note
    }
}

public struct GeneralPropertiesCapability: Codable, Equatable, Sendable {
    public let components: Set<ComponentID>
    public let properties: Set<PropertyID>
    public let status: GeneralPropertiesValidationStatus
    public let compositionDomain: String
    public let temperatureDomainK: ClosedRange<Double>?
    public let pressureDomainPa: ClosedRange<Double>?
    public let phaseDomain: String
    public let provenance: String
    public let references: [GeneralPropertiesReference]
    public let metrics: [GeneralPropertiesValidationMetric]

    public init(
        components: Set<ComponentID>,
        properties: Set<PropertyID>,
        status: GeneralPropertiesValidationStatus,
        compositionDomain: String,
        temperatureDomainK: ClosedRange<Double>? = nil,
        pressureDomainPa: ClosedRange<Double>? = nil,
        phaseDomain: String,
        provenance: String,
        references: [GeneralPropertiesReference],
        metrics: [GeneralPropertiesValidationMetric]
    ) {
        self.components = components
        self.properties = properties
        self.status = status
        self.compositionDomain = compositionDomain
        self.temperatureDomainK = temperatureDomainK
        self.pressureDomainPa = pressureDomainPa
        self.phaseDomain = phaseDomain
        self.provenance = provenance
        self.references = references
        self.metrics = metrics
    }
}

public struct GeneralPropertiesCapabilityDecision: Codable, Equatable, Sendable {
    public let status: GeneralPropertiesValidationStatus
    public let isCalculable: Bool
    public let isInsideValidatedDomain: Bool
    public let capability: GeneralPropertiesCapability?
    public let message: String
}

public enum GeneralPropertiesCapabilityMatrix {
    public static let auditedCoolPropVersion = "v8.0.0"
    public static let auditedCoolPropCommit = "ae81610e7d23efc57f9d051c8e70a4d66e87537f"

    public static let dryImpurityComponents: Set<ComponentID> = [
        .nitrogen, .methane, .oxygen, .argon, .hydrogen, .carbonMonoxide,
        .hydrogenSulfide
    ]

    public static let auditedComponents: [ComponentID] = [
        .carbonDioxide, .nitrogen, .methane, .oxygen, .argon, .hydrogen,
        .carbonMonoxide, .hydrogenSulfide, .water
    ]

    public static let dryMixtureCalculableProperties: Set<PropertyID> = [
        .density, .molarMass, .specificVolume, .compressibilityFactor
    ]

    public static let wetHomogeneousCalculableProperties: Set<PropertyID> = [
        .density, .molarMass, .specificVolume, .compressibilityFactor
    ]

    public static let allCapabilities: [GeneralPropertiesCapability] = [
        binary(.nitrogen, references: [
            .init(
                authors: "Mazzoccoli, Bosio and Arato",
                year: 2012,
                doi: "10.1021/je300590v",
                evidence: "CO2-rich binary p-rho-T measurements for CCS pipeline conditions"
            ),
            .init(
                authors: "Arai, Kaminishi and Saito",
                year: 1971,
                doi: "10.1252/jcej.4.113",
                evidence: "CO2+N2 phase-boundary PVTx measurements"
            )
        ], metricsNote: "Mazzoccoli 2012 CO2+N2 density rows in the current calculable range scored 64/64 converged with 22.422515% AARD and 1032.554248% worst deviation; no General Properties density gate is promoted."),
        GeneralPropertiesCapability(
            components: [.carbonDioxide, .methane],
            properties: dryMixtureCalculableProperties,
            status: .limitedProduction,
            compositionDomain: "xCH4 = 0.05 exactly; density is limited-production only for the Ghafri 2016 gas block and high-temperature supercritical slice",
            temperatureDomainK: 301.133...313.182,
            pressureDomainPa: 1_990_460...11_966_000,
            phaseDomain: "homogeneous gas at 301.133...301.153 K, plus homogeneous high-temperature supercritical density rows at 308.15...313.182 K; VLE remains separate",
            provenance: "CoolProp 8.0.0 HEOS/multifluid route evaluated against independent Ghafri 2016 ThermoML density rows; Liu 2017 CO2-rich expansion rows are outside the current 10 mol% calculability guardrail.",
            references: [
                .init(
                    authors: "Al Ghafri, Rowland, Hughes, May and coauthors",
                    year: 2016,
                    doi: "10.1016/j.fluid.2015.08.029",
                    evidence: "CO2+CH4 density at xCH4 = 0.05 near the critical region"
                ),
                .init(
                    authors: "Liu et al.",
                    year: 2017,
                    doi: "10.1016/j.jct.2016.11.009",
                    evidence: "CO2+CH4 density rows audited as outside current <=10 mol% impurity calculability for the CO2-rich slices"
                )
            ],
            metrics: [
                .init(
                    propertyGroup: "density / gas",
                    assessedRowCount: 6,
                    convergedRowCount: 6,
                    aardPercent: 0.204388,
                    signedBiasPercent: 0.204388,
                    rmsRelativeDeviationPercent: 0.244953,
                    worstRelativeDeviationPercent: 0.414904,
                    note: "Worst row: Ghafri block 1 row 6, 301.133 K, 6.976 MPa, experimental 227.803 kg/m3, CoolProp 228.748163 kg/m3."
                ),
                .init(
                    propertyGroup: "density / high-temperature supercritical",
                    assessedRowCount: 65,
                    convergedRowCount: 65,
                    aardPercent: 1.127350,
                    signedBiasPercent: 1.127350,
                    rmsRelativeDeviationPercent: 1.204793,
                    worstRelativeDeviationPercent: 1.995566,
                    note: "Worst row: Ghafri block 3 row 95, 308.166 K, 9.16895 MPa, experimental 464.65 kg/m3, CoolProp 473.922396 kg/m3."
                )
            ]
        ),
        GeneralPropertiesCapability(
            components: [.carbonDioxide, .oxygen],
            properties: dryMixtureCalculableProperties,
            status: .limitedProduction,
            compositionDomain: "xO2 = 0.05032089 exactly; density is limited-production only on the encoded Lozano-Martin gas isotherm bands",
            temperatureDomainK: 275.001...374.925,
            pressureDomainPa: 997_000...7_897_000,
            phaseDomain: "homogeneous gas density only; O2 VLE, dense liquid and interpolation to other oxygen compositions are not validated",
            provenance: "CoolProp 8.0.0 HEOS/multifluid route evaluated against Lozano-Martin 2020 primary gas-density rows; Mazzoccoli 2012 broader O2 rows remain diagnostic.",
            references: [
                .init(
                    authors: "Lozano-Martin, Mondejar and Segovia",
                    year: 2020,
                    doi: "10.1016/j.jct.2020.106210",
                    evidence: "CO2+O2 gas density at xO2 = 0.05032089"
                ),
                .init(
                    authors: "Ahamada, Valtz, Chabab, Blanco-Martin and Coquelet",
                    year: 2020,
                    doi: "10.1021/acs.jced.0c00484",
                    evidence: "CO2+O2 density rows for higher O2 compositions, outside the promoted low-O2 gate"
                )
            ],
            metrics: [
                .init(
                    propertyGroup: "density / gas",
                    assessedRowCount: 45,
                    convergedRowCount: 45,
                    aardPercent: 0.079176,
                    signedBiasPercent: 0.004750,
                    rmsRelativeDeviationPercent: 0.113558,
                    worstRelativeDeviationPercent: -0.392570,
                    note: "Worst row: Lozano-Martin csv row 1, 275.001 K, 3.94 MPa, experimental 109.732 kg/m3, CoolProp 109.301226 kg/m3."
                )
            ]
        ),
        binary(.argon, references: [
            .init(
                authors: "Lovseth et al.",
                year: 2018,
                doi: "10.1016/j.fluid.2018.03.006",
                evidence: "CO2+Ar VLE and density measurements for improved mixture modeling"
            ),
            .init(
                authors: "Mantovani et al.",
                year: 2012,
                doi: "10.1016/j.supflu.2011.09.001",
                evidence: "Supercritical p-rho-T measurements on CO2+Ar mixtures"
            ),
            .init(
                authors: "Mazzoccoli, Bosio and Arato",
                year: 2012,
                doi: "10.1021/je300590v",
                evidence: "CO2+Ar density rows in the current calculable impurity range"
            )
        ], metricsNote: "Mazzoccoli 2012 CO2+Ar density rows in the current calculable range scored 122/122 converged with 4.104151% AARD and 51.419473% worst deviation; no General Properties density gate is promoted."),
        GeneralPropertiesCapability(
            components: [.carbonDioxide, .hydrogen],
            properties: dryMixtureCalculableProperties,
            status: .limitedProduction,
            compositionDomain: "xH2 = 0.05362 exactly; density is limited-production only on the Souissi 2017 gas isotherms",
            temperatureDomainK: 273.15...323.15,
            pressureDomainPa: 503_160...5_997_370,
            phaseDomain: "homogeneous gas density only; H2 VLE, caloric, acoustic and transport properties are not validated",
            provenance: "CoolProp 8.0.0 HEOS/multifluid route evaluated against independent Souissi 2017 ThermoML gas-density rows.",
            references: [
                .init(
                    authors: "Souissi, Kleinrahm, Yang and Richter",
                    year: 2017,
                    doi: "10.1021/acs.jced.7b00213",
                    evidence: "CO2+H2 vapor-phase p-rho-T-x rows at xH2 = 0.05362"
                ),
                .init(
                    authors: "Cheng et al.",
                    year: 2019,
                    doi: "10.1021/acs.jced.8b01206",
                    evidence: "CO2+H2 density rows audited as H2-rich and outside current CO2-rich calculability"
                )
            ],
            metrics: [
                .init(
                    propertyGroup: "density / gas",
                    assessedRowCount: 19,
                    convergedRowCount: 19,
                    aardPercent: 0.097349,
                    signedBiasPercent: 0.093717,
                    rmsRelativeDeviationPercent: 0.149409,
                    worstRelativeDeviationPercent: 0.409137,
                    note: "Worst row: Souissi block 1 row 13, 323.15 K, 5.99737 MPa, experimental 121.561 kg/m3, CoolProp 122.058351 kg/m3."
                )
            ]
        ),
        binary(.carbonMonoxide, references: [
            .init(
                authors: "Chapoy et al.",
                year: 2020,
                doi: "10.1016/j.fluid.2020.112733",
                evidence: "CO2+CO VLE measurements"
            )
        ], metricsNote: "Only VLE evidence was identified during this milestone; density and other General Properties remain validation pending."),
        binary(.hydrogenSulfide, references: [
            .init(
                authors: "Kunz and Wagner",
                year: 2012,
                doi: "10.1021/je300655b",
                evidence: "GERG-2008 model provenance for natural-gas component coverage, not an independent PhaseXpert validation row set"
            )
        ], metricsNote: "No lawfully committed primary CO2+H2S row-level dataset is available in this repository."),
        GeneralPropertiesCapability(
            components: [.carbonDioxide, .water],
            properties: wetHomogeneousCalculableProperties,
            status: .preliminaryValidationPending,
            compositionDomain: "binary CO2 + H2O only; xH2O = 1e-6...0.001 mole fraction; CO2 is balance",
            temperatureDomainK: 350...423.15,
            pressureDomainPa: 500_000...5_000_000,
            phaseDomain: "imposed homogeneous gas only; not aqueous equilibrium",
            provenance: "CoolProp HEOS CO2/H2O homogeneous gas using the shipped Gernert CO2-Water pair; aqueous equilibrium is a separate provider path.",
            references: [
                .init(
                    authors: "Meyer and Harvey",
                    year: 2015,
                    doi: "10.1002/aic.14818",
                    evidence: "Dew-point data validate the separate water-equilibrium path, not homogeneous density"
                )
            ],
            metrics: [
                .init(
                    propertyGroup: "density and derived volumetric properties",
                    assessedRowCount: 0,
                    convergedRowCount: 0,
                    note: "No independent low-water homogeneous CO2-rich density rows are committed; existing gate remains preliminary."
                )
            ]
        )
    ]

    public static func decision(
        for composition: [MixtureComponent],
        property: PropertyID,
        pressurePa: Double,
        temperatureK: Double
    ) -> GeneralPropertiesCapabilityDecision {
        let active = composition.filter { $0.moleFraction.isFinite && $0.moleFraction > 0 }
        if active.count == 1, active.first?.component == .carbonDioxide {
            return .init(
                status: .preliminaryValidationPending,
                isCalculable: true,
                isInsideValidatedDomain: false,
                capability: nil,
                message: "Pure CO2 remains calculable; this milestone did not promote General Properties pure-fluid validation gates."
            )
        }
        guard let capability = allCapabilities.first(where: { $0.components == Set(active.map(\.component)) }) else {
            if isSupportedDryMulticomponent(active),
               dryMixtureCalculableProperties.contains(property) {
                return .init(
                    status: .preliminaryValidationPending,
                    isCalculable: true,
                    isInsideValidatedDomain: false,
                    capability: nil,
                    message: "Dry multicomponent \(property.rawValue) is preliminary / validation pending; no independent General Properties multicomponent density gate is committed."
                )
            }
            return .init(
                status: .unsupported,
                isCalculable: false,
                isInsideValidatedDomain: false,
                capability: nil,
                message: "No General Properties capability record exists for this active component set."
            )
        }
        let calculable = capability.properties.contains(property)
        let insideValidatedDomain = calculable
            && isInsideLimitedDensityDomain(
                active: active,
                property: property,
                pressurePa: pressurePa,
                temperatureK: temperatureK
            )
        let returnedStatus: GeneralPropertiesValidationStatus
        if !calculable {
            returnedStatus = .unsupported
        } else if insideValidatedDomain {
            returnedStatus = capability.status
        } else if capability.status == .limitedProduction {
            returnedStatus = .preliminaryValidationPending
        } else {
            returnedStatus = capability.status
        }
        return .init(
            status: returnedStatus,
            isCalculable: calculable,
            isInsideValidatedDomain: insideValidatedDomain,
            capability: capability,
            message: calculable
                ? "\(property.rawValue) is \(returnedStatus.displayName.lowercased()); \(capability.compositionDomain)."
                : "\(property.rawValue) is unavailable for this General Properties component set pending property-specific validation."
        )
    }

    public static func capabilitySummary(
        for composition: [MixtureComponent],
        pressurePa: Double,
        temperatureK: Double
    ) -> String {
        let decision = decision(
            for: composition,
            property: .density,
            pressurePa: pressurePa,
            temperatureK: temperatureK
        )
        return decision.message
    }

    private static func binary(
        _ impurity: ComponentID,
        references: [GeneralPropertiesReference],
        metricsNote: String
    ) -> GeneralPropertiesCapability {
        GeneralPropertiesCapability(
            components: [.carbonDioxide, impurity],
            properties: dryMixtureCalculableProperties,
            status: .preliminaryValidationPending,
            compositionDomain: "CO2-rich dry binary; total dry impurity currently calculable up to 10 mol% as a product guardrail, not a validation range",
            temperatureDomainK: nil,
            pressureDomainPa: nil,
            phaseDomain: "single-state CoolProp HEOS phase result; VLE and Phase Map are not validated by density calculability",
            provenance: "CoolProp 8.0.0 HEOS/multifluid route with pinned library interaction entries; no software-to-software comparison is treated as validation.",
            references: references,
            metrics: [
                .init(
                    propertyGroup: "density / volumetric",
                    assessedRowCount: 0,
                    convergedRowCount: 0,
                    note: metricsNote
                ),
                .init(
                    propertyGroup: "phase / VLE",
                    assessedRowCount: 0,
                    convergedRowCount: 0,
                    note: "No General Properties phase-equilibrium production gate is promoted."
                )
            ]
        )
    }

    private static func isInsideLimitedDensityDomain(
        active: [MixtureComponent],
        property: PropertyID,
        pressurePa: Double,
        temperatureK: Double
    ) -> Bool {
        guard densityDerivedProperties.contains(property),
              pressurePa.isFinite,
              temperatureK.isFinite else {
            return false
        }
        if let methane = moleFraction(of: .methane, in: active),
           approximatelyEqual(methane, 0.05, tolerance: 5e-7) {
            return (301.133...301.153).contains(temperatureK)
                && (1_990_460...6_976_000).contains(pressurePa)
                || (308.137...313.182).contains(temperatureK)
                && (7_971_800...11_966_000).contains(pressurePa)
        }
        if let oxygen = moleFraction(of: .oxygen, in: active),
           approximatelyEqual(oxygen, 0.05032089, tolerance: 5e-8) {
            return (275.001...374.925).contains(temperatureK)
                && (997_000...7_897_000).contains(pressurePa)
        }
        if let hydrogen = moleFraction(of: .hydrogen, in: active),
           approximatelyEqual(hydrogen, 0.05362, tolerance: 5e-7) {
            return isInsideIsothermBand(
                temperatureK: temperatureK,
                pressurePa: pressurePa,
                bands: [
                    (273.15, 513_520...3_035_960),
                    (293.15, 503_160...4_984_890),
                    (323.15, 549_210...5_997_370)
                ]
            )
        }
        return false
    }

    private static let densityDerivedProperties: Set<PropertyID> = [
        .density, .specificVolume, .compressibilityFactor, .molarMass
    ]

    private static func moleFraction(
        of component: ComponentID,
        in composition: [MixtureComponent]
    ) -> Double? {
        composition.first(where: { $0.component == component })?.moleFraction
    }

    private static func approximatelyEqual(
        _ lhs: Double,
        _ rhs: Double,
        tolerance: Double
    ) -> Bool {
        lhs.isFinite && abs(lhs - rhs) <= tolerance
    }

    private static func isInsideIsothermBand(
        temperatureK: Double,
        pressurePa: Double,
        bands: [(temperatureK: Double, pressurePa: ClosedRange<Double>)]
    ) -> Bool {
        bands.contains {
            approximatelyEqual(temperatureK, $0.temperatureK, tolerance: 0.01)
                && $0.pressurePa.contains(pressurePa)
        }
    }

    private static func isSupportedDryMulticomponent(
        _ composition: [MixtureComponent]
    ) -> Bool {
        composition.count > 2
            && composition.contains(where: { $0.component == .carbonDioxide })
            && composition.allSatisfy {
                $0.component == .carbonDioxide || dryImpurityComponents.contains($0.component)
            }
    }
}
