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

public enum TeqpPhaseDomain: String, Codable, Equatable, Sendable {
    case homogeneousGas
    case homogeneousLiquidOrDense
    case homogeneousSinglePhase
    case supercritical
    case phaseEquilibrium
    case pureFluid
}

public struct TeqpTemperaturePressureLimit: Codable, Equatable, Sendable {
    public let temperatureK: Double
    public let minimumTemperatureK: Double
    public let maximumTemperatureK: Double
    public let minimumPressurePa: Double
    public let maximumPressurePa: Double

    public init(
        temperatureK: Double,
        minimumTemperatureK: Double? = nil,
        maximumTemperatureK: Double? = nil,
        minimumPressurePa: Double,
        maximumPressurePa: Double
    ) {
        self.temperatureK = temperatureK
        self.minimumTemperatureK = minimumTemperatureK ?? temperatureK
        self.maximumTemperatureK = maximumTemperatureK ?? temperatureK
        self.minimumPressurePa = minimumPressurePa
        self.maximumPressurePa = maximumPressurePa
    }
}

public extension TeqpTemperaturePressureLimit {
    func containsTemperature(
        _ temperatureK: Double,
        nominalToleranceK: Double = 0
    ) -> Bool {
        (temperatureK >= minimumTemperatureK && temperatureK <= maximumTemperatureK)
            || abs(temperatureK - self.temperatureK) <= nominalToleranceK
    }

    func contains(
        temperatureK: Double,
        pressurePa: Double,
        nominalTemperatureToleranceK: Double = 0
    ) -> Bool {
        containsTemperature(temperatureK, nominalToleranceK: nominalTemperatureToleranceK)
            && pressurePa >= minimumPressurePa
            && pressurePa <= maximumPressurePa
    }
}

public struct TeqpPropertyCapability: Codable, Equatable, Sendable {
    public let property: PropertyID
    public let phaseDomain: TeqpPhaseDomain
    public let compositionLimits: [TeqpCompositionLimit]
    public let isothermPressureLimits: [TeqpTemperaturePressureLimit]
    public let validationArtifact: String
    public let validationSummary: String
    public let accuracySummary: String?
    public let notes: [String]

    public init(
        property: PropertyID,
        phaseDomain: TeqpPhaseDomain,
        compositionLimits: [TeqpCompositionLimit],
        isothermPressureLimits: [TeqpTemperaturePressureLimit],
        validationArtifact: String,
        validationSummary: String,
        accuracySummary: String? = nil,
        notes: [String]
    ) {
        self.property = property
        self.phaseDomain = phaseDomain
        self.compositionLimits = compositionLimits
        self.isothermPressureLimits = isothermPressureLimits
        self.validationArtifact = validationArtifact
        self.validationSummary = validationSummary
        self.accuracySummary = accuracySummary
        self.notes = notes
    }
}

public extension TeqpPropertyCapability {
    func isothermPressureLimit(
        for temperatureK: Double,
        nominalTemperatureToleranceK: Double = 0
    ) -> TeqpTemperaturePressureLimit? {
        isothermPressureLimits.first {
            $0.containsTemperature(
                temperatureK,
                nominalToleranceK: nominalTemperatureToleranceK
            )
        }
    }

    func contains(
        temperatureK: Double,
        pressurePa: Double,
        nominalTemperatureToleranceK: Double = 0
    ) -> Bool {
        isothermPressureLimits.contains {
            $0.contains(
                temperatureK: temperatureK,
                pressurePa: pressurePa,
                nominalTemperatureToleranceK: nominalTemperatureToleranceK
            )
        }
    }
}

public struct TeqpPhaseEquilibriumCapability: Codable, Equatable, Sendable {
    public let components: Set<ComponentID>
    public let phaseDomain: TeqpPhaseDomain
    public let compositionLimits: [TeqpCompositionLimit]
    public let isothermPressureLimits: [TeqpTemperaturePressureLimit]
    public let validationArtifact: String
    public let validationSummary: String
    public let accuracySummary: String
    public let supportsContinuousEnvelope: Bool
    public let supportsCriticalPoint: Bool
    public let notes: [String]

    public init(
        components: Set<ComponentID>,
        phaseDomain: TeqpPhaseDomain,
        compositionLimits: [TeqpCompositionLimit],
        isothermPressureLimits: [TeqpTemperaturePressureLimit],
        validationArtifact: String,
        validationSummary: String,
        accuracySummary: String,
        supportsContinuousEnvelope: Bool,
        supportsCriticalPoint: Bool,
        notes: [String]
    ) {
        self.components = components
        self.phaseDomain = phaseDomain
        self.compositionLimits = compositionLimits
        self.isothermPressureLimits = isothermPressureLimits
        self.validationArtifact = validationArtifact
        self.validationSummary = validationSummary
        self.accuracySummary = accuracySummary
        self.supportsContinuousEnvelope = supportsContinuousEnvelope
        self.supportsCriticalPoint = supportsCriticalPoint
        self.notes = notes
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
    public let propertyCapabilities: [TeqpPropertyCapability]
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
        propertyCapabilities: [TeqpPropertyCapability] = [],
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
        self.propertyCapabilities = propertyCapabilities
        self.supportsPhaseEnvelope = supportsPhaseEnvelope
        self.provenance = provenance
        self.limitations = limitations
        self.references = references
    }
}

public enum TeqpFormulationCatalog {
    public static let teqpVersion = "v0.23.1"
    public static let teqpCommit = "a68eb9cabf47af2c4aba0d272ac10fbca4c10eca"
    public static let co2OxygenNominalIsothermToleranceK = 0.05
    public static let multicomponentNominalIsothermToleranceK = 0.05

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

    public static let co2HydrogenEOSCGGasDensity = TeqpFormulation(
        id: "teqp-v0.23.1-eoscg2021-co2-h2-gas-density-souissi2017",
        name: "CO₂+H₂ EOS-CG-2021 homogeneous gas density",
        family: .eosCG2021,
        status: .productionEnabled,
        components: [.carbonDioxide, .hydrogen],
        compositionLimits: [
            TeqpCompositionLimit(
                component: .hydrogen,
                minimumMoleFraction: 0.05362,
                maximumMoleFraction: 0.05362
            )
        ],
        supportedProperties: [
            .density,
            .molarMass,
            .compressibilityFactor,
            .specificVolume
        ],
        propertyCapabilities: [
            TeqpPropertyCapability(
                property: .density,
                phaseDomain: .homogeneousGas,
                compositionLimits: [
                    TeqpCompositionLimit(
                        component: .hydrogen,
                        minimumMoleFraction: 0.05362,
                        maximumMoleFraction: 0.05362
                    )
                ],
                isothermPressureLimits: [
                    TeqpTemperaturePressureLimit(
                        temperatureK: 273.15,
                        minimumPressurePa: 513_520,
                        maximumPressurePa: 3_035_960
                    ),
                    TeqpTemperaturePressureLimit(
                        temperatureK: 293.15,
                        minimumPressurePa: 503_160,
                        maximumPressurePa: 4_984_890
                    ),
                    TeqpTemperaturePressureLimit(
                        temperatureK: 323.15,
                        minimumPressurePa: 549_210,
                        maximumPressurePa: 5_997_370
                    )
                ],
                validationArtifact: "Documentation/Validation/EOSCGDirectTeqpDensityProbeResults.json",
                validationSummary: "Souissi et al. 2017 NIST ThermoML gas-density validation, exact xH₂ = 0.05362.",
                accuracySummary: "19 points; AARD 0.189492%; worst relative deviation 0.370799%.",
                notes: [
                    "Validated only for homogeneous gas density at the exact Souissi et al. 2017 ThermoML H₂ mole fraction.",
                    "No interpolation between isotherms is claimed.",
                    "VLE, phase envelope, Cp, Cv, speed of sound, h, u, s and transport are unavailable for this mixture."
                ]
            )
        ],
        supportsPhaseEnvelope: false,
        provenance: "EOS-CG-2021 Table 4 CO₂+H₂ reducing parameters and Table 5 Beckmüller et al. Gaussian+Exponential departure function evaluated through teqp v0.23.1 \(teqpCommit); gas-density validation against Souissi et al. 2017 NIST ThermoML.",
        limitations: [
            "LIMITED PASS — homogeneous gas density only at xH₂ = 0.05362.",
            "Temperature must match one of the validated isotherms: 273.15 K, 293.15 K or 323.15 K.",
            "Pressure must remain inside the observed gas-pressure range for that isotherm.",
            "Phase equilibrium, phase envelope, heat capacities, speed of sound, reference-state properties and transport are unavailable.",
            "No CoolProp fallback is used."
        ],
        references: [
            SourceReference(
                authors: "Neumann, Herrig, Bell, Beckmüller, Lemmon, Thol and Span",
                title: "EOS-CG-2021: A Mixture Model for the Calculation of Thermodynamic Properties of CCS Mixtures",
                year: 2023,
                doiOrURL: "https://doi.org/10.1007/s10765-023-03263-6"
            ),
            SourceReference(
                authors: "Souissi, Thol, Herrig, Jäger and Span",
                title: "Vapor-Phase (p, rho, T, x) Behavior and Virial Coefficients for the Binary Mixture (0.05 Hydrogen + 0.95 Carbon Dioxide)",
                year: 2017,
                doiOrURL: "https://doi.org/10.1021/acs.jced.7b00213"
            )
        ]
    )

    public static let co2NitrogenGernertGasDensity = TeqpFormulation(
        id: "teqp-v0.23.1-co2-n2-gerg-gas-density-mazzoccoli2012",
        name: "CO₂+N₂ Gernert/GERG homogeneous gas density",
        family: .multifluid,
        status: .productionEnabled,
        components: [.carbonDioxide, .nitrogen],
        compositionLimits: [
            TeqpCompositionLimit(
                component: .nitrogen,
                minimumMoleFraction: 0.0127,
                maximumMoleFraction: 0.0127
            )
        ],
        supportedProperties: [
            .density,
            .molarMass,
            .compressibilityFactor,
            .specificVolume
        ],
        propertyCapabilities: [
            TeqpPropertyCapability(
                property: .density,
                phaseDomain: .homogeneousGas,
                compositionLimits: [
                    TeqpCompositionLimit(
                        component: .nitrogen,
                        minimumMoleFraction: 0.0127,
                        maximumMoleFraction: 0.0127
                    )
                ],
                isothermPressureLimits: [
                    TeqpTemperaturePressureLimit(
                        temperatureK: 283.15,
                        minimumPressurePa: 1_000_000,
                        maximumPressurePa: 4_500_000
                    )
                ],
                validationArtifact: "Documentation/Validation/AdvancedCCSTeqpIndependentValidation2026-08-20.json",
                validationSummary: "Mazzoccoli et al. 2012 ThermoML gas-density validation at exact xN₂ = 0.0127 and 283.15 K.",
                accuracySummary: "5/5 converged; AARD 0.599354%; bias +0.022493%; RMS 0.765116%; worst 1.442151%.",
                notes: [
                    "Validated only for the contiguous 283.15 K homogeneous gas pressure series at the exact Mazzoccoli et al. 2012 N₂ mole fraction.",
                    "The same dataset fails liquid/dense and broader temperature support, so no interpolation to other N₂ compositions or isotherms is claimed.",
                    "VLE, phase envelope, Cp, Cv, speed of sound, h, u, s and transport are unavailable for this mixture."
                ]
            )
        ],
        supportsPhaseEnvelope: false,
        provenance: "CarbonDioxide.json Span-JPCRD-1996; Nitrogen.json Span-JPCRD-2000; Gernert-Thesis-2013 reducing parameters and Kunz-JCED-2012 GERG-2008 departure function evaluated through teqp v0.23.1 \(teqpCommit).",
        limitations: [
            "LIMITED PASS — homogeneous gas density only at xN₂ = 0.0127.",
            "Temperature must be 283.15 K and pressure must remain between 1.0 MPa and 4.5 MPa.",
            "Liquid/dense density, phase equilibrium, phase envelope, heat capacities, speed of sound, reference-state properties and transport are unavailable.",
            "No CoolProp fallback is used."
        ],
        references: [
            SourceReference(
                authors: "Mazzoccoli, Bosio and Arato",
                title: "CO₂-rich binary p-rho-T measurements for CCS pipeline conditions",
                year: 2012,
                doiOrURL: "https://doi.org/10.1021/je300590v"
            ),
            SourceReference(
                authors: "Kunz and Wagner",
                title: "The GERG-2008 Wide-Range Equation of State for Natural Gases and Other Mixtures",
                year: 2012,
                doiOrURL: "https://doi.org/10.1021/je300655b"
            )
        ]
    )

    public static let co2MethaneEOSCGGasDensity = TeqpFormulation(
        id: "teqp-v0.23.1-eoscg2021-co2-ch4-gas-density-ghafri2016",
        name: "CO₂+CH₄ EOS-CG-2021 homogeneous gas density",
        family: .eosCG2021,
        status: .productionEnabled,
        components: [.carbonDioxide, .methane],
        compositionLimits: [
            TeqpCompositionLimit(
                component: .methane,
                minimumMoleFraction: 0.05,
                maximumMoleFraction: 0.05
            )
        ],
        supportedProperties: [
            .density,
            .molarMass,
            .compressibilityFactor,
            .specificVolume
        ],
        propertyCapabilities: [
            TeqpPropertyCapability(
                property: .density,
                phaseDomain: .homogeneousGas,
                compositionLimits: [
                    TeqpCompositionLimit(
                        component: .methane,
                        minimumMoleFraction: 0.05,
                        maximumMoleFraction: 0.05
                    )
                ],
                isothermPressureLimits: [
                    TeqpTemperaturePressureLimit(
                        temperatureK: 301.14,
                        minimumTemperatureK: 301.133,
                        maximumTemperatureK: 301.153,
                        minimumPressurePa: 1_990_460,
                        maximumPressurePa: 6_976_000
                    ),
                    TeqpTemperaturePressureLimit(
                        temperatureK: 308.15,
                        minimumTemperatureK: 308.137,
                        maximumTemperatureK: 308.177,
                        minimumPressurePa: 7_971_800,
                        maximumPressurePa: 9_967_260
                    ),
                    TeqpTemperaturePressureLimit(
                        temperatureK: 309.15,
                        minimumTemperatureK: 309.133,
                        maximumTemperatureK: 309.179,
                        minimumPressurePa: 7_971_980,
                        maximumPressurePa: 9_967_340
                    ),
                    TeqpTemperaturePressureLimit(
                        temperatureK: 310.15,
                        minimumTemperatureK: 310.135,
                        maximumTemperatureK: 310.183,
                        minimumPressurePa: 7_971_590,
                        maximumPressurePa: 9_969_370
                    ),
                    TeqpTemperaturePressureLimit(
                        temperatureK: 311.15,
                        minimumTemperatureK: 311.134,
                        maximumTemperatureK: 311.192,
                        minimumPressurePa: 7_972_680,
                        maximumPressurePa: 9_967_760
                    ),
                    TeqpTemperaturePressureLimit(
                        temperatureK: 312.15,
                        minimumTemperatureK: 312.131,
                        maximumTemperatureK: 312.193,
                        minimumPressurePa: 7_972_370,
                        maximumPressurePa: 9_967_680
                    ),
                    TeqpTemperaturePressureLimit(
                        temperatureK: 313.15,
                        minimumTemperatureK: 313.140,
                        maximumTemperatureK: 313.182,
                        minimumPressurePa: 7_973_280,
                        maximumPressurePa: 9_768_430
                    )
                ],
                validationArtifact: "Documentation/Validation/MethaneDensityDomainExpansion2026-08-15.json",
                validationSummary: "Ghafri et al. 2016 NIST ThermoML density validation, exact xCH₄ = 0.05.",
                accuracySummary: "65-point expanded production subset; AARD 1.1254775%; worst relative deviation 1.99333%.",
                notes: [
                    "Validated for homogeneous gas density in the Ghafri et al. 2016 ThermoML gas block.",
                    "Also validated for a high-temperature supercritical density slice at xCH₄ = 0.05 from 308.15 K through 313.15 K within the encoded isotherm pressure ranges.",
                    "The broader full 180-row Ghafri dataset converged but does not justify dense, liquid-like or near-critical production support.",
                    "VLE, phase envelope, Cp, Cv, speed of sound, h, u, s and transport are unavailable for this mixture."
                ]
            )
        ],
        supportsPhaseEnvelope: true,
        provenance: "EOS-CG-2021 inherited GERG CH₄+CO₂ reducing parameters and GERG-2008 departure function evaluated through teqp v0.23.1 \(teqpCommit); gas-density validation against Ghafri et al. 2016 NIST ThermoML after static Clapeyron EOS_CG identity audit.",
        limitations: [
            "LIMITED PASS — homogeneous gas density only at xCH₄ = 0.05.",
            "Temperature and pressure must remain inside one of the encoded Ghafri et al. 2016 validation slices: the 301.14 K gas block or the 308.15 K through 313.15 K high-temperature supercritical density slice.",
            "Dense, liquid-like and near-critical rows outside the high-temperature slice are diagnostic only and are not production-enabled.",
            "Phase equilibrium, phase envelope, heat capacities, speed of sound, reference-state properties and transport are unavailable.",
            "No CoolProp fallback is used."
        ],
        references: [
            SourceReference(
                authors: "Neumann, Herrig, Bell, Beckmüller, Lemmon, Thol and Span",
                title: "EOS-CG-2021: A Mixture Model for the Calculation of Thermodynamic Properties of CCS Mixtures",
                year: 2023,
                doiOrURL: "https://doi.org/10.1007/s10765-023-03263-6"
            ),
            SourceReference(
                authors: "Ghafri, Rowland, Hughes, May and others",
                title: "Accurate density measurements on a binary mixture (carbon dioxide + methane) at the vicinity of the critical point in the supercritical state by a single-sinker densimeter",
                year: 2016,
                doiOrURL: "https://doi.org/10.1016/j.fluid.2015.08.029"
            )
        ]
    )

    public static let co2OxygenEOSCGGasDensity = TeqpFormulation(
        id: "teqp-v0.23.1-eoscg2021-co2-o2-gas-density-lozano-martin2020",
        name: "CO₂+O₂ EOS-CG homogeneous gas density",
        family: .eosCG2021,
        status: .productionEnabled,
        components: [.carbonDioxide, .oxygen],
        compositionLimits: [
            TeqpCompositionLimit(
                component: .oxygen,
                minimumMoleFraction: 0.05032089,
                maximumMoleFraction: 0.05032089
            )
        ],
        supportedProperties: [.density, .molarMass, .compressibilityFactor, .specificVolume],
        propertyCapabilities: [
            TeqpPropertyCapability(
                property: .density,
                phaseDomain: .homogeneousGas,
                compositionLimits: [
                    TeqpCompositionLimit(
                        component: .oxygen,
                        minimumMoleFraction: 0.05032089,
                        maximumMoleFraction: 0.05032089
                    )
                ],
                isothermPressureLimits: [
                    TeqpTemperaturePressureLimit(temperatureK: 275, minimumTemperatureK: 275.001, maximumTemperatureK: 275.005, minimumPressurePa: 998_000, maximumPressurePa: 3_940_000),
                    TeqpTemperaturePressureLimit(temperatureK: 293.15, minimumTemperatureK: 293.094, maximumTemperatureK: 293.101, minimumPressurePa: 999_000, maximumPressurePa: 5_066_000),
                    TeqpTemperaturePressureLimit(temperatureK: 300, minimumTemperatureK: 299.945, maximumTemperatureK: 299.949, minimumPressurePa: 999_000, maximumPressurePa: 6_024_000),
                    TeqpTemperaturePressureLimit(temperatureK: 312.5, minimumTemperatureK: 312.472, maximumTemperatureK: 312.476, minimumPressurePa: 999_000, maximumPressurePa: 3_988_000),
                    TeqpTemperaturePressureLimit(temperatureK: 325, minimumTemperatureK: 324.952, maximumTemperatureK: 324.955, minimumPressurePa: 997_000, maximumPressurePa: 6_804_000),
                    TeqpTemperaturePressureLimit(temperatureK: 350, minimumTemperatureK: 349.937, maximumTemperatureK: 349.939, minimumPressurePa: 999_000, maximumPressurePa: 7_897_000),
                    TeqpTemperaturePressureLimit(temperatureK: 375, minimumTemperatureK: 374.920, maximumTemperatureK: 374.925, minimumPressurePa: 999_000, maximumPressurePa: 7_119_000)
                ],
                validationArtifact: "Documentation/Validation/LozanoMartin2020CO2O2Density.csv",
                validationSummary: "Lozano-Martín et al. 2020 single-sinker gas-density validation at exact normalized xO₂ = 0.05032089.",
                accuracySummary: "45/45 converged; AARD 0.079069%; bias +0.004184%; RMS 0.113610%; worst 0.393366%.",
                notes: [
                    "No composition interpolation or interpolation between measured isotherm temperature bands is claimed.",
                    "The lowest-density root is selected because the primary source explicitly identifies every encoded row as gaseous.",
                    "VLE, phase envelope, caloric, acoustic, reference-state and transport properties remain unavailable."
                ]
            )
        ],
        supportsPhaseEnvelope: false,
        provenance: "Gernert and Span EOS-CG-2016 CO₂+O₂ reducing parameters, inherited unchanged by EOS-CG-2021, evaluated through teqp v0.23.1 \(teqpCommit).",
        limitations: [
            "LIMITED PASS — homogeneous gas density only at exact xO₂ = 0.05032089.",
            "Temperature and pressure must remain inside one of the seven encoded experimental isotherm bands.",
            "No O₂ VLE or other thermodynamic property is production-enabled; no CoolProp fallback is used."
        ],
        references: [
            SourceReference(authors: "Lozano-Martín, Mondéjar and Segovia", title: "Accurate experimental (p, ρ, T) data of the (CO₂ + O₂) binary system for the development of models for CCS processes", year: 2020, doiOrURL: "https://doi.org/10.1016/j.jct.2020.106210"),
            SourceReference(authors: "Neumann, Herrig, Bell, Beckmüller, Lemmon, Thol and Span", title: "EOS-CG-2021: A Mixture Model for the Calculation of Thermodynamic Properties of CCS Mixtures", year: 2023, doiOrURL: "https://doi.org/10.1007/s10765-023-03263-6")
        ]
    )

    public static let co2MethaneEOSCGVLE = TeqpPhaseEquilibriumCapability(
        components: [.carbonDioxide, .methane],
        phaseDomain: .phaseEquilibrium,
        compositionLimits: [
            TeqpCompositionLimit(
                component: .methane,
                minimumMoleFraction: 0.05,
                maximumMoleFraction: 0.05
            )
        ],
        isothermPressureLimits: [
            TeqpTemperaturePressureLimit(
                temperatureK: 293.13,
                minimumPressurePa: 5_727_300,
                maximumPressurePa: 7_930_800
            ),
            TeqpTemperaturePressureLimit(
                temperatureK: 298.142,
                minimumPressurePa: 6_431_600,
                maximumPressurePa: 7_697_750
            )
        ],
        validationArtifact: "Documentation/Validation/MethaneVLEProductionGate2026-08-16.json",
        validationSummary: "Petropoulou et al. 2018 NIST ThermoML ordinary VLE rows, exact xCH₄ = 0.05; production envelope points between anchors are EOS-CG-2021 calculations inside the validated temperature bounds.",
        accuracySummary: "24 accepted rows; pressure AARD 0.608899%; worst pressure deviation 1.787018%; worst absolute yCH₄ deviation 0.026258.",
        supportsContinuousEnvelope: true,
        supportsCriticalPoint: false,
        notes: [
            "Production support includes calculated bubble/dew phase classification and a continuous envelope segment from 293.13 K to 298.142 K at exact xCH₄ = 0.05.",
            "Intermediate curve points are EOS-CG-2021 interpolation within the experimentally validated Petropoulou ordinary VLE temperature bounds; they are not direct experimental rows.",
            "The 303.15 K Petropoulou critical-region rows remain diagnostic only.",
            "No validated critical endpoint or arbitrary composition interpolation is exposed."
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

    public static let oxyCombIMulticomponentDensity = multicomponentDensityFormulation(
        id: "oxycomb-i",
        name: "OxyComb I CO₂+N₂+O₂+Ar EOS-CG-2021 density",
        composition: [
            (.carbonDioxide, 0.920), (.nitrogen, 0.043),
            (.oxygen, 0.016), (.argon, 0.021)
        ],
        limits: [
            .init(temperatureK: 312.35, minimumPressurePa: 1_952_000, maximumPressurePa: 6_951_000),
            .init(temperatureK: 312.60, minimumPressurePa: 7_049_000, maximumPressurePa: 11_002_000)
        ],
        metrics: "20/20 validation rows converged; AARD 0.584120%; bias -0.043177%; RMS 0.718944%; worst 1.702920%.",
        domain: "312.35 K at 1.952–6.951 MPa and 312.60 K at 7.049–11.002 MPa"
    )

    public static let preCombIMulticomponentDensity = multicomponentDensityFormulation(
        id: "precomb-i",
        name: "PreComb I CO₂+CH₄+H₂ EOS-CG-2021 gas density",
        composition: [
            (.carbonDioxide, 0.950), (.methane, 0.033), (.hydrogen, 0.017)
        ],
        limits: [
            .init(temperatureK: 313.00, minimumPressurePa: 1_995_000, maximumPressurePa: 7_000_000)
        ],
        metrics: "11/11 gas rows converged; AARD 0.347581%; bias +0.319395%; RMS 0.460806%; worst 0.925245%.",
        domain: "313.00 K at 1.995–7.000 MPa"
    )

    public static let preCombIIMulticomponentDensity = multicomponentDensityFormulation(
        id: "precomb-ii",
        name: "PreComb II CO₂+N₂+CH₄+H₂ EOS-CG-2021 density",
        composition: [
            (.carbonDioxide, 0.942), (.nitrogen, 0.023),
            (.methane, 0.022), (.hydrogen, 0.013)
        ],
        limits: [
            .init(temperatureK: 313.15, minimumPressurePa: 2_000_000, maximumPressurePa: 20_002_000)
        ],
        metrics: "37/37 validation rows converged; AARD 0.608688%; bias -0.508935%; RMS 0.695111%; worst 1.120183%.",
        domain: "313.15 K at 2.000–20.002 MPa"
    )

    public static let transportSpecMulticomponentDensity = multicomponentDensityFormulation(
        id: "transport-spec",
        name: "TransportSpec CO₂+N₂+Ar+CH₄+H₂ EOS-CG-2021 density",
        composition: [
            (.carbonDioxide, 0.952), (.nitrogen, 0.028), (.argon, 0.005),
            (.methane, 0.010), (.hydrogen, 0.005)
        ],
        limits: [
            .init(temperatureK: 293.15, minimumPressurePa: 1_998_000, maximumPressurePa: 5_499_000),
            .init(temperatureK: 293.15, minimumPressurePa: 8_501_000, maximumPressurePa: 22_000_000),
            .init(temperatureK: 313.15, minimumPressurePa: 1_996_000, maximumPressurePa: 22_000_000)
        ],
        metrics: "77/77 rows in the promoted 293.15 K and 313.15 K blocks converged; 293.15 K AARD 0.766256%, worst 1.105702%; 313.15 K AARD 0.261704%, worst 0.649013%.",
        domain: "293.15 K at 1.998–5.499 MPa or 8.501–22.000 MPa; 313.15 K at 1.996–22.000 MPa"
    )

    private static func multicomponentDensityFormulation(
        id: String,
        name: String,
        composition: [(ComponentID, Double)],
        limits: [TeqpTemperaturePressureLimit],
        metrics: String,
        domain: String
    ) -> TeqpFormulation {
        let compositionLimits = composition.map {
            TeqpCompositionLimit(
                component: $0.0,
                minimumMoleFraction: $0.1,
                maximumMoleFraction: $0.1
            )
        }
        return TeqpFormulation(
            id: "teqp-v0.23.1-eoscg2021-multicomponent-\(id)-density-razmjoo2026",
            name: name,
            family: .eosCG2021,
            status: .productionEnabled,
            components: Set(composition.map(\.0)),
            compositionLimits: compositionLimits,
            supportedProperties: [.density, .molarMass, .compressibilityFactor, .specificVolume],
            propertyCapabilities: [
                TeqpPropertyCapability(
                    property: .density,
                    phaseDomain: .homogeneousSinglePhase,
                    compositionLimits: compositionLimits,
                    isothermPressureLimits: limits,
                    validationArtifact: "Documentation/Validation/Razmjoo2026MulticomponentDensity.json",
                    validationSummary: "Razmjoo et al. 2026 gravimetric-mixture VTD validation at the exact published composition; no composition interpolation.",
                    accuracySummary: metrics,
                    notes: [
                        "LIMITED PASS — density and density-derived M, v and Z only at the exact published composition and measured isotherm/pressure blocks: \(domain).",
                        "VLE, phase maps, caloric, acoustic and transport properties remain unsupported.",
                        "No component is dropped, no composition is normalized and no fallback provider is used."
                    ]
                )
            ],
            supportsPhaseEnvelope: false,
            provenance: "EOS-CG-2021 evaluated through teqp v0.23.1 \(teqpCommit), independently checked against Razmjoo et al. 2026 CC BY 4.0 experimental rows from Zenodo 10.5281/zenodo.15846367.",
            limitations: [
                "LIMITED PASS — exact published composition only; no interpolation across composition.",
                "Temperature/pressure must remain in the measured blocks: \(domain).",
                "VLE, phase maps, Cp, Cv, speed of sound, h, u, s and transport are unavailable.",
                "No CoolProp fallback is used."
            ],
            references: [
                SourceReference(
                    authors: "Razmjoo, Signorini, Di Bona, Conversano and Gatti",
                    title: "New density data and equations of state assessment for multicomponent CO₂-rich mixtures relevant to CO₂ transport for CCS applications",
                    year: 2026,
                    doiOrURL: "https://doi.org/10.1016/j.fuel.2026.139184"
                ),
                SourceReference(
                    authors: "Razmjoo, Signorini, Di Bona, Conversano and Gatti",
                    title: "New density data for multicomponent CO₂-rich mixtures",
                    year: 2025,
                    doiOrURL: "https://doi.org/10.5281/zenodo.15846367"
                )
            ]
        )
    }

    public static let surveyedBinaryImpurities: Set<ComponentID> = [
        .nitrogen,
        .oxygen,
        .argon,
        .hydrogen,
        .methane
    ]

    public static var productionFormulations: [TeqpFormulation] {
        [
            pureCarbonDioxide,
            co2NitrogenGernertGasDensity,
            co2HydrogenEOSCGGasDensity,
            co2MethaneEOSCGGasDensity,
            co2OxygenEOSCGGasDensity,
            oxyCombIMulticomponentDensity,
            preCombIMulticomponentDensity,
            preCombIIMulticomponentDensity,
            transportSpecMulticomponentDensity
        ]
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
