import Foundation

/// Expanded pure-fluid values returned from the native CoolProp state.
///
/// Values use SI units. Enthalpy, entropy, internal energy and the
/// Joule-Thomson coefficient are signed; the remaining values must be positive.
public struct CoolPropPureFluidProperties: Equatable, Sendable {
    public let enthalpyJoulesPerKilogram: Double
    public let entropyJoulesPerKilogramKelvin: Double
    public let internalEnergyJoulesPerKilogram: Double
    public let isobaricHeatCapacityJoulesPerKilogramKelvin: Double
    public let isochoricHeatCapacityJoulesPerKilogramKelvin: Double
    public let speedOfSoundMetresPerSecond: Double
    public let thermalConductivityWattsPerMetreKelvin: Double
    public let jouleThomsonKelvinPerPascal: Double

    public init(
        enthalpyJoulesPerKilogram: Double,
        entropyJoulesPerKilogramKelvin: Double,
        internalEnergyJoulesPerKilogram: Double,
        isobaricHeatCapacityJoulesPerKilogramKelvin: Double,
        isochoricHeatCapacityJoulesPerKilogramKelvin: Double,
        speedOfSoundMetresPerSecond: Double,
        thermalConductivityWattsPerMetreKelvin: Double,
        jouleThomsonKelvinPerPascal: Double
    ) {
        self.enthalpyJoulesPerKilogram = enthalpyJoulesPerKilogram
        self.entropyJoulesPerKilogramKelvin = entropyJoulesPerKilogramKelvin
        self.internalEnergyJoulesPerKilogram = internalEnergyJoulesPerKilogram
        self.isobaricHeatCapacityJoulesPerKilogramKelvin =
            isobaricHeatCapacityJoulesPerKilogramKelvin
        self.isochoricHeatCapacityJoulesPerKilogramKelvin =
            isochoricHeatCapacityJoulesPerKilogramKelvin
        self.speedOfSoundMetresPerSecond = speedOfSoundMetresPerSecond
        self.thermalConductivityWattsPerMetreKelvin =
            thermalConductivityWattsPerMetreKelvin
        self.jouleThomsonKelvinPerPascal = jouleThomsonKelvinPerPascal
    }
}

/// Raw values returned by a CoolProp bridge for one pure-CO₂ state point.
public struct CoolPropEngineResult: Equatable, Sendable {
    public let densityKilogramsPerCubicMetre: Double
    public let dynamicViscosityPascalSeconds: Double
    public let phaseIdentifier: String
    public let expandedProperties: CoolPropPureFluidProperties?

    public init(
        densityKilogramsPerCubicMetre: Double,
        dynamicViscosityPascalSeconds: Double,
        phaseIdentifier: String,
        expandedProperties: CoolPropPureFluidProperties? = nil
    ) {
        self.densityKilogramsPerCubicMetre = densityKilogramsPerCubicMetre
        self.dynamicViscosityPascalSeconds = dynamicViscosityPascalSeconds
        self.phaseIdentifier = phaseIdentifier
        self.expandedProperties = expandedProperties
    }
}

/// Raw values returned for the restricted CO₂-N₂ binary spike.
///
/// Dynamic viscosity is intentionally absent: it is not enabled until a
/// separate transport-property validation is completed.
public struct CoolPropBinaryEngineResult: Equatable, Sendable {
    public let densityKilogramsPerCubicMetre: Double
    public let densityMolesPerCubicMetre: Double?
    public let reducingDensityMolesPerCubicMetre: Double?
    public let gibbsMolarJoulesPerMole: Double?
    public let phaseIdentifier: String

    public init(
        densityKilogramsPerCubicMetre: Double,
        densityMolesPerCubicMetre: Double? = nil,
        reducingDensityMolesPerCubicMetre: Double? = nil,
        gibbsMolarJoulesPerMole: Double? = nil,
        phaseIdentifier: String
    ) {
        self.densityKilogramsPerCubicMetre = densityKilogramsPerCubicMetre
        self.densityMolesPerCubicMetre = densityMolesPerCubicMetre
        self.reducingDensityMolesPerCubicMetre = reducingDensityMolesPerCubicMetre
        self.gibbsMolarJoulesPerMole = gibbsMolarJoulesPerMole
        self.phaseIdentifier = phaseIdentifier
    }
}

public struct CoolPropPhaseEngineResult: Equatable, Sendable {
    public let phaseIdentifier: String

    public init(phaseIdentifier: String) {
        self.phaseIdentifier = phaseIdentifier
    }
}

public enum CoolPropSinglePhaseHint: Equatable, Sendable {
    case gas
    case liquid
}

public struct CoolPropMixtureSaturationPressures: Equatable, Sendable {
    public let bubblePressurePa: Double
    public let dewPressurePa: Double

    public init(bubblePressurePa: Double, dewPressurePa: Double) {
        self.bubblePressurePa = bubblePressurePa
        self.dewPressurePa = dewPressurePa
    }
}

/// Pure-fluid limits needed to sample the CO₂ saturation boundary safely.
public struct CoolPropSaturationLimits: Equatable, Sendable {
    public let triplePointTemperatureK: Double
    public let criticalPointTemperatureK: Double
    public let criticalPointPressurePa: Double

    public init(
        triplePointTemperatureK: Double,
        criticalPointTemperatureK: Double,
        criticalPointPressurePa: Double
    ) {
        self.triplePointTemperatureK = triplePointTemperatureK
        self.criticalPointTemperatureK = criticalPointTemperatureK
        self.criticalPointPressurePa = criticalPointPressurePa
    }
}

/// Provider-ready points returned verbatim by CoolProp's low-level phase-envelope routine.
public struct CoolPropMixtureEnvelopeResult: Equatable, Sendable {
    public let points: [PhaseEnvelopePoint]
    public let solverMethod: String
    public let isComplete: Bool
    public let isClosed: Bool

    public init(
        points: [PhaseEnvelopePoint],
        solverMethod: String,
        isComplete: Bool = true,
        isClosed: Bool = true
    ) {
        self.points = points
        self.solverMethod = solverMethod
        self.isComplete = isComplete
        self.isClosed = isClosed
    }
}

/// Narrow seam between the provider and a local CoolProp binary.
///
/// The protocol keeps C/C++ symbols out of the domain and presentation layers
/// and allows provider behavior to be tested without shipping fabricated data.
public protocol CoolPropEngine: Sendable {
    var isAvailable: Bool { get }
    var libraryVersion: String { get }

    func calculatePureCarbonDioxide(
        pressurePa: Double,
        temperatureK: Double
    ) async throws -> CoolPropEngineResult

    func calculateCarbonDioxideNitrogen(
        pressurePa: Double,
        temperatureK: Double,
        carbonDioxideMoleFraction: Double,
        nitrogenMoleFraction: Double
    ) async throws -> CoolPropBinaryEngineResult

    func calculateDryCarbonDioxideMixture(
        pressurePa: Double,
        temperatureK: Double,
        composition: [MixtureComponent]
    ) async throws -> CoolPropBinaryEngineResult

    func calculateCarbonDioxideWaterHomogeneousGas(
        pressurePa: Double,
        temperatureK: Double,
        carbonDioxideMoleFraction: Double,
        waterMoleFraction: Double
    ) async throws -> CoolPropBinaryEngineResult

    func calculateDryCarbonDioxideMixture(
        pressurePa: Double,
        temperatureK: Double,
        composition: [MixtureComponent],
        imposedPhase: CoolPropSinglePhaseHint
    ) async throws -> CoolPropBinaryEngineResult

    func identifyDryCarbonDioxideMixturePhase(
        pressurePa: Double,
        temperatureK: Double,
        composition: [MixtureComponent]
    ) async throws -> CoolPropPhaseEngineResult

    func dryCarbonDioxideMixtureSaturationPressures(
        temperatureK: Double,
        composition: [MixtureComponent]
    ) async throws -> CoolPropMixtureSaturationPressures

    func pureCarbonDioxideSaturationLimits() async throws -> CoolPropSaturationLimits

    func pureCarbonDioxideSaturationPressure(
        temperatureK: Double
    ) async throws -> Double

    func dryCarbonDioxideMixturePhaseEnvelope(
        composition: [MixtureComponent]
    ) async throws -> CoolPropMixtureEnvelopeResult
}

public extension CoolPropEngine {
    func calculateCarbonDioxideWaterHomogeneousGas(
        pressurePa: Double,
        temperatureK: Double,
        carbonDioxideMoleFraction: Double,
        waterMoleFraction: Double
    ) async throws -> CoolPropBinaryEngineResult {
        throw ProviderError.modelUnavailable(
            "The CoolProp engine does not expose the preliminary CO₂/H₂O homogeneous-gas bridge."
        )
    }

    func calculateDryCarbonDioxideMixture(
        pressurePa: Double,
        temperatureK: Double,
        composition: [MixtureComponent]
    ) async throws -> CoolPropBinaryEngineResult {
        let active = composition.filter {
            $0.moleFraction > 0
        }
        guard
            active.count == 2,
            let carbonDioxide = active.first(where: { $0.component == .carbonDioxide }),
            let nitrogen = active.first(where: { $0.component == .nitrogen })
        else {
            throw ProviderError.modelUnavailable(
                "The CoolProp engine does not expose the dry-mixture bridge."
            )
        }
        return try await calculateCarbonDioxideNitrogen(
            pressurePa: pressurePa,
            temperatureK: temperatureK,
            carbonDioxideMoleFraction: carbonDioxide.moleFraction,
            nitrogenMoleFraction: nitrogen.moleFraction
        )
    }

    func calculateCarbonDioxideNitrogen(
        pressurePa: Double,
        temperatureK: Double,
        carbonDioxideMoleFraction: Double,
        nitrogenMoleFraction: Double
    ) async throws -> CoolPropBinaryEngineResult {
        throw ProviderError.modelUnavailable(
            "The CoolProp engine does not expose the restricted CO₂-N₂ bridge."
        )
    }

    func calculateDryCarbonDioxideMixture(
        pressurePa: Double,
        temperatureK: Double,
        composition: [MixtureComponent],
        imposedPhase: CoolPropSinglePhaseHint
    ) async throws -> CoolPropBinaryEngineResult {
        throw ProviderError.modelUnavailable(
            "The CoolProp engine does not expose the phase-imposed dry-mixture bridge."
        )
    }

    func identifyDryCarbonDioxideMixturePhase(
        pressurePa: Double,
        temperatureK: Double,
        composition: [MixtureComponent]
    ) async throws -> CoolPropPhaseEngineResult {
        throw ProviderError.modelUnavailable(
            "The CoolProp engine does not expose the dry-mixture phase-classification bridge."
        )
    }

    func dryCarbonDioxideMixtureSaturationPressures(
        temperatureK: Double,
        composition: [MixtureComponent]
    ) async throws -> CoolPropMixtureSaturationPressures {
        throw ProviderError.modelUnavailable(
            "The CoolProp engine does not expose the dry-mixture saturation-pressure bridge."
        )
    }

    func dryCarbonDioxideMixturePhaseEnvelope(
        composition: [MixtureComponent]
    ) async throws -> CoolPropMixtureEnvelopeResult {
        throw ProviderError.modelUnavailable(
            "The CoolProp engine does not expose the dry-mixture phase-envelope bridge."
        )
    }
}

/// Used until the native XCFramework has been built and linked.
public struct UnavailableCoolPropEngine: CoolPropEngine {
    public let isAvailable = false
    public let libraryVersion = "Not linked"

    public init() {}

    public func calculatePureCarbonDioxide(
        pressurePa: Double,
        temperatureK: Double
    ) async throws -> CoolPropEngineResult {
        throw ProviderError.modelUnavailable(
            "The CoolProp native XCFramework has not been linked."
        )
    }

    public func pureCarbonDioxideSaturationLimits() async throws -> CoolPropSaturationLimits {
        throw ProviderError.modelUnavailable(
            "The CoolProp native XCFramework has not been linked."
        )
    }

    public func pureCarbonDioxideSaturationPressure(
        temperatureK: Double
    ) async throws -> Double {
        throw ProviderError.modelUnavailable(
            "The CoolProp native XCFramework has not been linked."
        )
    }
}

private actor PureCarbonDioxideEnvelopeCache {
    struct Entry: Sendable {
        let points: [PhaseEnvelopePoint]
        let warnings: [String]
        let generatedAt: Date
        let solver: SolverMetadata
    }

    private var entries: [String: Entry] = [:]

    func entry(for key: String) -> Entry? {
        entries[key]
    }

    func store(_ entry: Entry, for key: String) {
        entries[key] = entry
    }
}

/// Preliminary established-model provider for pure CO₂ and restricted dry CO₂-rich mixtures.
///
/// Availability does not imply scientific validation. Every successful result
/// carries an explicit validation-pending warning.
public struct CoolPropProvider<Engine: CoolPropEngine>: ThermodynamicModelProvider, PhaseMapProvidingModelProvider, PointPhaseScreeningModelProvider {
    private let engine: Engine
    private let envelopeCache: PureCarbonDioxideEnvelopeCache

    private static var saturationPointCount: Int { 81 }
    private static var maximumTotalImpurityMoleFraction: Double { 0.10 }
    private static var mixtureCompositionSumTolerance: Double { 1e-10 }
    private static var supportedDryComponents: Set<ComponentID> {
        [
            .carbonDioxide, .nitrogen, .oxygen, .argon, .methane, .hydrogen,
            .carbonMonoxide, .hydrogenSulfide
        ]
    }

    private enum SupportedComposition {
        case pureCarbonDioxide
        case dryMixture([MixtureComponent])
        case wetCarbonDioxideGas([MixtureComponent])
    }

    private struct ResolvedState {
        let densityKilogramsPerCubicMetre: Double
        let dynamicViscosityPascalSeconds: Double?
        let phaseIdentifier: String
        let isPureCarbonDioxide: Bool
        let expandedProperties: CoolPropPureFluidProperties?
        let solverMethod: String
        let warnings: [String]
    }

    public init(engine: Engine) {
        self.engine = engine
        self.envelopeCache = PureCarbonDioxideEnvelopeCache()
    }

    public var descriptor: ModelDescriptor {
        ModelDescriptor(
            id: "coolprop-heos",
            name: "General Properties",
            modelVersion: engine.libraryVersion,
            providerVersion: "0.11.0",
            availability: engine.isAvailable ? .preliminary : .unavailable,
            calculationMode: .local,
            supportedComponents: engine.isAvailable
                ? [
                    .carbonDioxide, .nitrogen, .oxygen, .argon, .methane, .hydrogen,
                    .carbonMonoxide, .hydrogenSulfide, .water
                ]
                : [],
            supportedProperties: engine.isAvailable
                ? [
                    .density,
                    .dynamicViscosity,
                    .molarMass,
                    .compressibilityFactor,
                    .specificVolume,
                    .enthalpy,
                    .entropy,
                    .internalEnergy,
                    .isobaricHeatCapacity,
                    .isochoricHeatCapacity,
                    .heatCapacityRatio,
                    .speedOfSound,
                    .thermalConductivity,
                    .jouleThomsonCoefficient
                ]
                : [],
            domain: .initialCO2Transport,
            scientificBasis: "CoolProp HEOS pure-fluid CO₂, restricted dry CO₂-rich mixtures, and a preliminary homogeneous CO₂-rich water-vapor route. The General Properties capability matrix separates calculable states from independently validated states.",
            equationOrMethod: "CoolProp HEOS; pure-CO₂ properties use one AbstractState(P,T) update. Dry mixtures use shipped interaction entries through the HEOS/multifluid route. Preliminary CO₂/H₂O gas density uses the shipped Gernert CO₂/Water pair with an imposed gas phase, never the unsafe high-level mixture PT flash.",
            coefficientSetVersion: engine.libraryVersion,
            requiredResources: ["PhaseXpertCoolPropBridge.xcframework"],
            limitations: [
                "Pure CO₂ supports density, viscosity, caloric properties, heat capacities, speed of sound, thermal conductivity, Joule-Thomson coefficient and explicitly derived engineering properties.",
                "Dry CO₂-rich mixtures may contain N₂, O₂, Ar, CH₄, H₂, CO and H₂S with total impurity in (0, 10] mol%; this product guardrail remains calculability scope, not a validated accuracy range.",
                "Mixtures remain restricted to density, phase and three explicitly derived engineering properties; expanded pure-fluid properties are unavailable.",
                "Preliminary integration; no production accuracy claim.",
                "Mixture viscosity, caloric, acoustic, conductivity and derivative properties are unavailable pending separate validation.",
                "Production phase diagrams are scoped to pure CO₂; multicomponent compositions are not routed to phase-envelope generation.",
                "H₂O homogeneous properties remain preliminary for binary CO₂/H₂O at xH₂O = 1–1000 ppm, 350–423.15 K and 0.5–5 MPa.",
                "Binary pure-water equilibrium is separately limited-production in explicit 30–80 °C / 0.4999–5.0055 MPa and 100 °C / 4.70–15.09 MPa regions; brine, wet multicomponent equilibrium and pH are unsupported."
            ],
            references: [
                SourceReference(
                    authors: "Meyer and Harvey",
                    title: "Dew-Point Measurements for Water in Compressed Carbon Dioxide",
                    year: 2015,
                    doiOrURL: "https://doi.org/10.1002/aic.14818"
                ),
                SourceReference(
                    authors: "Span and Wagner",
                    title: "A New Equation of State for Carbon Dioxide Covering the Fluid Region from the Triple-Point Temperature to 1100 K at Pressures up to 800 MPa",
                    year: 1996,
                    doiOrURL: "https://doi.org/10.1063/1.555991"
                ),
                SourceReference(
                    authors: "Bell, Wronski, Quoilin and Lemort",
                    title: "Pure and Pseudo-pure Fluid Thermophysical Property Evaluation and the Open-Source Thermophysical Property Library CoolProp",
                    year: 2014,
                    doiOrURL: "https://doi.org/10.1021/ie4033999"
                ),
                SourceReference(
                    authors: "Kunz and Wagner",
                    title: "The GERG-2008 Wide-Range Equation of State for Natural Gases and Other Mixtures",
                    year: 2012,
                    doiOrURL: "https://doi.org/10.1021/je300655b"
                ),
                SourceReference(
                    authors: "Mazzoccoli, Bosio and Arato",
                    title: "Pressure-Density-Temperature Measurements of Binary Mixtures Rich in CO₂ for Pipeline Transportation in the CCS Process",
                    year: 2012,
                    doiOrURL: "https://doi.org/10.1021/je300590v"
                ),
                SourceReference(
                    authors: "Arai, Kaminishi and Saito",
                    title: "The Experimental Determination of the P-V-T-X Relations for the Carbon Dioxide-Nitrogen and the Carbon Dioxide-Methane Systems",
                    year: 1971,
                    doiOrURL: "https://doi.org/10.1252/jcej.4.113"
                ),
                SourceReference(
                    authors: "Petropoulou et al.",
                    title: "Vapor-Liquid Equilibrium of the Carbon Dioxide/Methane Mixture at Three Isotherms",
                    year: 2018,
                    doiOrURL: "https://doi.org/10.1016/j.fluid.2017.12.015"
                ),
                SourceReference(
                    authors: "Ahamada, Valtz, Chabab, Blanco-Martín and Coquelet",
                    title: "Experimental Density Data of Three Carbon Dioxide and Oxygen Binary Mixtures at Temperatures from 276 to 416 K and at Pressures up to 20 MPa",
                    year: 2020,
                    doiOrURL: "https://doi.org/10.1021/acs.jced.0c00484"
                ),
                SourceReference(
                    authors: "Westman et al.",
                    title: "Vapor-Liquid Equilibrium Data for the Carbon Dioxide and Oxygen System",
                    year: 2016,
                    doiOrURL: "https://doi.org/10.1016/j.fluid.2016.04.002"
                ),
                SourceReference(
                    authors: "Løvseth et al.",
                    title: "Thermodynamics of the Carbon Dioxide plus Argon System",
                    year: 2018,
                    doiOrURL: "https://doi.org/10.1016/j.fluid.2018.03.006"
                ),
                SourceReference(
                    authors: "Chapoy et al.",
                    title: "Vapour-Liquid Equilibrium Data for the Carbon Dioxide plus Carbon Monoxide System",
                    year: 2020,
                    doiOrURL: "https://doi.org/10.1016/j.fluid.2020.112733"
                ),
                SourceReference(
                    authors: "Huber, Sykioti, Assael and Perkins",
                    title: "Reference Correlation of the Thermal Conductivity of Carbon Dioxide from the Triple Point to 1100 K and up to 200 MPa",
                    year: 2016,
                    doiOrURL: "https://doi.org/10.1063/1.4940892"
                ),
                SourceReference(
                    authors: "Laesecke and Muzny",
                    title: "Reference Correlation for the Viscosity of Carbon Dioxide",
                    year: 2017,
                    doiOrURL: "https://doi.org/10.1063/1.4977429"
                ),
                SourceReference(
                    authors: "Linstrom and Mallard (editors)",
                    title: "NIST Chemistry WebBook, NIST Standard Reference Database Number 69",
                    year: 2025,
                    doiOrURL: "https://doi.org/10.18434/T4D303"
                ),
                SourceReference(
                    authors: "CODATA Task Group on Fundamental Constants",
                    title: "2022 CODATA recommended values of the fundamental physical constants",
                    year: 2022,
                    doiOrURL: "https://physics.nist.gov/cuu/Constants/"
                ),
                SourceReference(
                    authors: "Wagner and Pruß",
                    title: "The IAPWS Formulation 1995 for the Thermodynamic Properties of Ordinary Water Substance for General and Scientific Use",
                    year: 2002,
                    doiOrURL: "https://doi.org/10.1063/1.1461829"
                ),
                SourceReference(
                    authors: "Spycher, Pruess and Ennis-King",
                    title: "CO₂-H₂O mixtures in the geological sequestration of CO₂. I. Assessment and calculation of mutual solubilities from 12 to 100 °C and up to 600 bar",
                    year: 2003,
                    doiOrURL: "https://doi.org/10.1016/S0016-7037(03)00273-4"
                ),
                SourceReference(
                    authors: "Sanchez-Vicente and Trusler",
                    title: "Measurements and Modelling of Vapour-Liquid Equilibrium for (H₂O + N₂) and (CO₂ + H₂O + N₂) Systems",
                    year: 2022,
                    doiOrURL: "https://doi.org/10.3390/en15113936"
                )
            ]
        )
    }

    public func applicabilityIssues(
        for composition: [MixtureComponent]
    ) -> [ValidationIssue] {
        let totalImpurity = composition
            .filter {
                $0.component != .carbonDioxide
                    && $0.moleFraction.isFinite
                    && $0.moleFraction > 0
            }
            .reduce(0) { $0 + $1.moleFraction }

        var issues: [ValidationIssue] = []
        let active = composition.filter { $0.moleFraction.isFinite && $0.moleFraction > 0 }
        if let water = active.first(where: { $0.component == .water }),
           active.count != 2
            || !active.contains(where: { $0.component == .carbonDioxide })
            || water.moleFraction < 1e-6
            || water.moleFraction > 0.001 {
            issues.append(
                ValidationIssue(
                    code: .componentOutsideModelRange,
                    severity: .error,
                    message: "Homogeneous H₂O properties require binary CO₂/H₂O with 1–1000 ppm H₂O. The separate equilibrium preview never drops additional components."
                )
            )
        }
        if totalImpurity > Self.maximumTotalImpurityMoleFraction {
            issues.append(
                ValidationIssue(
                    code: .componentOutsideModelRange,
                    severity: .error,
                    message: "The preliminary dry-mixture scope is limited to at most 10 mol% total impurity. This temporary product guardrail is not a validated accuracy range."
                )
            )
        }

        let total = composition.reduce(0) { $0 + $1.moleFraction }
        let deviation = abs(total - 1)
        if
            totalImpurity > CalculationValidator.compositionTolerance,
            total.isFinite,
            deviation > Self.mixtureCompositionSumTolerance,
            deviation <= CalculationValidator.compositionTolerance
        {
            issues.append(
                ValidationIssue(
                    code: .compositionTotal,
                    severity: .error,
                    message: "Dry-mixture mole fractions must sum to 100 mol% without implicit native normalization. Adjust the entered values explicitly."
                )
            )
        }
        return issues
    }

    public func operatingRangeGuidance(
        for context: OperatingGuidanceContext
    ) -> OperatingRangeGuidance? {
        guard let water = context.composition.first(where: {
            $0.component == .water && $0.moleFraction > 0
        }) else { return nil }
        var issues: [OperatingGuidanceLine] = []
        if water.moleFraction < 1e-6 || water.moleFraction > 0.001 {
            issues.append(.init(
                severity: .unsupported,
                title: "Water outside preliminary range",
                detail: "Enter 1–1000 ppm H₂O on a mole basis."
            ))
        }
        if let temperatureK = context.temperatureK,
           !(350...423.15).contains(temperatureK) {
            let equilibriumRemainsAvailable = context.pressurePa.map {
                SpycherPruess2003WaterEquilibrium.isValidated(
                    pressurePa: $0,
                    temperatureK: temperatureK
                )
            } ?? false
            issues.append(.init(
                severity: .unsupported,
                title: "Homogeneous properties outside preliminary range",
                detail: equilibriumRemainsAvailable
                    ? "Homogeneous wet-gas properties are limited to 350–423.15 K. Water-equilibrium results remain available within their separate validated range."
                    : "CO₂/H₂O homogeneous gas is limited to 350–423.15 K."
            ))
        }
        if let pressurePa = context.pressurePa,
           !(500_000...5_000_000).contains(pressurePa) {
            let equilibriumRemainsAvailable = context.temperatureK.map {
                SpycherPruess2003WaterEquilibrium.isValidated(
                    pressurePa: pressurePa,
                    temperatureK: $0
                )
            } ?? false
            issues.append(.init(
                severity: .unsupported,
                title: "Homogeneous properties outside preliminary range",
                detail: equilibriumRemainsAvailable
                    ? "Homogeneous wet-gas properties are limited to 5–50 bar(a). Water-equilibrium results remain available within their separate validated range."
                    : "CO₂/H₂O homogeneous gas is limited to 5–50 bar(a)."
            ))
        }
        return OperatingRangeGuidance(
            title: "Preliminary homogeneous wet-gas range",
            summary: [
                .init(severity: .information, title: "Composition", detail: "Binary CO₂/H₂O; xH₂O = 1–1000 ppm (mole basis)"),
                .init(severity: .information, title: "Homogeneous properties", detail: "Density plus derived molar mass, specific volume and compressibility factor"),
                .init(severity: .information, title: "Water equilibrium", detail: "Limited-production binary pure-water equilibrium in separate 30–80 °C / 4.999–50.055 bar(a) and 100 °C / 47.0–150.9 bar(a) regions")
            ],
            currentInputIssues: issues,
            propertyAvailability: [
                .init(severity: .information, title: "Available", detail: "Homogeneous gas density, M, v and Z"),
                .init(severity: .unsupported, title: "Unavailable", detail: "Cp/Cv, sound speed, transport, brine equilibrium, wet multicomponent equilibrium and pH")
            ],
            phaseDiagram: [
                .init(severity: .unsupported, title: "Phase Map", detail: "Unavailable for H₂O-containing mixtures; dry-mixture safety routing remains unchanged.")
            ]
        )
    }

    public func calculate(_ request: CalculationRequest) async throws -> CalculationResponse {
        try await calculate(request, dryMixturePhaseHint: nil)
    }

    public func calculateScreenedHomogeneous(_ request: CalculationRequest) async throws -> CalculationResponse {
        let composition = try supportedComposition(request.composition)
        guard case let .dryMixture(activeComposition) = composition else {
            return try await calculate(request, dryMixturePhaseHint: nil)
        }
        let hint = try await safeDryMixturePhaseHint(
            pressurePa: request.pressurePa,
            temperatureK: request.temperatureK,
            activeComposition: activeComposition
        )
        return try await calculate(request, dryMixturePhaseHint: hint)
    }

    private func calculate(
        _ request: CalculationRequest,
        dryMixturePhaseHint: CoolPropSinglePhaseHint?
    ) async throws -> CalculationResponse {
        try Task.checkCancellation()
        guard engine.isAvailable else {
            throw ProviderError.modelUnavailable(
                "CoolProp is not available in this build."
            )
        }
        guard request.modelID == descriptor.id else {
            throw ProviderError.invalidRequest("The request model ID does not match CoolProp.")
        }
        guard request.pressurePa.isFinite, request.temperatureK.isFinite else {
            throw ProviderError.invalidRequest("Pressure and temperature must be finite.")
        }
        guard
            request.pressurePa >= descriptor.domain.minimumPressurePa,
            request.pressurePa <= descriptor.domain.maximumPressurePa,
            request.temperatureK >= descriptor.domain.minimumTemperatureK,
            request.temperatureK <= descriptor.domain.maximumTemperatureK
        else {
            throw ProviderError.invalidRequest(
                "The state point is outside the preliminary CoolProp domain."
            )
        }
        let composition = try supportedComposition(request.composition)
        let startedAt = Date()
        let state: ResolvedState

        switch composition {
        case .pureCarbonDioxide:
            let raw = try await engine.calculatePureCarbonDioxide(
                pressurePa: request.pressurePa,
                temperatureK: request.temperatureK
            )
            state = ResolvedState(
                densityKilogramsPerCubicMetre: raw.densityKilogramsPerCubicMetre,
                dynamicViscosityPascalSeconds: raw.dynamicViscosityPascalSeconds,
                phaseIdentifier: raw.phaseIdentifier,
                isPureCarbonDioxide: true,
                expandedProperties: raw.expandedProperties,
                solverMethod: "CoolProp AbstractState(HEOS, CO₂), single P,T state update",
                warnings: [
                    "Expanded pure-CO₂ caloric, acoustic, conductivity and derivative properties have not completed independent PhaseXpert validation.",
                    "Enthalpy, entropy and internal energy use the pinned CoolProp default reference state."
                ]
            )
        case let .dryMixture(activeComposition):
            let resolvedPhaseHint: CoolPropSinglePhaseHint
            if let dryMixturePhaseHint {
                resolvedPhaseHint = dryMixturePhaseHint
            } else {
                resolvedPhaseHint = try await safeDryMixturePhaseHint(
                    pressurePa: request.pressurePa,
                    temperatureK: request.temperatureK,
                    activeComposition: activeComposition
                )
            }
            let raw =
                try await engine.calculateDryCarbonDioxideMixture(
                    pressurePa: request.pressurePa,
                    temperatureK: request.temperatureK,
                    composition: activeComposition,
                    imposedPhase: resolvedPhaseHint
                )
            state = ResolvedState(
                densityKilogramsPerCubicMetre: raw.densityKilogramsPerCubicMetre,
                dynamicViscosityPascalSeconds: nil,
                phaseIdentifier: raw.phaseIdentifier,
                isPureCarbonDioxide: false,
                expandedProperties: nil,
                solverMethod: "CoolProp legacy-stability phase screening plus imposed single-phase HEOS dry-mixture P,T update; pinned library interaction entries only",
                warnings: [
                    "DRY MIXTURE — PROPERTY-SPECIFIC VALIDATION: density and derived volumetric properties are calculable; the General Properties capability matrix reports whether the current state is limited-production or preliminary.",
                    GeneralPropertiesCapabilityMatrix.capabilitySummary(
                        for: request.composition,
                        pressurePa: request.pressurePa,
                        temperatureK: request.temperatureK
                    ),
                    "The 10 mol% total-impurity cap is a PhaseXpert product guardrail, not a validated accuracy range.",
                    "Mixture dynamic viscosity and expanded properties are not enabled; phase diagrams are scoped to pure CO₂."
                ]
            )
        case let .wetCarbonDioxideGas(activeComposition):
            let carbonDioxide = activeComposition.first { $0.component == .carbonDioxide }?.moleFraction ?? 0
            let water = activeComposition.first { $0.component == .water }?.moleFraction ?? 0
            guard homogeneousWaterGasIsCalculable(
                pressurePa: request.pressurePa,
                temperatureK: request.temperatureK,
                waterMoleFraction: water
            ) else {
                if let response = waterEquilibriumOnlyResponse(
                    request: request,
                    currentWaterMoleFraction: water,
                    startedAt: startedAt
                ) {
                    return response
                }
                throw ProviderError.invalidRequest(
                    "No General Properties CO₂/H₂O calculation family is available at this state. Preliminary homogeneous gas support is limited to 350–423.15 K and 0.5–5 MPa; water equilibrium is limited to \(SpycherPruess2003WaterEquilibrium.validatedRangeSummary)"
                )
            }
            let raw = try await engine.calculateCarbonDioxideWaterHomogeneousGas(
                pressurePa: request.pressurePa,
                temperatureK: request.temperatureK,
                carbonDioxideMoleFraction: carbonDioxide,
                waterMoleFraction: water
            )
            state = ResolvedState(
                densityKilogramsPerCubicMetre: raw.densityKilogramsPerCubicMetre,
                dynamicViscosityPascalSeconds: nil,
                phaseIdentifier: raw.phaseIdentifier,
                isPureCarbonDioxide: false,
                expandedProperties: nil,
                solverMethod: "CoolProp AbstractState(HEOS, CO₂/H₂O), imposed homogeneous gas phase; Gernert CO₂-Water pair",
                warnings: [
                    "WET GAS — PRELIMINARY / VALIDATION PENDING: only homogeneous density and derived M, v and Z are available.",
                    GeneralPropertiesCapabilityMatrix.capabilitySummary(
                        for: request.composition,
                        pressurePa: request.pressurePa,
                        temperatureK: request.temperatureK
                    ),
                    "The homogeneous CoolProp state does not itself determine aqueous equilibrium, water dropout or pH."
                ]
            )
        }
        try Task.checkCancellation()

        guard
            state.densityKilogramsPerCubicMetre.isFinite,
            state.densityKilogramsPerCubicMetre > 0
        else {
            throw ProviderError.malformedResponse(
                "CoolProp returned a non-finite or non-positive density."
            )
        }
        if let viscosity = state.dynamicViscosityPascalSeconds {
            guard viscosity.isFinite, viscosity > 0 else {
                throw ProviderError.malformedResponse(
                    "CoolProp returned a non-finite or non-positive dynamic viscosity."
                )
            }
        }

        let derivedValues = DerivedPropertyCalculator().values(
            requestedProperties: request.requestedProperties,
            pressurePa: request.pressurePa,
            temperatureK: request.temperatureK,
            composition: request.composition,
            densityKilogramsPerCubicMetre: state.densityKilogramsPerCubicMetre
        )
        let derivedByProperty = Dictionary(
            uniqueKeysWithValues: derivedValues.map { ($0.property, $0) }
        )
        let values = request.requestedProperties
            .sorted { $0.rawValue < $1.rawValue }
            .map { property in
                derivedByProperty[property]
                    ?? propertyValue(for: property, state: state)
            }
        let derivedMethod = derivedValues.isEmpty
            ? ""
            : "; derived M=ΣxᵢMᵢ, v=1/ρ, Z=pM/(ρRT)"

        let waterEquilibrium: CarbonDioxideWaterEquilibriumResult?
        if case .wetCarbonDioxideGas = composition {
            let currentWater = request.composition.first {
                $0.component == .water
            }?.moleFraction
            waterEquilibrium = try? SpycherPruess2003WaterEquilibrium().equilibrium(
                pressurePa: request.pressurePa,
                temperatureK: request.temperatureK,
                currentWaterMoleFraction: currentWater
            )
        } else {
            waterEquilibrium = nil
        }
        let equilibriumWarnings = waterEquilibrium == nil ? [] : [
            "WATER EQUILIBRIUM — LIMITED PRODUCTION: binary CO₂ + pure H₂O only, independently validated in separate 30–80 °C / 0.4999–5.0055 MPa and 100 °C / 4.70–15.09 MPa regions.",
            "Water-dropout temperature is returned only from the bounded 30–80 °C validation region; dropout pressure is returned only when a root exists inside the applicable region."
        ]

        return CalculationResponse(
            requestID: request.requestID,
            model: descriptor,
            phase: phaseRegion(for: state.phaseIdentifier),
            properties: values,
            solver: SolverMetadata(
                method: state.solverMethod + derivedMethod,
                converged: true,
                durationMilliseconds: Date().timeIntervalSince(startedAt) * 1_000
            ),
            warnings: [
                "HOMOGENEOUS PROPERTIES — PRELIMINARY / VALIDATION PENDING: do not use those property values for engineering, safety, commercial, or regulatory decisions."
            ] + state.warnings + equilibriumWarnings,
            isScientificResult: true,
            waterEquilibrium: waterEquilibrium
        )
    }

    private func homogeneousWaterGasIsCalculable(
        pressurePa: Double,
        temperatureK: Double,
        waterMoleFraction: Double
    ) -> Bool {
        (1e-6...0.001).contains(waterMoleFraction)
            && (350...423.15).contains(temperatureK)
            && (500_000...5_000_000).contains(pressurePa)
    }

    private func waterEquilibriumOnlyResponse(
        request: CalculationRequest,
        currentWaterMoleFraction: Double,
        startedAt: Date
    ) -> CalculationResponse? {
        guard let waterEquilibrium = try? SpycherPruess2003WaterEquilibrium().equilibrium(
            pressurePa: request.pressurePa,
            temperatureK: request.temperatureK,
            currentWaterMoleFraction: currentWaterMoleFraction
        ) else {
            return nil
        }
        let values = request.requestedProperties
            .sorted { $0.rawValue < $1.rawValue }
            .map(wetHomogeneousUnavailableProperty)
        return CalculationResponse(
            requestID: request.requestID,
            model: descriptor,
            phase: .unavailable,
            properties: values,
            solver: SolverMetadata(
                method: "Partial General Properties result: binary CO₂/H₂O water equilibrium only; homogeneous wet-gas properties skipped outside preliminary property range",
                converged: true,
                durationMilliseconds: Date().timeIntervalSince(startedAt) * 1_000
            ),
            warnings: [
                "PARTIAL RESULT — water equilibrium was calculated; homogeneous wet-gas density and derived M, v and Z are unavailable at this state.",
                "WATER EQUILIBRIUM — LIMITED PRODUCTION: binary CO₂ + pure H₂O only, independently validated in separate 30–80 °C / 0.4999–5.0055 MPa and 100 °C / 4.70–15.09 MPa regions.",
                "HOMOGENEOUS PROPERTIES — UNAVAILABLE: preliminary CO₂/H₂O homogeneous gas support is limited to 350–423.15 K and 0.5–5 MPa."
            ],
            isScientificResult: true,
            waterEquilibrium: waterEquilibrium
        )
    }

    private func wetHomogeneousUnavailableProperty(
        for property: PropertyID
    ) -> PropertyValue {
        let unit: String
        switch property {
        case .density:
            unit = "kg/m³"
        case .molarMass:
            unit = "kg/mol"
        case .specificVolume:
            unit = "m³/kg"
        case .compressibilityFactor:
            unit = "1"
        case .dynamicViscosity:
            unit = "Pa·s"
        case .enthalpy, .internalEnergy:
            unit = "J/kg"
        case .entropy:
            unit = "J/(kg·K)"
        case .isobaricHeatCapacity, .isochoricHeatCapacity:
            unit = "J/(kg·K)"
        case .heatCapacityRatio:
            unit = "1"
        case .speedOfSound:
            unit = "m/s"
        case .thermalConductivity:
            unit = "W/(m·K)"
        case .jouleThomsonCoefficient:
            unit = "°C/bar"
        default:
            unit = ""
        }
        let message: String
        if GeneralPropertiesCapabilityMatrix.wetHomogeneousCalculableProperties.contains(property) {
            message = "Outside preliminary homogeneous-property range."
        } else {
            message = "This wet-gas property is unavailable pending independent validation."
        }
        return PropertyValue(
            property: property,
            value: nil,
            unit: unit,
            status: .unavailable,
            message: message
        )
    }

    public func phaseClassification(
        pressurePa: Double,
        temperatureK: Double,
        composition: [MixtureComponent]
    ) async throws -> PhaseMapClassificationResult {
        let supported = try supportedComposition(composition)
        guard case let .dryMixture(activeComposition) = supported else {
            throw ProviderError.invalidRequest("Exact-state phase screening is available only for supported dry mixtures.")
        }
        let raw = try await engine.identifyDryCarbonDioxideMixturePhase(
            pressurePa: pressurePa,
            temperatureK: temperatureK,
            composition: activeComposition
        )
        return PhaseMapClassificationAdapter.map(phaseRegion(for: raw.phaseIdentifier))
    }

    private func safeDryMixturePhaseHint(
        pressurePa: Double,
        temperatureK: Double,
        activeComposition: [MixtureComponent]
    ) async throws -> CoolPropSinglePhaseHint {
        let raw = try await engine.identifyDryCarbonDioxideMixturePhase(
            pressurePa: pressurePa,
            temperatureK: temperatureK,
            composition: activeComposition
        )
        let classification = PhaseMapClassificationAdapter.map(
            phaseRegion(for: raw.phaseIdentifier)
        )
        switch classification.classification {
        case .gas:
            return .gas
        case .liquid, .dense:
            return .liquid
        default:
            throw ProviderError.invalidRequest(
                "The homogeneous dry-mixture property point was skipped after safe phase screening returned \(classification.displayName)."
            )
        }
    }

    public func phaseMap(
        _ request: PhaseMapRequest,
        progress: (@Sendable (PhaseMapProgress) async -> Void)? = nil
    ) async throws -> PhaseMapResult {
        try Task.checkCancellation()
        guard engine.isAvailable else {
            throw ProviderError.modelUnavailable(
                "CoolProp is not available in this build."
            )
        }
        guard request.modelID == descriptor.id else {
            throw ProviderError.invalidRequest("The phase-map request model ID does not match CoolProp.")
        }
        let points = try PhaseMapGridBuilder.points(for: request)
        let supported = try supportedComposition(request.composition)
        if case .wetCarbonDioxideGas = supported {
            throw ProviderError.invalidRequest(
                "Phase Map is unavailable for H₂O-containing mixtures; the PR #49 dry-mixture safety path is unchanged."
            )
        }
        guard case let .dryMixture(activeComposition) = supported else {
            throw ProviderError.invalidRequest(
                "CoolProp legacy-stability Phase Map is available only for supported dry mixtures."
            )
        }

        let startedAt = Date()
        var evaluations: [PhaseMapEvaluation] = []
        evaluations.reserveCapacity(points.count)

        for (index, point) in points.enumerated() {
            try Task.checkCancellation()
            do {
                debugLogPhaseMapNativeCall(
                    index: index,
                    point: point,
                    composition: request.composition,
                    providerPath: "CoolProp dry-mixture legacy-stability phase classifier"
                )
                let raw = try await engine.identifyDryCarbonDioxideMixturePhase(
                    pressurePa: point.pressurePa,
                    temperatureK: point.temperatureK,
                    composition: activeComposition
                )
                evaluations.append(PhaseMapEvaluation(
                    point: point,
                    classification: PhaseMapClassificationAdapter.map(
                        phaseRegion(for: raw.phaseIdentifier)
                    ),
                    solver: SolverMetadata(
                        method: "CoolProp legacy mixture stability, HEOS dry CO₂-rich mixture; phase-map classification without requesting density as a Phase Map property",
                        converged: true,
                        durationMilliseconds: Date().timeIntervalSince(startedAt) * 1_000
                    ),
                    failureReason: nil
                ))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                evaluations.append(failedEvaluation(
                    point: point,
                    message: userMessage(for: error)
                ))
            }
            await progress?(PhaseMapProgress(completedCount: evaluations.count, totalCount: points.count))
        }

        return PhaseMapResult(
            request: request,
            model: descriptor,
            evaluations: evaluations,
            warnings: [
                "Phase Map classifies discrete provider flash points only; it is not a phase envelope and does not trace bubble or dew boundaries.",
                "CoolProp dry-mixture Phase Map uses a safe legacy-stability phase classifier; boundary-conflicting points are reported as Unknown.",
                "Narrow phase regions can be missed between evaluated grid points."
            ]
        )
    }

    public func phaseEnvelope(_ request: PhaseEnvelopeRequest) async throws -> PhaseEnvelopeResponse {
        try Task.checkCancellation()
        let startedAt = Date()
        guard engine.isAvailable else {
            return unavailableEnvelope(
                requestID: request.requestID,
                warning: "Phase boundary unavailable because CoolProp is not linked."
            )
        }
        guard request.modelID == descriptor.id else {
            throw ProviderError.invalidRequest(
                "The phase-envelope request model ID does not match CoolProp."
            )
        }
        let supported = try supportedComposition(request.composition)
        if case .dryMixture = supported {
            throw ProviderError.invalidRequest(
                PhaseDiagramEligibility.pureCarbonDioxideScopeMessage
            )
        }
        if case .wetCarbonDioxideGas = supported {
            throw ProviderError.invalidRequest(
                PhaseDiagramEligibility.pureCarbonDioxideScopeMessage
            )
        }

        let cacheKey = "\(engine.libraryVersion)-pure-co2-\(Self.saturationPointCount)"
        if let cached = await envelopeCache.entry(for: cacheKey) {
            return PhaseEnvelopeResponse(
                requestID: request.requestID,
                points: cached.points,
                warnings: cached.warnings,
                isAvailable: true,
                boundaryKind: .pureFluidSaturation,
                model: descriptor,
                generatedAt: cached.generatedAt,
                solver: cached.solver
            )
        }

        let limits = try await engine.pureCarbonDioxideSaturationLimits()
        try validate(limits)

        // Sampling avoids both singular endpoints. The actual critical point is
        // returned separately from CoolProp and is not inferred from the curve.
        let span = limits.criticalPointTemperatureK - limits.triplePointTemperatureK
        let endpointOffset = max(span * 1e-6, 1e-4)
        let firstTemperature = limits.triplePointTemperatureK + endpointOffset
        let lastTemperature = limits.criticalPointTemperatureK - endpointOffset
        let increment = (lastTemperature - firstTemperature)
            / Double(Self.saturationPointCount - 1)

        var points: [PhaseEnvelopePoint] = []
        points.reserveCapacity(Self.saturationPointCount + 1)
        for index in 0..<Self.saturationPointCount {
            try Task.checkCancellation()
            let temperature = firstTemperature + Double(index) * increment
            let pressure = try await engine.pureCarbonDioxideSaturationPressure(
                temperatureK: temperature
            )
            guard pressure.isFinite, pressure > 0 else {
                throw ProviderError.malformedResponse(
                    "CoolProp returned a non-finite or non-positive saturation pressure."
                )
            }
            guard points.last.map({ pressure > $0.pressurePa }) ?? true else {
                throw ProviderError.malformedResponse(
                    "CoolProp returned a non-increasing pure-CO₂ saturation boundary."
                )
            }
            points.append(
                PhaseEnvelopePoint(
                    temperatureK: temperature,
                    pressurePa: pressure,
                    branch: .bubble
                )
            )
        }
        points.append(
            PhaseEnvelopePoint(
                temperatureK: limits.criticalPointTemperatureK,
                pressurePa: limits.criticalPointPressurePa,
                branch: .critical
            )
        )
        try Task.checkCancellation()

        let generatedAt = Date()
        let warnings = [
            "PRELIMINARY — VALIDATION PENDING: the plotted boundary must not be used for engineering, safety, commercial, or regulatory decisions.",
            "For pure CO₂, bubble and dew boundaries coincide; the chart shows one saturation boundary."
        ]
        let solver = SolverMetadata(
            method: "CoolProp PropsSI(P,T,Q=0), HEOS pure CO₂",
            converged: true,
            durationMilliseconds: Date().timeIntervalSince(startedAt) * 1_000
        )
        await envelopeCache.store(
            .init(
                points: points,
                warnings: warnings,
                generatedAt: generatedAt,
                solver: solver
            ),
            for: cacheKey
        )
        return PhaseEnvelopeResponse(
            requestID: request.requestID,
            points: points,
            warnings: warnings,
            isAvailable: true,
            boundaryKind: .pureFluidSaturation,
            model: descriptor,
            generatedAt: generatedAt,
            solver: solver
        )
    }

    private func supportedComposition(
        _ composition: [MixtureComponent]
    ) throws -> SupportedComposition {
        guard !composition.isEmpty else {
            throw ProviderError.invalidRequest("Composition cannot be empty.")
        }
        guard composition.allSatisfy({
            $0.moleFraction.isFinite && $0.moleFraction >= 0
        }) else {
            throw ProviderError.invalidRequest(
                "Composition mole fractions must be finite and non-negative."
            )
        }
        let grouped = Dictionary(grouping: composition, by: \.component)
        guard grouped.values.allSatisfy({ $0.count == 1 }) else {
            throw ProviderError.invalidRequest("Each component may appear only once.")
        }

        let total = composition.reduce(0) { $0 + $1.moleFraction }
        guard abs(total - 1) <= CalculationValidator.compositionTolerance else {
            throw ProviderError.invalidRequest(
                "Composition must total 100 mol% before CoolProp calculation."
            )
        }
        let active = composition.filter {
            $0.moleFraction > 0
        }
        if isPureCarbonDioxide(active) {
            return .pureCarbonDioxide
        }
        if active.contains(where: { $0.component == .water }) {
            guard active.count == 2,
                  let carbonDioxide = active.first(where: { $0.component == .carbonDioxide }),
                  let water = active.first(where: { $0.component == .water }),
                  carbonDioxide.moleFraction > water.moleFraction,
                  water.moleFraction >= 1e-6,
                  water.moleFraction <= 0.001 else {
                throw ProviderError.invalidRequest(
                    "Preliminary H₂O support is limited to binary CO₂/H₂O homogeneous gas with xH₂O from 1 to 1000 ppm."
                )
            }
            return .wetCarbonDioxideGas(active)
        }
        if let unsupported = active.first(where: {
            !Self.supportedDryComponents.contains($0.component)
        }) {
            throw ProviderError.unsupportedComponent(unsupported.component)
        }
        guard
            active.count >= 2,
            let carbonDioxide = active.first(where: { $0.component == .carbonDioxide })
        else {
            throw ProviderError.invalidRequest(
                "The preliminary provider requires CO₂ plus at least one supported dry impurity."
            )
        }
        guard active.allSatisfy({
            $0.component == .carbonDioxide
                || carbonDioxide.moleFraction > $0.moleFraction
        }) else {
            throw ProviderError.invalidRequest("CO₂ must be the unique largest component.")
        }
        let totalImpurity = active
            .filter { $0.component != .carbonDioxide }
            .reduce(0) { $0 + $1.moleFraction }
        guard totalImpurity <= Self.maximumTotalImpurityMoleFraction else {
            throw ProviderError.invalidRequest(
                "The dry-mixture scope is temporarily limited to at most 10 mol% total impurity."
            )
        }
        guard abs(total - 1) <= Self.mixtureCompositionSumTolerance else {
            throw ProviderError.invalidRequest(
                "Dry-mixture mole fractions must sum to 100 mol% without implicit normalization."
            )
        }
        return .dryMixture(active)
    }

    private func isPureCarbonDioxide(_ composition: [MixtureComponent]) -> Bool {
        composition.count == 1
            && composition[0].component == .carbonDioxide
            && abs(composition[0].moleFraction - 1)
                <= CalculationValidator.compositionTolerance
    }

    private func validate(_ limits: CoolPropSaturationLimits) throws {
        guard
            limits.triplePointTemperatureK.isFinite,
            limits.triplePointTemperatureK > 0,
            limits.criticalPointTemperatureK.isFinite,
            limits.criticalPointTemperatureK > limits.triplePointTemperatureK,
            limits.criticalPointPressurePa.isFinite,
            limits.criticalPointPressurePa > 0
        else {
            throw ProviderError.malformedResponse(
                "CoolProp returned invalid pure-CO₂ saturation limits."
            )
        }
    }

    private func unavailableEnvelope(
        requestID: UUID,
        warning: String
    ) -> PhaseEnvelopeResponse {
        PhaseEnvelopeResponse(
            requestID: requestID,
            points: [],
            warnings: [warning],
            isAvailable: false,
            model: descriptor,
            generatedAt: Date(),
            solver: SolverMetadata(
                method: "No phase-boundary calculation",
                converged: false,
                durationMilliseconds: 0
            )
        )
    }

    private func propertyValue(
        for property: PropertyID,
        state: ResolvedState
    ) -> PropertyValue {
        switch property {
        case .density:
            PropertyValue(
                property: property,
                value: state.densityKilogramsPerCubicMetre,
                unit: "kg/m³",
                status: .calculated
            )
        case .dynamicViscosity:
            if let viscosity = state.dynamicViscosityPascalSeconds {
                PropertyValue(
                    property: property,
                    value: viscosity,
                    unit: "Pa·s",
                    status: .calculated
                )
            } else {
                unavailablePureProperty(
                    property,
                    unit: "Pa·s",
                    state: state,
                    mixtureMessage: "Mixture dynamic viscosity is not enabled pending independent validation."
                )
            }
        case .enthalpy:
            expandedProperty(
                property,
                unit: "J/kg",
                value: state.expandedProperties?.enthalpyJoulesPerKilogram,
                requiresPositiveValue: false,
                state: state,
                message: "CoolProp HEOS mass-specific enthalpy; default reference state."
            )
        case .entropy:
            expandedProperty(
                property,
                unit: "J/(kg·K)",
                value: state.expandedProperties?.entropyJoulesPerKilogramKelvin,
                requiresPositiveValue: false,
                state: state,
                message: "CoolProp HEOS mass-specific entropy; default reference state."
            )
        case .internalEnergy:
            expandedProperty(
                property,
                unit: "J/kg",
                value: state.expandedProperties?.internalEnergyJoulesPerKilogram,
                requiresPositiveValue: false,
                state: state,
                message: "CoolProp HEOS mass-specific internal energy; default reference state."
            )
        case .isobaricHeatCapacity:
            expandedProperty(
                property,
                unit: "J/(kg·K)",
                value: state.expandedProperties?.isobaricHeatCapacityJoulesPerKilogramKelvin,
                requiresPositiveValue: true,
                state: state,
                message: "CoolProp HEOS mass-specific Cp."
            )
        case .isochoricHeatCapacity:
            expandedProperty(
                property,
                unit: "J/(kg·K)",
                value: state.expandedProperties?.isochoricHeatCapacityJoulesPerKilogramKelvin,
                requiresPositiveValue: true,
                state: state,
                message: "CoolProp HEOS mass-specific Cv."
            )
        case .heatCapacityRatio:
            heatCapacityRatio(state: state)
        case .speedOfSound:
            expandedProperty(
                property,
                unit: "m/s",
                value: state.expandedProperties?.speedOfSoundMetresPerSecond,
                requiresPositiveValue: true,
                state: state,
                message: "CoolProp HEOS equilibrium speed of sound."
            )
        case .thermalConductivity:
            expandedProperty(
                property,
                unit: "W/(m·K)",
                value: state.expandedProperties?.thermalConductivityWattsPerMetreKelvin,
                requiresPositiveValue: true,
                state: state,
                message: "Pinned CoolProp pure-CO₂ thermal-conductivity correlation."
            )
        case .jouleThomsonCoefficient:
            expandedProperty(
                property,
                unit: "°C/bar",
                value: state.expandedProperties.map {
                    $0.jouleThomsonKelvinPerPascal * 100_000
                },
                requiresPositiveValue: false,
                state: state,
                message: "CoolProp single-phase derivative (∂T/∂p)h; converted from K/Pa to °C/bar."
            )
        default:
            PropertyValue(
                property: property,
                value: nil,
                unit: "",
                status: .unavailable,
                message: "This property is not enabled in the CoolProp spike."
            )
        }
    }

    private func expandedProperty(
        _ property: PropertyID,
        unit: String,
        value: Double?,
        requiresPositiveValue: Bool,
        state: ResolvedState,
        message: String
    ) -> PropertyValue {
        guard let value else {
            return unavailablePureProperty(
                property,
                unit: unit,
                state: state,
                mixtureMessage: "This expanded property is enabled for pure CO₂ only."
            )
        }
        guard value.isFinite, !requiresPositiveValue || value > 0 else {
            return PropertyValue(
                property: property,
                value: nil,
                unit: unit,
                status: .failed,
                message: "CoolProp returned a non-finite or non-physical value."
            )
        }
        return PropertyValue(
            property: property,
            value: value,
            unit: unit,
            status: .calculated,
            message: message
        )
    }

    private func heatCapacityRatio(state: ResolvedState) -> PropertyValue {
        guard let expanded = state.expandedProperties else {
            return unavailablePureProperty(
                .heatCapacityRatio,
                unit: "1",
                state: state,
                mixtureMessage: "Cp/Cv is enabled for pure CO₂ only."
            )
        }
        let ratio = expanded.isobaricHeatCapacityJoulesPerKilogramKelvin
            / expanded.isochoricHeatCapacityJoulesPerKilogramKelvin
        guard ratio.isFinite, ratio > 0 else {
            return PropertyValue(
                property: .heatCapacityRatio,
                value: nil,
                unit: "1",
                status: .failed,
                message: "Cp/Cv could not be derived from finite, positive heat capacities."
            )
        }
        return PropertyValue(
            property: .heatCapacityRatio,
            value: ratio,
            unit: "1",
            status: .calculated,
            message: "Derived from the CoolProp HEOS mass-specific Cp/Cv values."
        )
    }

    private func unavailablePureProperty(
        _ property: PropertyID,
        unit: String,
        state: ResolvedState,
        mixtureMessage: String
    ) -> PropertyValue {
        PropertyValue(
            property: property,
            value: nil,
            unit: unit,
            status: state.isPureCarbonDioxide ? .failed : .unavailable,
            message: state.isPureCarbonDioxide
                ? "The pure-CO₂ engine did not return this advertised property."
                : mixtureMessage
        )
    }

    private func failedEvaluation(
        point: PhaseMapGridPoint,
        message: String
    ) -> PhaseMapEvaluation {
        PhaseMapEvaluation(
            point: point,
            classification: PhaseMapClassificationResult(
                classification: .failed,
                displayName: "Failed",
                isSupported: false,
                detail: message
            ),
            solver: nil,
            failureReason: message
        )
    }

    private func userMessage(for error: Error) -> String {
        guard let providerError = error as? ProviderError else {
            return "The provider failed at this point."
        }
        switch providerError {
        case let .modelUnavailable(message),
             let .invalidRequest(message),
             let .malformedResponse(message):
            return message
        case let .unsupportedComponent(component):
            return "\(component.symbol) is not supported by the selected provider."
        case .timeout:
            return "The provider timed out at this point."
        case .cancelled:
            return "The point evaluation was cancelled."
        }
    }

    private func debugLogPhaseMapNativeCall(
        index: Int,
        point: PhaseMapGridPoint,
        composition: [MixtureComponent],
        providerPath: String
    ) {
        #if DEBUG
        let compositionSummary = composition
            .map { "\($0.component.symbol)=\($0.moleFraction)" }
            .joined(separator: ",")
        print(
            "PX_PHASE_MAP_NATIVE index=\(index) P=\(point.pressurePa) T=\(point.temperatureK) composition=\(compositionSummary) path=\(providerPath)"
        )
        fflush(stdout)
        #endif
    }

    private func phaseRegion(for identifier: String) -> PhaseRegion {
        switch identifier.lowercased() {
        case "gas", "supercritical_gas":
            .gas
        case "liquid":
            .liquid
        case "supercritical_liquid":
            .dense
        case "supercritical", "critical_point":
            .supercritical
        case "twophase", "two_phase":
            .twoPhase
        case "solid":
            .solid
        default:
            .unknown
        }
    }
}
