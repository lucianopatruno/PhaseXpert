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

    func pureCarbonDioxideSaturationLimits() async throws -> CoolPropSaturationLimits

    func pureCarbonDioxideSaturationPressure(
        temperatureK: Double
    ) async throws -> Double
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

/// Preliminary established-model provider restricted to pure CO₂.
///
/// Availability does not imply scientific validation. Every successful result
/// carries an explicit validation-pending warning.
public struct CoolPropProvider<Engine: CoolPropEngine>: ThermodynamicModelProvider {
    private let engine: Engine
    private let envelopeCache: PureCarbonDioxideEnvelopeCache

    private static var saturationPointCount: Int { 81 }

    public init(engine: Engine) {
        self.engine = engine
        self.envelopeCache = PureCarbonDioxideEnvelopeCache()
    }

    public var descriptor: ModelDescriptor {
        ModelDescriptor(
            id: "coolprop-heos",
            name: "CoolProp HEOS — Preliminary",
            modelVersion: engine.libraryVersion,
            providerVersion: "0.3.0",
            availability: engine.isAvailable ? .preliminary : .unavailable,
            calculationMode: .local,
            supportedComponents: engine.isAvailable ? [.carbonDioxide] : [],
            supportedProperties: engine.isAvailable ? [.density, .dynamicViscosity] : [],
            domain: .initialCO2Transport,
            scientificBasis: "CoolProp HEOS pure-fluid backend for carbon dioxide.",
            equationOrMethod: "CoolProp HEOS; formulation and transport correlations selected by the pinned CoolProp release.",
            coefficientSetVersion: engine.libraryVersion,
            requiredResources: ["PhaseXpertCoolPropBridge.xcframework"],
            limitations: [
                "Pure CO₂ only in this spike.",
                "Preliminary integration; no production accuracy claim.",
                "The phase diagram is a pure-fluid saturation boundary, not a mixture phase envelope.",
                "Mixtures remain disabled pending pair-specific validation."
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
                )
            ]
        )
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
        guard
            request.composition.count == 1,
            let carbonDioxide = request.composition.first,
            carbonDioxide.component == .carbonDioxide,
            abs(carbonDioxide.moleFraction - 1) <= CalculationValidator.compositionTolerance
        else {
            throw ProviderError.invalidRequest(
                "The CoolProp spike accepts pure CO₂ only."
            )
        }

        let startedAt = Date()
        let raw = try await engine.calculatePureCarbonDioxide(
            pressurePa: request.pressurePa,
            temperatureK: request.temperatureK
        )
        try Task.checkCancellation()

        guard
            raw.densityKilogramsPerCubicMetre.isFinite,
            raw.densityKilogramsPerCubicMetre > 0,
            raw.dynamicViscosityPascalSeconds.isFinite,
            raw.dynamicViscosityPascalSeconds > 0
        else {
            throw ProviderError.malformedResponse(
                "CoolProp returned a non-finite or non-positive property."
            )
        }

        let values = request.requestedProperties
            .sorted { $0.rawValue < $1.rawValue }
            .map { propertyValue(for: $0, raw: raw) }

        return CalculationResponse(
            requestID: request.requestID,
            model: descriptor,
            phase: phaseRegion(for: raw.phaseIdentifier),
            properties: values,
            solver: SolverMetadata(
                method: "CoolProp PropsSI(P,T), HEOS pure CO₂",
                converged: true,
                durationMilliseconds: Date().timeIntervalSince(startedAt) * 1_000
            ),
            warnings: [
                "PRELIMINARY — VALIDATION PENDING: do not use this result for engineering, safety, commercial, or regulatory decisions."
            ],
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
                warning: "The preliminary CoolProp phase diagram supports exactly 100 mol% CO₂ only."
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
        raw: CoolPropEngineResult
    ) -> PropertyValue {
        switch property {
        case .density:
            PropertyValue(
                property: property,
                value: raw.densityKilogramsPerCubicMetre,
                unit: "kg/m³",
                status: .calculated
            )
        case .dynamicViscosity:
            PropertyValue(
                property: property,
                value: raw.dynamicViscosityPascalSeconds,
                unit: "Pa·s",
                status: .calculated
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
