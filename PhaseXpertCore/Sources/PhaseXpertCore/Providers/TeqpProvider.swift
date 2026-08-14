import Foundation

public struct TeqpEngineResult: Equatable, Sendable {
    public let densityKilogramsPerCubicMetre: Double
    public let isochoricHeatCapacityJoulesPerKilogramKelvin: Double?
    public let isobaricHeatCapacityJoulesPerKilogramKelvin: Double?
    public let heatCapacityRatio: Double?
    public let speedOfSoundMetresPerSecond: Double?
    public let densityRootCount: Int
    public let phaseIdentifier: String

    public init(
        densityKilogramsPerCubicMetre: Double,
        isochoricHeatCapacityJoulesPerKilogramKelvin: Double? = nil,
        isobaricHeatCapacityJoulesPerKilogramKelvin: Double? = nil,
        heatCapacityRatio: Double? = nil,
        speedOfSoundMetresPerSecond: Double? = nil,
        densityRootCount: Int,
        phaseIdentifier: String
    ) {
        self.densityKilogramsPerCubicMetre = densityKilogramsPerCubicMetre
        self.isochoricHeatCapacityJoulesPerKilogramKelvin =
            isochoricHeatCapacityJoulesPerKilogramKelvin
        self.isobaricHeatCapacityJoulesPerKilogramKelvin =
            isobaricHeatCapacityJoulesPerKilogramKelvin
        self.heatCapacityRatio = heatCapacityRatio
        self.speedOfSoundMetresPerSecond = speedOfSoundMetresPerSecond
        self.densityRootCount = densityRootCount
        self.phaseIdentifier = phaseIdentifier
    }
}

public struct TeqpSaturationPoint: Equatable, Sendable {
    public let temperatureK: Double
    public let pressurePa: Double
    public let liquidDensityKilogramsPerCubicMetre: Double
    public let vaporDensityKilogramsPerCubicMetre: Double

    public init(
        temperatureK: Double,
        pressurePa: Double,
        liquidDensityKilogramsPerCubicMetre: Double,
        vaporDensityKilogramsPerCubicMetre: Double
    ) {
        self.temperatureK = temperatureK
        self.pressurePa = pressurePa
        self.liquidDensityKilogramsPerCubicMetre = liquidDensityKilogramsPerCubicMetre
        self.vaporDensityKilogramsPerCubicMetre = vaporDensityKilogramsPerCubicMetre
    }
}

public struct TeqpMixtureDensityResult: Equatable, Sendable {
    public let densityKilogramsPerCubicMetre: Double
    public let molarDensityMolesPerCubicMetre: Double
    public let densityRootCount: Int
    public let phaseIdentifier: String
    public let formulationID: String

    public init(
        densityKilogramsPerCubicMetre: Double,
        molarDensityMolesPerCubicMetre: Double,
        densityRootCount: Int,
        phaseIdentifier: String,
        formulationID: String
    ) {
        self.densityKilogramsPerCubicMetre = densityKilogramsPerCubicMetre
        self.molarDensityMolesPerCubicMetre = molarDensityMolesPerCubicMetre
        self.densityRootCount = densityRootCount
        self.phaseIdentifier = phaseIdentifier
        self.formulationID = formulationID
    }
}

public protocol TeqpEngine: Sendable {
    var isAvailable: Bool { get }
    var libraryVersion: String { get }

    func calculatePureCarbonDioxide(
        pressurePa: Double,
        temperatureK: Double
    ) async throws -> TeqpEngineResult

    func pureCarbonDioxideSaturation(
        temperatureK: Double
    ) async throws -> TeqpSaturationPoint

    func calculateCarbonDioxideHydrogenGasDensity(
        pressurePa: Double,
        temperatureK: Double,
        hydrogenMoleFraction: Double
    ) async throws -> TeqpMixtureDensityResult
}

public struct UnavailableTeqpEngine: TeqpEngine {
    public let isAvailable = false
    public let libraryVersion = "Not linked"

    public init() {}

    public func calculatePureCarbonDioxide(
        pressurePa: Double,
        temperatureK: Double
    ) async throws -> TeqpEngineResult {
        throw ProviderError.modelUnavailable(
            "The teqp native XCFramework has not been linked."
        )
    }

    public func pureCarbonDioxideSaturation(
        temperatureK: Double
    ) async throws -> TeqpSaturationPoint {
        throw ProviderError.modelUnavailable(
            "The teqp native XCFramework has not been linked."
        )
    }

    public func calculateCarbonDioxideHydrogenGasDensity(
        pressurePa: Double,
        temperatureK: Double,
        hydrogenMoleFraction: Double
    ) async throws -> TeqpMixtureDensityResult {
        throw ProviderError.modelUnavailable(
            "The teqp native XCFramework has not been linked."
        )
    }
}

public struct TeqpProvider<Engine: TeqpEngine>: ThermodynamicModelProvider {
    private let engine: Engine

    public init(engine: Engine) {
        self.engine = engine
    }

    public var descriptor: ModelDescriptor {
        ModelDescriptor(
            id: "teqp-pure-co2-experimental",
            name: engine.isAvailable
                ? "Advanced CCS Properties"
                : "Advanced CO₂ & Phase Model (teqp)",
            modelVersion: engine.libraryVersion,
            providerVersion: "0.1.0",
            availability: engine.isAvailable ? .preliminary : .unavailable,
            calculationMode: .local,
            supportedComponents: engine.isAvailable
                ? TeqpFormulationCatalog.productionSupportedComponents
                : [],
            supportedProperties: engine.isAvailable
                ? TeqpFormulationCatalog.productionSupportedProperties
                : [],
            domain: .initialCO2Transport,
            scientificBasis: "Native teqp Helmholtz engine with validation-gated pure CO₂ and property-specific CCS mixture formulations.",
            equationOrMethod: "Pure CO₂ uses the pinned upstream CarbonDioxide.json multifluid model. CO₂+H₂ homogeneous gas density uses EOS-CG-2021 Table 4/5 model data at the exact Souissi et al. 2017 validation composition and isotherms. Unsupported properties and domains do not fall back to CoolProp.",
            coefficientSetVersion: TeqpFormulationCatalog.pureCarbonDioxide.provenance,
            requiredResources: ["PhaseXpertTeqpBridge.xcframework"],
            limitations: [
                "Experimental local provider; no production accuracy claim.",
                "Pure CO₂ is supported for density, Cv, Cp, Cp/Cv, speed of sound and pure saturation.",
                "CO₂+H₂ is supported only for homogeneous gas density at xH₂ = 0.05362, on the validated 273.15 K, 293.15 K and 323.15 K isotherms, within the observed gas-pressure ranges.",
                "N₂, O₂, Ar, CH₄ and simultaneous impurity mixtures remain unsupported and never fall back to CoolProp.",
                "Dynamic viscosity and all transport properties are unavailable for this provider.",
                "Subcritical states on or too close to pure-CO₂ saturation are reported as unavailable because they do not have a unique homogeneous bulk density.",
                "Phase classification is limited to stable vapor, stable liquid, and supercritical states that the bridge can identify robustly; otherwise the phase remains unknown.",
                "Pure-CO₂ phase-envelope generation is available; impurity phase envelopes remain validation-gated and unavailable.",
                "Pure-CO₂ Cv, Cp and speed of sound are calculated from complete teqp ideal-gas plus residual Helmholtz derivatives; mixture Cv, Cp and speed of sound remain unavailable pending validation.",
                "Absolute h, u and s remain unavailable pending reference-state validation."
            ],
            references: [
                SourceReference(
                    authors: "Bell and Deiters",
                    title: "Helmholtz energy transformations of common cubic equations of state for use with pure fluids and mixtures",
                    year: 2021,
                    doiOrURL: "https://doi.org/10.1021/acs.iecr.1c00847"
                ),
                SourceReference(
                    authors: "Span and Wagner",
                    title: "A New Equation of State for Carbon Dioxide Covering the Fluid Region from the Triple-Point Temperature to 1100 K at Pressures up to 800 MPa",
                    year: 1996,
                    doiOrURL: "https://doi.org/10.1063/1.555991"
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
    }

    public func applicabilityIssues(
        for composition: [MixtureComponent]
    ) -> [ValidationIssue] {
        guard !isPureCarbonDioxide(composition) else { return [] }
        if isSupportedHydrogenGasComposition(composition) {
            return []
        }
        return [
            ValidationIssue(
                code: .componentOutsideModelRange,
                severity: .error,
                message: "Advanced CCS Properties supports pure CO₂ and a narrow CO₂+H₂ homogeneous gas-density validation domain only. This mixture is unsupported and is not routed to CoolProp."
            )
        ]
    }

    public func calculate(_ request: CalculationRequest) async throws -> CalculationResponse {
        try Task.checkCancellation()
        guard engine.isAvailable else {
            throw ProviderError.modelUnavailable("teqp is not available in this build.")
        }
        guard request.modelID == descriptor.id else {
            throw ProviderError.invalidRequest("The request model ID does not match teqp.")
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
                "The state point is outside the experimental teqp domain."
            )
        }
        if isSupportedHydrogenGasComposition(request.composition) {
            return try await calculateHydrogenGasDensity(request)
        }
        guard isPureCarbonDioxide(request.composition) else {
            throw ProviderError.invalidRequest(
                "Advanced CCS Properties supports pure CO₂ and a narrow CO₂+H₂ homogeneous gas-density validation domain only. No CoolProp fallback is used."
            )
        }

        let startedAt = Date()
        let raw = try await engine.calculatePureCarbonDioxide(
            pressurePa: request.pressurePa,
            temperatureK: request.temperatureK
        )
        guard raw.densityKilogramsPerCubicMetre.isFinite,
              raw.densityKilogramsPerCubicMetre > 0
        else {
            throw ProviderError.malformedResponse(
                "teqp returned a non-finite or non-positive density."
            )
        }
        guard raw.densityRootCount >= 1 else {
            throw ProviderError.malformedResponse(
                "teqp did not return a defensible density root."
            )
        }

        let derivedValues = DerivedPropertyCalculator().values(
            requestedProperties: request.requestedProperties,
            pressurePa: request.pressurePa,
            temperatureK: request.temperatureK,
            composition: request.composition,
            densityKilogramsPerCubicMetre: raw.densityKilogramsPerCubicMetre
        )
        let derivedByProperty = Dictionary(
            uniqueKeysWithValues: derivedValues.map { ($0.property, $0) }
        )
        let values = request.requestedProperties
            .sorted { $0.rawValue < $1.rawValue }
            .map { property in
                derivedByProperty[property] ?? propertyValue(for: property, result: raw)
            }
        let derivedMethod = derivedValues.isEmpty
            ? ""
            : "; derived M=ΣxᵢMᵢ, v=1/ρ, Z=pM/(ρRT)"

        return CalculationResponse(
            requestID: request.requestID,
            model: descriptor,
            phase: phaseRegion(for: raw.phaseIdentifier),
            properties: values,
            solver: SolverMetadata(
                method: "teqp pure-CO₂ P,T density solve with teqp pure-fluid VLE stable-branch selection\(derivedMethod)",
                converged: true,
                iterationCount: nil,
                durationMilliseconds: Date().timeIntervalSince(startedAt) * 1_000
            ),
            warnings: [
                "EXPERIMENTAL teqp provider — validation pending: do not use this result for engineering, safety, commercial, or regulatory decisions.",
                "Dynamic viscosity and transport properties are unavailable for teqp in this milestone.",
                "Subcritical multiple-root states use teqp pure-fluid VLE stability selection; states on or too close to saturation remain unavailable."
            ],
            isScientificResult: true
        )
    }

    public func phaseEnvelope(_ request: PhaseEnvelopeRequest) async throws -> PhaseEnvelopeResponse {
        try Task.checkCancellation()
        let startedAt = Date()
        guard engine.isAvailable else {
            return PhaseEnvelopeResponse(
                requestID: request.requestID,
                points: [],
                warnings: [
                    "teqp phase boundary unavailable because the native XCFramework is not linked."
                ],
                isAvailable: false,
                model: descriptor,
                generatedAt: Date(),
                solver: SolverMetadata(
                    method: "No teqp phase-boundary calculation",
                    converged: false,
                    durationMilliseconds: 0
                )
            )
        }
        guard request.modelID == descriptor.id else {
            throw ProviderError.invalidRequest(
                "The phase-envelope request model ID does not match teqp."
            )
        }
        guard isPureCarbonDioxide(request.composition) else {
            throw ProviderError.invalidRequest(
                "The experimental teqp provider supports phase-envelope generation only for exactly 100 mol% CO₂. No CoolProp fallback is used."
            )
        }

        let criticalTemperatureK = 304.1282
        let criticalPressurePa = 7_377_300.0
        let triplePointTemperatureK = 216.592
        let pointCount = 80
        let span = criticalTemperatureK - triplePointTemperatureK
        let endpointOffset = max(span * 1e-6, 1e-4)
        let firstTemperature = triplePointTemperatureK + endpointOffset
        let lastTemperature = criticalTemperatureK - endpointOffset
        let increment = (lastTemperature - firstTemperature)
            / Double(pointCount - 1)

        var points: [PhaseEnvelopePoint] = []
        points.reserveCapacity(pointCount + 1)
        for index in 0..<pointCount {
            try Task.checkCancellation()
            let temperature = firstTemperature + Double(index) * increment
            let saturation = try await engine.pureCarbonDioxideSaturation(
                temperatureK: temperature
            )
            guard saturation.pressurePa.isFinite, saturation.pressurePa > 0 else {
                throw ProviderError.malformedResponse(
                    "teqp returned a non-finite or non-positive saturation pressure."
                )
            }
            guard saturation.liquidDensityKilogramsPerCubicMetre.isFinite,
                  saturation.vaporDensityKilogramsPerCubicMetre.isFinite,
                  saturation.liquidDensityKilogramsPerCubicMetre > saturation.vaporDensityKilogramsPerCubicMetre
            else {
                throw ProviderError.malformedResponse(
                    "teqp returned invalid pure-CO₂ saturation densities."
                )
            }
            guard points.last.map({ saturation.pressurePa > $0.pressurePa }) ?? true else {
                throw ProviderError.malformedResponse(
                    "teqp returned a non-increasing pure-CO₂ saturation boundary."
                )
            }
            points.append(
                PhaseEnvelopePoint(
                    temperatureK: saturation.temperatureK,
                    pressurePa: saturation.pressurePa,
                    branch: .bubble
                )
            )
        }
        points.append(
            PhaseEnvelopePoint(
                temperatureK: criticalTemperatureK,
                pressurePa: criticalPressurePa,
                branch: .critical
            )
        )

        return PhaseEnvelopeResponse(
            requestID: request.requestID,
            points: points,
            warnings: [
                "EXPERIMENTAL teqp provider — validation pending: do not use this boundary for engineering, safety, commercial, or regulatory decisions.",
                "For pure CO₂, bubble and dew boundaries coincide; the chart shows one saturation boundary.",
                "Impurity phase-envelope generation remains validation-gated and unavailable."
            ],
            isAvailable: true,
            boundaryKind: .pureFluidSaturation,
            model: descriptor,
            generatedAt: Date(),
            solver: SolverMetadata(
                method: "teqp pure-CO₂ VLE saturation solve",
                converged: true,
                durationMilliseconds: Date().timeIntervalSince(startedAt) * 1_000
            )
        )
    }

    private func propertyValue(
        for property: PropertyID,
        result: TeqpEngineResult
    ) -> PropertyValue {
        switch property {
        case .density:
            PropertyValue(
                property: property,
                value: result.densityKilogramsPerCubicMetre,
                unit: "kg/m³",
                status: .calculated,
                message: "Native teqp pure-CO₂ density from P,T with stable-root selection where required."
            )
        case .isobaricHeatCapacity:
            guardedPropertyValue(
                property: property,
                value: result.isobaricHeatCapacityJoulesPerKilogramKelvin,
                unit: "J/(kg·K)",
                message: "Native teqp pure-CO₂ Cp from ideal-gas plus residual Helmholtz derivatives."
            )
        case .isochoricHeatCapacity:
            guardedPropertyValue(
                property: property,
                value: result.isochoricHeatCapacityJoulesPerKilogramKelvin,
                unit: "J/(kg·K)",
                message: "Native teqp pure-CO₂ Cv from ideal-gas plus residual Helmholtz derivatives."
            )
        case .heatCapacityRatio:
            guardedPropertyValue(
                property: property,
                value: result.heatCapacityRatio,
                unit: "",
                message: "Native teqp pure-CO₂ heat-capacity ratio Cp/Cv."
            )
        case .speedOfSound:
            guardedPropertyValue(
                property: property,
                value: result.speedOfSoundMetresPerSecond,
                unit: "m/s",
                message: "Native teqp pure-CO₂ speed of sound from Helmholtz derivatives."
            )
        case .dynamicViscosity:
            PropertyValue(
                property: property,
                value: nil,
                unit: "Pa·s",
                status: .unavailable,
                message: "Dynamic viscosity is unavailable for the experimental teqp provider; no CoolProp fallback is used."
            )
        default:
            PropertyValue(
                property: property,
                value: nil,
                unit: "",
                status: .unavailable,
                message: "This property is not enabled for the experimental teqp pure-CO₂ milestone."
            )
        }
    }

    private func calculateHydrogenGasDensity(
        _ request: CalculationRequest
    ) async throws -> CalculationResponse {
        try validateHydrogenGasDomain(request)
        let startedAt = Date()
        let hydrogenMoleFraction = try hydrogenFraction(request.composition)
        let raw = try await engine.calculateCarbonDioxideHydrogenGasDensity(
            pressurePa: request.pressurePa,
            temperatureK: request.temperatureK,
            hydrogenMoleFraction: hydrogenMoleFraction
        )
        guard raw.densityKilogramsPerCubicMetre.isFinite,
              raw.densityKilogramsPerCubicMetre > 0
        else {
            throw ProviderError.malformedResponse(
                "teqp returned a non-finite or non-positive CO₂+H₂ gas density."
            )
        }
        guard raw.densityRootCount >= 1 else {
            throw ProviderError.malformedResponse(
                "teqp did not return a defensible CO₂+H₂ gas-density root."
            )
        }

        let derivedValues = DerivedPropertyCalculator().values(
            requestedProperties: request.requestedProperties,
            pressurePa: request.pressurePa,
            temperatureK: request.temperatureK,
            composition: request.composition,
            densityKilogramsPerCubicMetre: raw.densityKilogramsPerCubicMetre
        )
        let derivedByProperty = Dictionary(
            uniqueKeysWithValues: derivedValues.map { ($0.property, $0) }
        )
        let values = request.requestedProperties
            .sorted { $0.rawValue < $1.rawValue }
            .map { property -> PropertyValue in
                if let derived = derivedByProperty[property] {
                    return derived
                }
                if property == .density {
                    return PropertyValue(
                        property: property,
                        value: raw.densityKilogramsPerCubicMetre,
                        unit: "kg/m³",
                        status: .calculated,
                        message: "Native teqp EOS-CG-2021 CO₂+H₂ homogeneous gas density at the Souissi et al. 2017 validated composition/isotherm domain."
                    )
                }
                return PropertyValue(
                    property: property,
                    value: nil,
                    unit: "",
                    status: .unavailable,
                    message: "This property is not validated for the CO₂+H₂ EOS-CG-2021 gas-density domain; no CoolProp fallback is used."
                )
            }

        return CalculationResponse(
            requestID: request.requestID,
            model: descriptor,
            phase: .gas,
            properties: values,
            solver: SolverMetadata(
                method: "teqp v0.23.1 EOS-CG-2021 CO₂+H₂ homogeneous gas-density solve; formulation \(raw.formulationID); validation artifact Documentation/Validation/EOSCGDirectTeqpDensityProbeResults.json",
                converged: true,
                iterationCount: nil,
                durationMilliseconds: Date().timeIntervalSince(startedAt) * 1_000
            ),
            warnings: [
                "LIMITED PASS — CO₂+H₂ homogeneous gas density only at xH₂ = 0.05362 and the validated Souissi et al. 2017 isotherms/pressure ranges.",
                "Phase equilibrium, phase envelopes, heat capacities, speed of sound, reference-state properties and transport are unavailable for this mixture.",
                "No CoolProp fallback is used."
            ],
            isScientificResult: true
        )
    }

    private func validateHydrogenGasDomain(_ request: CalculationRequest) throws {
        let supported = try supportedHydrogenCapability()
        let hydrogenMoleFraction = try hydrogenFraction(request.composition)
        guard let compositionLimit = supported.compositionLimits
            .first(where: { $0.component == .hydrogen })
        else {
            throw ProviderError.invalidRequest("CO₂+H₂ validation metadata is incomplete.")
        }
        guard abs(hydrogenMoleFraction - compositionLimit.minimumMoleFraction)
            <= CalculationValidator.compositionTolerance
        else {
            throw ProviderError.invalidRequest(
                "CO₂+H₂ teqp density is validated only at xH₂ = 0.05362."
            )
        }
        guard let isotherm = supported.isothermPressureLimits.first(where: {
            abs(request.temperatureK - $0.temperatureK) <= 0.02
        }) else {
            throw ProviderError.invalidRequest(
                "CO₂+H₂ teqp density is validated only at 273.15 K, 293.15 K or 323.15 K."
            )
        }
        guard request.pressurePa >= isotherm.minimumPressurePa,
              request.pressurePa <= isotherm.maximumPressurePa
        else {
            throw ProviderError.invalidRequest(
                "CO₂+H₂ teqp density pressure is outside the validated gas range for this isotherm."
            )
        }
    }

    private func supportedHydrogenCapability() throws -> TeqpPropertyCapability {
        guard let capability = TeqpFormulationCatalog
            .co2HydrogenEOSCGGasDensity
            .propertyCapabilities
            .first(where: { $0.property == .density })
        else {
            throw ProviderError.invalidRequest("CO₂+H₂ validation metadata is incomplete.")
        }
        return capability
    }

    private func guardedPropertyValue(
        property: PropertyID,
        value: Double?,
        unit: String,
        message: String
    ) -> PropertyValue {
        guard let value, value.isFinite, value > 0 else {
            return PropertyValue(
                property: property,
                value: nil,
                unit: unit,
                status: .unavailable,
                message: "teqp did not return a finite positive value for this pure-CO₂ property."
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

    private func phaseRegion(for identifier: String) -> PhaseRegion {
        switch identifier.lowercased() {
        case "supercritical":
            .supercritical
        case "gas":
            .gas
        case "liquid":
            .liquid
        default:
            .unknown
        }
    }

    private func isPureCarbonDioxide(_ composition: [MixtureComponent]) -> Bool {
        composition.count == 1
            && composition[0].component == .carbonDioxide
            && abs(composition[0].moleFraction - 1)
                <= CalculationValidator.compositionTolerance
    }

    private func isSupportedHydrogenGasComposition(
        _ composition: [MixtureComponent]
    ) -> Bool {
        guard composition.count == 2,
              let carbonDioxide = composition.first(where: {
                  $0.component == .carbonDioxide
              }),
              let hydrogen = composition.first(where: {
                  $0.component == .hydrogen
              })
        else {
            return false
        }
        return abs(carbonDioxide.moleFraction + hydrogen.moleFraction - 1)
            <= CalculationValidator.compositionTolerance
            && abs(hydrogen.moleFraction - 0.05362)
                <= CalculationValidator.compositionTolerance
    }

    private func hydrogenFraction(_ composition: [MixtureComponent]) throws -> Double {
        guard let hydrogen = composition.first(where: { $0.component == .hydrogen }) else {
            throw ProviderError.invalidRequest("CO₂+H₂ composition is missing H₂.")
        }
        return hydrogen.moleFraction
    }
}
