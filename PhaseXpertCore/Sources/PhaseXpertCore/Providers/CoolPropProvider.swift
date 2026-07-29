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
}

/// Preliminary established-model provider restricted to pure CO₂.
///
/// Availability does not imply scientific validation. Every successful result
/// carries an explicit validation-pending warning.
public struct CoolPropProvider<Engine: CoolPropEngine>: ThermodynamicModelProvider {
    private let engine: Engine

    public init(engine: Engine) {
        self.engine = engine
    }

    public var descriptor: ModelDescriptor {
        ModelDescriptor(
            id: "coolprop-heos",
            name: "CoolProp HEOS — Preliminary",
            modelVersion: engine.libraryVersion,
            providerVersion: "0.2.0",
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
                "Phase-envelope calculation is not enabled.",
                "Mixtures remain disabled pending pair-specific validation."
            ],
            references: [
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
        return PhaseEnvelopeResponse(
            requestID: request.requestID,
            points: [],
            warnings: [
                "Phase envelope unavailable in the pure-CO₂ CoolProp integration spike."
            ],
            isAvailable: false
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
