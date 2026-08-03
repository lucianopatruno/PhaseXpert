import Foundation

public struct ThermoPackStateResult: Equatable, Sendable {
    public enum Phase: String, Equatable, Sendable {
        case liquid
        case vapor
        case twoPhase
        case unknown
    }

    public let phase: Phase
    public let densityKilogramsPerCubicMetre: Double?
    public let molarMassKilogramsPerMole: Double?
    public let specificVolumeCubicMetresPerKilogram: Double?
    public let compressibilityFactor: Double?
    public let enthalpyJoulesPerKilogram: Double?
    public let entropyJoulesPerKilogramKelvin: Double?
    public let isobaricHeatCapacityJoulesPerKilogramKelvin: Double?
    public let vaporFraction: Double?

    public init(
        phase: Phase,
        densityKilogramsPerCubicMetre: Double? = nil,
        molarMassKilogramsPerMole: Double? = nil,
        specificVolumeCubicMetresPerKilogram: Double? = nil,
        compressibilityFactor: Double? = nil,
        enthalpyJoulesPerKilogram: Double? = nil,
        entropyJoulesPerKilogramKelvin: Double? = nil,
        isobaricHeatCapacityJoulesPerKilogramKelvin: Double? = nil,
        vaporFraction: Double? = nil
    ) {
        self.phase = phase
        self.densityKilogramsPerCubicMetre = densityKilogramsPerCubicMetre
        self.molarMassKilogramsPerMole = molarMassKilogramsPerMole
        self.specificVolumeCubicMetresPerKilogram = specificVolumeCubicMetresPerKilogram
        self.compressibilityFactor = compressibilityFactor
        self.enthalpyJoulesPerKilogram = enthalpyJoulesPerKilogram
        self.entropyJoulesPerKilogramKelvin = entropyJoulesPerKilogramKelvin
        self.isobaricHeatCapacityJoulesPerKilogramKelvin =
            isobaricHeatCapacityJoulesPerKilogramKelvin
        self.vaporFraction = vaporFraction
    }
}

public struct ThermoPackEnvelopeResult: Equatable, Sendable {
    public let points: [PhaseEnvelopePoint]
    public let attemptedCalls: Int
    public let failedCalls: Int
    public let complete: Bool
    public let timedOut: Bool
    public let durationMilliseconds: Double

    public init(
        points: [PhaseEnvelopePoint],
        attemptedCalls: Int,
        failedCalls: Int,
        complete: Bool,
        timedOut: Bool,
        durationMilliseconds: Double
    ) {
        self.points = points
        self.attemptedCalls = attemptedCalls
        self.failedCalls = failedCalls
        self.complete = complete
        self.timedOut = timedOut
        self.durationMilliseconds = durationMilliseconds
    }
}

public protocol ThermoPackEngine: Sendable {
    var isAvailable: Bool { get }
    var libraryVersion: String { get }
    var bridgeVersion: String { get }
    var configurationIdentifier: String { get }

    func calculate(
        pressurePa: Double,
        temperatureK: Double,
        carbonDioxideMoleFraction: Double,
        nitrogenMoleFraction: Double
    ) async throws -> ThermoPackStateResult

    func phaseEnvelope(
        carbonDioxideMoleFraction: Double,
        nitrogenMoleFraction: Double,
        bounds: ScientificDomain,
        maximumPointsPerBranch: Int,
        maximumElapsedMilliseconds: Double
    ) async throws -> ThermoPackEnvelopeResult
}

public struct UnavailableThermoPackEngine: ThermoPackEngine {
    public let isAvailable = false
    public let libraryVersion = "Not linked"
    public let bridgeVersion = "1.0.0"
    public let configurationIdentifier =
        "PR / Classic alpha / Classic-vdW mixing / PR_kij.json vdW-18 ref=Default"

    public init() {}

    public func calculate(
        pressurePa: Double,
        temperatureK: Double,
        carbonDioxideMoleFraction: Double,
        nitrogenMoleFraction: Double
    ) async throws -> ThermoPackStateResult {
        throw ProviderError.modelUnavailable(
            "The ThermoPack native XCFramework has not been linked."
        )
    }

    public func phaseEnvelope(
        carbonDioxideMoleFraction: Double,
        nitrogenMoleFraction: Double,
        bounds: ScientificDomain,
        maximumPointsPerBranch: Int,
        maximumElapsedMilliseconds: Double
    ) async throws -> ThermoPackEnvelopeResult {
        throw ProviderError.modelUnavailable(
            "The ThermoPack native XCFramework has not been linked."
        )
    }
}

public struct ThermoPackProvider<Engine: ThermoPackEngine>: ThermodynamicModelProvider {
    public static var providerCapabilityVersion: String { "1.0.0" }
    public static var maximumNitrogenMoleFraction: Double { 0.10 }
    public static var compositionSumTolerance: Double { 1e-10 }
    public static var maximumEnvelopePointsPerBranch: Int { 64 }
    public static var maximumEnvelopeElapsedMilliseconds: Double { 5_000 }

    private let engine: Engine

    public init(engine: Engine) {
        self.engine = engine
    }

    public var descriptor: ModelDescriptor {
        ModelDescriptor(
            id: "thermopack-pr-classic-co2-n2",
            name: "ThermoPack PR / Classic vdW — Preliminary",
            modelVersion: "ThermoPack \(engine.libraryVersion); Peng–Robinson",
            providerVersion: Self.providerCapabilityVersion,
            availability: engine.isAvailable ? .preliminary : .unavailable,
            calculationMode: .local,
            supportedComponents: engine.isAvailable ? [.carbonDioxide, .nitrogen] : [],
            supportedProperties: engine.isAvailable ? [
                .density, .molarMass, .specificVolume, .compressibilityFactor,
                .enthalpy, .entropy, .isobaricHeatCapacity, .vapourFraction
            ] : [],
            domain: .initialCO2Transport,
            scientificBasis:
                "ThermoPack v2.2.4 cubic Peng–Robinson equation of state for CO₂/N₂.",
            equationOrMethod:
                "Peng–Robinson cubic EOS; Classic alpha; Classic van der Waals one-fluid mixing; "
                + "TP flash and independent bubble/dew pressure calls from ThermoPack's ISO C API.",
            coefficientSetVersion:
                "ThermoPack PR_kij.json vdW-18, CO2/N2, ref=Default; source "
                + "ca75d8e095e8b951616897efe1bca9b8c3badda7; bridge "
                + engine.bridgeVersion,
            requiredResources: ["PhaseXpertThermoPackBridge.xcframework"],
            limitations: [
                "Only pure CO₂ and 90–100 mol% CO₂ / 0–10 mol% N₂ are enabled.",
                "The 10 mol% N₂ limit is a PhaseXpert product guardrail, not a validated accuracy range.",
                "The shipped ThermoPack Default CO₂/N₂ interaction record is used unchanged; PhaseXpert supplies no interaction parameter.",
                "ThermoPack results are independent and never filled with CoolProp values.",
                "Transport, Cv, speed of sound, conductivity, Joule–Thomson coefficient, expansion coefficient and isothermal compressibility are unavailable in this bridge.",
                "Single-phase state properties are not reported for a two-phase flash; only phase and provider vapor fraction are retained.",
                "The v2.2.4 ISO C TP-flash entry point has no explicit error-code argument; malformed or non-finite outputs are rejected by the bridge.",
                "Native iOS compilation, static-runtime inspection and numerical smoke validation remain pending."
            ],
            references: [
                SourceReference(
                    authors: "ThermoPack developers, SINTEF Energy Research and NTNU",
                    title: "ThermoPack v2.2.4 source and documentation",
                    year: 2024,
                    doiOrURL: "https://github.com/thermotools/thermopack/tree/v2.2.4"
                ),
                SourceReference(
                    authors: "Wilhelmsen, Aasen, Skaugen, Aursand, Austegard and Aursand",
                    title: "Thermodynamic Modeling with Equations of State: Present Challenges with Established Methods",
                    year: 2017,
                    doiOrURL: "https://doi.org/10.1021/acs.iecr.7b00317"
                ),
                SourceReference(
                    authors: "Peng and Robinson",
                    title: "A New Two-Constant Equation of State",
                    year: 1976,
                    doiOrURL: "https://doi.org/10.1021/i160057a011"
                )
            ]
        )
    }

    public func applicabilityIssues(
        for composition: [MixtureComponent]
    ) -> [ValidationIssue] {
        let nitrogen = composition.first(where: { $0.component == .nitrogen })?
            .moleFraction ?? 0
        if nitrogen > Self.maximumNitrogenMoleFraction {
            return [
                ValidationIssue(
                    code: .componentOutsideModelRange,
                    severity: .error,
                    message:
                        "The ThermoPack PR milestone is limited to at most 10 mol% N₂. "
                        + "This is not a validated accuracy range."
                )
            ]
        }
        return []
    }

    public func calculate(_ request: CalculationRequest) async throws -> CalculationResponse {
        try Task.checkCancellation()
        guard engine.isAvailable else {
            throw ProviderError.modelUnavailable(
                "ThermoPack is not available in this build."
            )
        }
        guard request.modelID == descriptor.id else {
            throw ProviderError.invalidRequest(
                "The request model ID does not match the ThermoPack provider."
            )
        }
        try validateState(request)
        let fractions = try supportedFractions(request.composition)
        let started = Date()
        let raw = try await engine.calculate(
            pressurePa: request.pressurePa,
            temperatureK: request.temperatureK,
            carbonDioxideMoleFraction: fractions.co2,
            nitrogenMoleFraction: fractions.n2
        )
        try Task.checkCancellation()

        let properties = request.requestedProperties
            .sorted { $0.rawValue < $1.rawValue }
            .map { property($0, from: raw) }
        return CalculationResponse(
            requestID: request.requestID,
            model: descriptor,
            phase: phase(raw.phase),
            properties: properties,
            solver: SolverMetadata(
                method:
                    "ThermoPack TP flash; PR / Classic alpha / Classic-vdW mixing; "
                    + "PR_kij.json vdW-18 ref=Default",
                converged: true,
                durationMilliseconds: Date().timeIntervalSince(started) * 1_000
            ),
            warnings: [
                "PRELIMINARY — VALIDATION PENDING: ThermoPack outputs have not completed independent PhaseXpert validation.",
                "This result was calculated only by ThermoPack; no CoolProp value or fallback was used.",
                "Model differences in saved-case comparison do not establish accuracy."
            ],
            isScientificResult: true
        )
    }

    public func phaseEnvelope(
        _ request: PhaseEnvelopeRequest
    ) async throws -> PhaseEnvelopeResponse {
        try Task.checkCancellation()
        guard engine.isAvailable else {
            throw ProviderError.modelUnavailable(
                "ThermoPack is not available in this build."
            )
        }
        guard request.modelID == descriptor.id else {
            throw ProviderError.invalidRequest(
                "The phase-envelope model ID does not match ThermoPack."
            )
        }
        let fractions = try supportedFractions(request.composition)
        let result = try await engine.phaseEnvelope(
            carbonDioxideMoleFraction: fractions.co2,
            nitrogenMoleFraction: fractions.n2,
            bounds: descriptor.domain,
            maximumPointsPerBranch: Self.maximumEnvelopePointsPerBranch,
            maximumElapsedMilliseconds: Self.maximumEnvelopeElapsedMilliseconds
        )
        try Task.checkCancellation()

        let finite = result.points.filter {
            $0.temperatureK.isFinite && $0.temperatureK > 0
                && $0.pressurePa.isFinite && $0.pressurePa > 0
        }
        let bubbleCount = finite.filter { $0.branch == .bubble }.count
        let dewCount = finite.filter { $0.branch == .dew }.count
        guard bubbleCount >= 2, dewCount >= 2 else {
            return PhaseEnvelopeResponse(
                requestID: request.requestID,
                points: [],
                warnings: [
                    "ThermoPack did not return at least two finite provider points on each bubble/dew branch. No diagram is displayed."
                ],
                isAvailable: false,
                boundaryKind: fractions.n2 == 0 ? .pureFluidSaturation : .mixtureEnvelope,
                model: descriptor,
                generatedAt: Date(),
                solver: SolverMetadata(
                    method: envelopeMethod(result),
                    converged: false,
                    iterationCount: result.attemptedCalls,
                    durationMilliseconds: result.durationMilliseconds
                )
            )
        }

        var warnings = [
            "PRELIMINARY — VALIDATION PENDING: this ThermoPack boundary must not be used for engineering decisions.",
            "Bubble and dew points are direct ThermoPack bubble/dew-pressure results. Straight chart segments are display-only connections between adjacent provider points.",
            "No CoolProp trace, workaround, interpolation, extrapolation or estimated scientific point is used."
        ]
        if !result.complete {
            warnings.append(
                "The provider branches are incomplete; only returned finite points are shown."
            )
        }
        if result.timedOut {
            warnings.append(
                "The explicit \(Int(Self.maximumEnvelopeElapsedMilliseconds)) ms native elapsed-time bound was reached."
            )
        }
        if result.failedCalls > 0 {
            warnings.append(
                "\(result.failedCalls) of \(result.attemptedCalls) bounded bubble/dew calls failed or returned no in-domain finite point."
            )
        }
        return PhaseEnvelopeResponse(
            requestID: request.requestID,
            points: finite,
            warnings: warnings,
            isAvailable: true,
            boundaryKind: fractions.n2 == 0 ? .pureFluidSaturation : .mixtureEnvelope,
            model: descriptor,
            generatedAt: Date(),
            solver: SolverMetadata(
                method: envelopeMethod(result),
                converged: result.complete && !result.timedOut && result.failedCalls == 0,
                iterationCount: result.attemptedCalls,
                durationMilliseconds: result.durationMilliseconds
            )
        )
    }

    private func envelopeMethod(_ result: ThermoPackEnvelopeResult) -> String {
        "ThermoPack bubP/dewP; maximum \(Self.maximumEnvelopePointsPerBranch) calls per branch; "
            + "\(Int(Self.maximumEnvelopeElapsedMilliseconds)) ms elapsed bound; "
            + "attempted \(result.attemptedCalls), failed \(result.failedCalls)"
    }

    private func validateState(_ request: CalculationRequest) throws {
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
                "The state is outside the declared PhaseXpert ThermoPack domain."
            )
        }
    }

    private func supportedFractions(
        _ composition: [MixtureComponent]
    ) throws -> (co2: Double, n2: Double) {
        guard !composition.isEmpty else {
            throw ProviderError.invalidRequest("Composition cannot be empty.")
        }
        guard composition.allSatisfy({
            $0.moleFraction.isFinite && $0.moleFraction >= 0
        }) else {
            throw ProviderError.invalidRequest(
                "Composition values must be finite and non-negative."
            )
        }
        let grouped = Dictionary(grouping: composition, by: \.component)
        guard grouped.values.allSatisfy({ $0.count == 1 }) else {
            throw ProviderError.invalidRequest("Each component may appear only once.")
        }
        if let unsupported = composition.first(where: {
            $0.moleFraction > 0
                && $0.component != .carbonDioxide
                && $0.component != .nitrogen
        }) {
            throw ProviderError.unsupportedComponent(unsupported.component)
        }
        let co2 = composition.first(where: { $0.component == .carbonDioxide })?
            .moleFraction ?? 0
        let n2 = composition.first(where: { $0.component == .nitrogen })?
            .moleFraction ?? 0
        guard abs(co2 + n2 - 1) <= Self.compositionSumTolerance else {
            throw ProviderError.invalidRequest(
                "ThermoPack mole fractions must sum to one without implicit normalization."
            )
        }
        guard co2 >= 0.90, n2 >= 0, n2 <= Self.maximumNitrogenMoleFraction else {
            throw ProviderError.invalidRequest(
                "ThermoPack PR supports 90–100 mol% CO₂ and 0–10 mol% N₂ in this milestone."
            )
        }
        return (co2, n2)
    }

    private func phase(_ value: ThermoPackStateResult.Phase) -> PhaseRegion {
        switch value {
        case .liquid: .liquid
        case .vapor: .gas
        case .twoPhase: .twoPhase
        case .unknown: .unknown
        }
    }

    private func property(
        _ id: PropertyID,
        from state: ThermoPackStateResult
    ) -> PropertyValue {
        if state.phase == .twoPhase && id != .vapourFraction {
            return PropertyValue(
                property: id,
                value: nil,
                unit: unit(for: id),
                status: .unavailable,
                message:
                    "ThermoPack reported a two-phase flash; this bridge does not construct a bulk two-phase value for this property."
            )
        }
        let resolved: (value: Double?, unit: String, requiresPositive: Bool)
        switch id {
        case .density:
            resolved = (state.densityKilogramsPerCubicMetre, "kg/m³", true)
        case .molarMass:
            resolved = (
                state.molarMassKilogramsPerMole.map { $0 * 1_000 }, "g/mol", true
            )
        case .specificVolume:
            resolved = (
                state.specificVolumeCubicMetresPerKilogram, "m³/kg", true
            )
        case .compressibilityFactor:
            resolved = (state.compressibilityFactor, "1", true)
        case .enthalpy:
            resolved = (state.enthalpyJoulesPerKilogram, "J/kg", false)
        case .entropy:
            resolved = (
                state.entropyJoulesPerKilogramKelvin, "J/(kg·K)", false
            )
        case .isobaricHeatCapacity:
            resolved = (
                state.isobaricHeatCapacityJoulesPerKilogramKelvin, "J/(kg·K)", true
            )
        case .vapourFraction:
            resolved = (state.vaporFraction, "mol/mol", false)
        default:
            return PropertyValue(
                property: id,
                value: nil,
                unit: unit(for: id),
                status: .unavailable,
                message:
                    "The pinned ThermoPack PR bridge does not expose this property; no CoolProp value is substituted."
            )
        }
        guard let raw = resolved.value else {
            return PropertyValue(
                property: id,
                value: nil,
                unit: resolved.unit,
                status: .unavailable,
                message: "ThermoPack did not return this property for the resolved state."
            )
        }
        guard raw.isFinite, !resolved.requiresPositive || raw > 0 else {
            return PropertyValue(
                property: id,
                value: nil,
                unit: resolved.unit,
                status: .failed,
                message: "ThermoPack returned a non-finite or non-physical value."
            )
        }
        return PropertyValue(
            property: id,
            value: raw,
            unit: resolved.unit,
            status: .calculated,
            message: "Returned by the pinned ThermoPack PR configuration."
        )
    }

    private func unit(for id: PropertyID) -> String {
        switch id {
        case .density: "kg/m³"
        case .dynamicViscosity: "Pa·s"
        case .molarMass: "g/mol"
        case .compressibilityFactor: "1"
        case .specificVolume: "m³/kg"
        case .enthalpy, .internalEnergy: "J/kg"
        case .entropy, .isobaricHeatCapacity, .isochoricHeatCapacity: "J/(kg·K)"
        case .heatCapacityRatio: "1"
        case .speedOfSound: "m/s"
        case .thermalConductivity: "W/(m·K)"
        case .jouleThomsonCoefficient: "°C/bar"
        case .isothermalCompressibility: "1/Pa"
        case .thermalExpansionCoefficient: "1/K"
        case .vapourFraction: "mol/mol"
        }
    }
}
