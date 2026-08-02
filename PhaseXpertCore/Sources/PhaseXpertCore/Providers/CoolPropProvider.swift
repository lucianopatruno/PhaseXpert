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
    public let phaseIdentifier: String

    public init(
        densityKilogramsPerCubicMetre: Double,
        phaseIdentifier: String
    ) {
        self.densityKilogramsPerCubicMetre = densityKilogramsPerCubicMetre
        self.phaseIdentifier = phaseIdentifier
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
    public let isClosed: Bool

    public init(
        points: [PhaseEnvelopePoint],
        solverMethod: String,
        isClosed: Bool = true
    ) {
        self.points = points
        self.solverMethod = solverMethod
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

    func pureCarbonDioxideSaturationLimits() async throws -> CoolPropSaturationLimits

    func pureCarbonDioxideSaturationPressure(
        temperatureK: Double
    ) async throws -> Double

    func dryCarbonDioxideMixturePhaseEnvelope(
        composition: [MixtureComponent]
    ) async throws -> CoolPropMixtureEnvelopeResult
}

public extension CoolPropEngine {
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
public struct CoolPropProvider<Engine: CoolPropEngine>: ThermodynamicModelProvider {
    private let engine: Engine
    private let envelopeCache: PureCarbonDioxideEnvelopeCache

    private static var saturationPointCount: Int { 81 }
    private static var maximumTotalImpurityMoleFraction: Double { 0.10 }
    private static var mixtureCompositionSumTolerance: Double { 1e-10 }
    private static var supportedDryComponents: Set<ComponentID> {
        [.carbonDioxide, .nitrogen, .oxygen, .argon, .methane, .hydrogen]
    }

    private enum SupportedComposition {
        case pureCarbonDioxide
        case dryMixture([MixtureComponent])
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
            name: "CoolProp HEOS — Preliminary",
            modelVersion: engine.libraryVersion,
            providerVersion: "0.8.1",
            availability: engine.isAvailable ? .preliminary : .unavailable,
            calculationMode: .local,
            supportedComponents: engine.isAvailable
                ? [.carbonDioxide, .nitrogen, .oxygen, .argon, .methane, .hydrogen]
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
            scientificBasis: "CoolProp HEOS pure-fluid CO₂ and restricted dry CO₂-rich mixture backend.",
            equationOrMethod: "CoolProp HEOS; pure-CO₂ thermodynamic, acoustic and transport values come from one AbstractState(P,T) update. Cp/Cv, molar mass, specific volume and Z are derived transparently. Dry-mixture states and phase envelopes use only interaction entries shipped by the pinned release; no estimated mixing rule is applied.",
            coefficientSetVersion: engine.libraryVersion,
            requiredResources: ["PhaseXpertCoolPropBridge.xcframework"],
            limitations: [
                "Pure CO₂ supports density, viscosity, caloric properties, heat capacities, speed of sound, thermal conductivity, Joule-Thomson coefficient and explicitly derived engineering properties.",
                "Dry CO₂-rich mixtures may contain N₂, O₂, Ar, CH₄ and H₂ with total impurity in (0, 10] mol%; this temporary product guardrail is not a validated accuracy range.",
                "Mixtures remain restricted to density, phase and three explicitly derived engineering properties; expanded pure-fluid properties are unavailable.",
                "Preliminary integration; no production accuracy claim.",
                "Mixture viscosity, caloric, acoustic, conductivity and derivative properties are unavailable pending separate validation.",
                "Dry-mixture phase envelopes use CoolProp's low-level HEOS phase-envelope routine and remain preliminary and validation pending."
            ],
            references: [
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

    public func calculate(_ request: CalculationRequest) async throws -> CalculationResponse {
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
            let raw = try await engine.calculateDryCarbonDioxideMixture(
                pressurePa: request.pressurePa,
                temperatureK: request.temperatureK,
                composition: activeComposition
            )
            state = ResolvedState(
                densityKilogramsPerCubicMetre: raw.densityKilogramsPerCubicMetre,
                dynamicViscosityPascalSeconds: nil,
                phaseIdentifier: raw.phaseIdentifier,
                isPureCarbonDioxide: false,
                expandedProperties: nil,
                solverMethod: "CoolProp PropsSI(P,T), HEOS dry CO₂-rich mixture; pinned library interaction entries only",
                warnings: [
                    "DRY MIXTURE — VALIDATION PENDING: density and phase have not completed independent validation.",
                    "The 10 mol% total-impurity cap is a PhaseXpert product guardrail, not a validated accuracy range.",
                    "Mixture dynamic viscosity and expanded properties are not enabled; phase envelopes are a separate preliminary provider calculation."
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
                "PRELIMINARY — VALIDATION PENDING: do not use this result for engineering, safety, commercial, or regulatory decisions."
            ] + state.warnings,
            isScientificResult: true
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
        if case let .dryMixture(composition) = supported {
            let compositionKey = composition
                .sorted { $0.component.rawValue < $1.component.rawValue }
                .map { "\($0.component.rawValue)=\(String(format: "%.17g", $0.moleFraction))" }
                .joined(separator: ";")
            let cacheKey = "\(engine.libraryVersion)-mixture-\(compositionKey)"
            if let cached = await envelopeCache.entry(for: cacheKey) {
                return PhaseEnvelopeResponse(
                    requestID: request.requestID,
                    points: cached.points,
                    warnings: cached.warnings,
                    isAvailable: true,
                    boundaryKind: .mixtureEnvelope,
                    model: descriptor,
                    generatedAt: cached.generatedAt,
                    solver: cached.solver
                )
            }

            let native = try await engine.dryCarbonDioxideMixturePhaseEnvelope(
                composition: composition
            )
            try validateMixtureEnvelope(native.points)
            try Task.checkCancellation()
            let generatedAt = Date()
            let warnings = [
                "PRELIMINARY — VALIDATION PENDING: the calculated mixture envelope must not be used for engineering, safety, commercial, or regulatory decisions.",
                "Bubble and dew points are returned directly by CoolProp HEOS. PhaseXpert does not interpolate or estimate scientific values."
            ] + (native.isClosed ? [] : [
                "CoolProp returned usable bubble/dew points but did not report pressure closure. PhaseXpert plots only the returned provider points and does not close the trace."
            ])
            let solver = SolverMetadata(
                method: native.solverMethod,
                converged: native.isClosed,
                durationMilliseconds: Date().timeIntervalSince(startedAt) * 1_000
            )
            await envelopeCache.store(
                .init(points: native.points, warnings: warnings, generatedAt: generatedAt, solver: solver),
                for: cacheKey
            )
            return PhaseEnvelopeResponse(
                requestID: request.requestID,
                points: native.points,
                warnings: warnings,
                isAvailable: true,
                boundaryKind: .mixtureEnvelope,
                model: descriptor,
                generatedAt: generatedAt,
                solver: solver
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
            "For pure CO₂, bubble and dew boundaries coincide; the chart shows one saturation boundary calculated by CoolProp HEOS."
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

    private func validateMixtureEnvelope(_ points: [PhaseEnvelopePoint]) throws {
        let bubbleCount = points.filter { $0.branch == .bubble }.count
        let dewCount = points.filter { $0.branch == .dew }.count
        guard points.count >= 4, bubbleCount >= 2, dewCount >= 2 else {
            throw ProviderError.malformedResponse(
                "CoolProp did not return traceable bubble and dew branches."
            )
        }
        guard points.allSatisfy({
            $0.temperatureK.isFinite && $0.temperatureK > 0
                && $0.pressurePa.isFinite && $0.pressurePa > 0
        }) else {
            throw ProviderError.malformedResponse(
                "CoolProp returned a non-finite or non-positive mixture phase-envelope point."
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
