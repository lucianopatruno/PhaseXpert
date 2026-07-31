import Foundation

/// Raw values returned by a CoolProp bridge for one pure-CO₂ state point.
public struct CoolPropEngineResult: Equatable, Sendable {
    public let densityKilogramsPerCubicMetre: Double
    public let dynamicViscosityPascalSeconds: Double
    public let phaseIdentifier: String

    public init(
        densityKilogramsPerCubicMetre: Double,
        dynamicViscosityPascalSeconds: Double,
        phaseIdentifier: String
    ) {
        self.densityKilogramsPerCubicMetre = densityKilogramsPerCubicMetre
        self.dynamicViscosityPascalSeconds = dynamicViscosityPascalSeconds
        self.phaseIdentifier = phaseIdentifier
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

    func pureCarbonDioxideSaturationLimits() async throws -> CoolPropSaturationLimits

    func pureCarbonDioxideSaturationPressure(
        temperatureK: Double
    ) async throws -> Double
}

public extension CoolPropEngine {
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

/// Preliminary established-model provider for pure CO₂ and a restricted CO₂-N₂ spike.
///
/// Availability does not imply scientific validation. Every successful result
/// carries an explicit validation-pending warning.
public struct CoolPropProvider<Engine: CoolPropEngine>: ThermodynamicModelProvider {
    private let engine: Engine
    private let envelopeCache: PureCarbonDioxideEnvelopeCache

    private static var saturationPointCount: Int { 81 }
    private static var maximumNitrogenMoleFraction: Double { 0.10 }
    private static var binaryCompositionSumTolerance: Double { 1e-10 }

    private enum SupportedComposition {
        case pureCarbonDioxide
        case carbonDioxideNitrogen(carbonDioxide: Double, nitrogen: Double)
    }

    private struct ResolvedState {
        let densityKilogramsPerCubicMetre: Double
        let dynamicViscosityPascalSeconds: Double?
        let phaseIdentifier: String
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
            providerVersion: "0.4.0",
            availability: engine.isAvailable ? .preliminary : .unavailable,
            calculationMode: .local,
            supportedComponents: engine.isAvailable ? [.carbonDioxide, .nitrogen] : [],
            supportedProperties: engine.isAvailable ? [.density, .dynamicViscosity] : [],
            domain: .initialCO2Transport,
            scientificBasis: "CoolProp HEOS pure-fluid CO₂ and restricted CO₂-N₂ binary mixture backend.",
            equationOrMethod: "CoolProp HEOS; the CO₂-N₂ pair uses only interaction data shipped by the pinned CoolProp release. No estimated mixing rule is applied.",
            coefficientSetVersion: engine.libraryVersion,
            requiredResources: ["PhaseXpertCoolPropBridge.xcframework"],
            limitations: [
                "Pure CO₂ supports density and dynamic viscosity.",
                "CO₂-N₂ is restricted to density and phase with 0 < N₂ ≤ 10 mol%; this is an implementation test cap, not a validated accuracy range.",
                "Preliminary integration; no production accuracy claim.",
                "CO₂-N₂ dynamic viscosity is unavailable pending separate validation.",
                "The phase diagram remains a pure-CO₂ saturation boundary; mixture phase envelopes are not enabled."
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
                )
            ]
        )
    }

    public func applicabilityIssues(
        for composition: [MixtureComponent]
    ) -> [ValidationIssue] {
        let nitrogenFraction = composition
            .filter { $0.component == .nitrogen && $0.moleFraction.isFinite }
            .reduce(0) { $0 + $1.moleFraction }

        var issues: [ValidationIssue] = []
        if nitrogenFraction > Self.maximumNitrogenMoleFraction {
            issues.append(
                ValidationIssue(
                    code: .componentOutsideModelRange,
                    severity: .error,
                    message: "The preliminary CO₂-N₂ spike is limited to at most 10 mol% N₂. This temporary cap is not a validated accuracy range."
                )
            )
        }

        let total = composition.reduce(0) { $0 + $1.moleFraction }
        let deviation = abs(total - 1)
        if
            nitrogenFraction > CalculationValidator.compositionTolerance,
            total.isFinite,
            deviation > Self.binaryCompositionSumTolerance,
            deviation <= CalculationValidator.compositionTolerance
        {
            issues.append(
                ValidationIssue(
                    code: .compositionTotal,
                    severity: .error,
                    message: "CO₂-N₂ mole fractions must sum to 100 mol% without implicit native normalization. Adjust the entered values explicitly."
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
                solverMethod: "CoolProp PropsSI(P,T), HEOS pure CO₂",
                warnings: []
            )
        case let .carbonDioxideNitrogen(carbonDioxide, nitrogen):
            let raw = try await engine.calculateCarbonDioxideNitrogen(
                pressurePa: request.pressurePa,
                temperatureK: request.temperatureK,
                carbonDioxideMoleFraction: carbonDioxide,
                nitrogenMoleFraction: nitrogen
            )
            state = ResolvedState(
                densityKilogramsPerCubicMetre: raw.densityKilogramsPerCubicMetre,
                dynamicViscosityPascalSeconds: nil,
                phaseIdentifier: raw.phaseIdentifier,
                solverMethod: "CoolProp PropsSI(P,T), HEOS CO₂-N₂ binary; pinned library interaction data only",
                warnings: [
                    "CO₂-N₂ MIXTURE SPIKE: density and phase have not completed independent validation.",
                    "Mixture dynamic viscosity and mixture phase envelopes are not enabled."
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

        let values = request.requestedProperties
            .sorted { $0.rawValue < $1.rawValue }
            .map { propertyValue(for: $0, state: state) }

        return CalculationResponse(
            requestID: request.requestID,
            model: descriptor,
            phase: phaseRegion(for: state.phaseIdentifier),
            properties: values,
            solver: SolverMetadata(
                method: state.solverMethod,
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
                warning: "Pure CO₂ saturation boundary unavailable because CoolProp is not linked."
            )
        }
        guard request.modelID == descriptor.id else {
            throw ProviderError.invalidRequest(
                "The phase-envelope request model ID does not match CoolProp."
            )
        }
        guard isPureCarbonDioxide(request.composition) else {
            return unavailableEnvelope(
                requestID: request.requestID,
                warning: "Mixture phase envelopes are not enabled in the CO₂-N₂ spike; the phase diagram supports exactly 100 mol% CO₂ only."
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
            throw ProviderError.invalidRequest(
                "Each component may appear only once."
            )
        }
        let total = composition.reduce(0) { $0 + $1.moleFraction }
        guard abs(total - 1) <= CalculationValidator.compositionTolerance else {
            throw ProviderError.invalidRequest(
                "Composition must total 100 mol% before CoolProp calculation."
            )
        }

        let active = composition.filter {
            $0.moleFraction > CalculationValidator.compositionTolerance
        }
        if isPureCarbonDioxide(active) {
            return .pureCarbonDioxide
        }
        guard
            active.count == 2,
            let carbonDioxide = active.first(where: { $0.component == .carbonDioxide }),
            let nitrogen = active.first(where: { $0.component == .nitrogen })
        else {
            let unsupported = active.first {
                $0.component != .carbonDioxide && $0.component != .nitrogen
            }
            if let unsupported {
                throw ProviderError.unsupportedComponent(unsupported.component)
            }
            throw ProviderError.invalidRequest(
                "The preliminary CoolProp provider accepts pure CO₂ or the restricted CO₂-N₂ binary only."
            )
        }
        guard abs(
            carbonDioxide.moleFraction + nitrogen.moleFraction - 1
        ) <= Self.binaryCompositionSumTolerance else {
            throw ProviderError.invalidRequest(
                "CO₂-N₂ mole fractions must sum to 100 mol% without implicit normalization."
            )
        }
        guard carbonDioxide.moleFraction > nitrogen.moleFraction else {
            throw ProviderError.invalidRequest(
                "CO₂ must be the unique largest component."
            )
        }
        guard nitrogen.moleFraction <= Self.maximumNitrogenMoleFraction else {
            throw ProviderError.invalidRequest(
                "The CO₂-N₂ spike is temporarily limited to at most 10 mol% N₂."
            )
        }
        return .carbonDioxideNitrogen(
            carbonDioxide: carbonDioxide.moleFraction,
            nitrogen: nitrogen.moleFraction
        )
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
                PropertyValue(
                    property: property,
                    value: nil,
                    unit: "Pa·s",
                    status: .unavailable,
                    message: "CO₂-N₂ dynamic viscosity is not enabled pending independent validation."
                )
            }
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
