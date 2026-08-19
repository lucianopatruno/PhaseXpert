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

public struct TeqpMixtureThermodynamicResult: Equatable, Sendable {
    public let densityKilogramsPerCubicMetre: Double
    public let molarDensityMolesPerCubicMetre: Double
    public let pressurePa: Double
    public let pressureDerivativeWithRespectToMolarDensityJoulesPerMole: Double
    public let pressureDerivativeWithRespectToTemperaturePascalsPerKelvin: Double
    public let isochoricHeatCapacityJoulesPerKilogramKelvin: Double
    public let isobaricHeatCapacityJoulesPerKilogramKelvin: Double
    public let heatCapacityRatio: Double
    public let speedOfSoundMetresPerSecond: Double
    public let speedOfSoundSquaredMetresSquaredPerSecondSquared: Double
    public let minimumStabilityEigenvalue: Double
    public let densityRootCount: Int
    public let converged: Bool
    public let phaseIdentifier: String
    public let formulationID: String

    public init(
        densityKilogramsPerCubicMetre: Double,
        molarDensityMolesPerCubicMetre: Double,
        pressurePa: Double,
        pressureDerivativeWithRespectToMolarDensityJoulesPerMole: Double,
        pressureDerivativeWithRespectToTemperaturePascalsPerKelvin: Double,
        isochoricHeatCapacityJoulesPerKilogramKelvin: Double,
        isobaricHeatCapacityJoulesPerKilogramKelvin: Double,
        heatCapacityRatio: Double,
        speedOfSoundMetresPerSecond: Double,
        speedOfSoundSquaredMetresSquaredPerSecondSquared: Double,
        minimumStabilityEigenvalue: Double,
        densityRootCount: Int,
        converged: Bool,
        phaseIdentifier: String,
        formulationID: String
    ) {
        self.densityKilogramsPerCubicMetre = densityKilogramsPerCubicMetre
        self.molarDensityMolesPerCubicMetre = molarDensityMolesPerCubicMetre
        self.pressurePa = pressurePa
        self.pressureDerivativeWithRespectToMolarDensityJoulesPerMole =
            pressureDerivativeWithRespectToMolarDensityJoulesPerMole
        self.pressureDerivativeWithRespectToTemperaturePascalsPerKelvin =
            pressureDerivativeWithRespectToTemperaturePascalsPerKelvin
        self.isochoricHeatCapacityJoulesPerKilogramKelvin =
            isochoricHeatCapacityJoulesPerKilogramKelvin
        self.isobaricHeatCapacityJoulesPerKilogramKelvin =
            isobaricHeatCapacityJoulesPerKilogramKelvin
        self.heatCapacityRatio = heatCapacityRatio
        self.speedOfSoundMetresPerSecond = speedOfSoundMetresPerSecond
        self.speedOfSoundSquaredMetresSquaredPerSecondSquared =
            speedOfSoundSquaredMetresSquaredPerSecondSquared
        self.minimumStabilityEigenvalue = minimumStabilityEigenvalue
        self.densityRootCount = densityRootCount
        self.converged = converged
        self.phaseIdentifier = phaseIdentifier
        self.formulationID = formulationID
    }
}

public struct TeqpBinaryCriticalResult: Equatable, Sendable {
    public let converged: Bool
    public let iterationCount: Int
    public let temperatureK: Double
    public let pressurePa: Double
    public let molarDensityMolesPerCubicMetre: Double
    public let densityKilogramsPerCubicMetre: Double
    public let component2MoleFraction: Double
    public let minimumStabilityEigenvalue: Double
    public let thirdOrderResidual: Double
    public let formulationID: String

    public init(
        converged: Bool,
        iterationCount: Int,
        temperatureK: Double,
        pressurePa: Double,
        molarDensityMolesPerCubicMetre: Double,
        densityKilogramsPerCubicMetre: Double,
        component2MoleFraction: Double,
        minimumStabilityEigenvalue: Double,
        thirdOrderResidual: Double,
        formulationID: String
    ) {
        self.converged = converged
        self.iterationCount = iterationCount
        self.temperatureK = temperatureK
        self.pressurePa = pressurePa
        self.molarDensityMolesPerCubicMetre = molarDensityMolesPerCubicMetre
        self.densityKilogramsPerCubicMetre = densityKilogramsPerCubicMetre
        self.component2MoleFraction = component2MoleFraction
        self.minimumStabilityEigenvalue = minimumStabilityEigenvalue
        self.thirdOrderResidual = thirdOrderResidual
        self.formulationID = formulationID
    }
}

public enum TeqpBinaryFormulationID: Sendable {
    case carbonDioxideNitrogen
    case eoscgCarbonDioxideHydrogen
    case eoscgCarbonDioxideMethane
}

public struct TeqpBinaryVLEResult: Equatable, Sendable {
    public let converged: Bool
    public let iterationCount: Int
    public let returnCode: Int
    public let pressurePa: Double
    public let liquidMolarDensityMolesPerCubicMetre: Double
    public let vaporMolarDensityMolesPerCubicMetre: Double
    public let liquidComponent2MoleFraction: Double
    public let vaporComponent2MoleFraction: Double
    public let pressureResidualPa: Double
    public let component1ChemicalPotentialResidual: Double
    public let component2ChemicalPotentialResidual: Double

    public init(
        converged: Bool,
        iterationCount: Int,
        returnCode: Int,
        pressurePa: Double,
        liquidMolarDensityMolesPerCubicMetre: Double,
        vaporMolarDensityMolesPerCubicMetre: Double,
        liquidComponent2MoleFraction: Double,
        vaporComponent2MoleFraction: Double,
        pressureResidualPa: Double,
        component1ChemicalPotentialResidual: Double,
        component2ChemicalPotentialResidual: Double
    ) {
        self.converged = converged
        self.iterationCount = iterationCount
        self.returnCode = returnCode
        self.pressurePa = pressurePa
        self.liquidMolarDensityMolesPerCubicMetre =
            liquidMolarDensityMolesPerCubicMetre
        self.vaporMolarDensityMolesPerCubicMetre =
            vaporMolarDensityMolesPerCubicMetre
        self.liquidComponent2MoleFraction = liquidComponent2MoleFraction
        self.vaporComponent2MoleFraction = vaporComponent2MoleFraction
        self.pressureResidualPa = pressureResidualPa
        self.component1ChemicalPotentialResidual =
            component1ChemicalPotentialResidual
        self.component2ChemicalPotentialResidual =
            component2ChemicalPotentialResidual
    }
}

public struct TeqpBinaryVLEInitialGuess: Equatable, Sendable {
    public let liquidMolarDensityMolesPerCubicMetre: Double
    public let vaporMolarDensityMolesPerCubicMetre: Double
    public let vaporComponent2MoleFraction: Double

    public init(
        liquidMolarDensityMolesPerCubicMetre: Double,
        vaporMolarDensityMolesPerCubicMetre: Double,
        vaporComponent2MoleFraction: Double
    ) {
        self.liquidMolarDensityMolesPerCubicMetre =
            liquidMolarDensityMolesPerCubicMetre
        self.vaporMolarDensityMolesPerCubicMetre =
            vaporMolarDensityMolesPerCubicMetre
        self.vaporComponent2MoleFraction = vaporComponent2MoleFraction
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

    func calculateCarbonDioxideMethaneGasDensity(
        pressurePa: Double,
        temperatureK: Double,
        methaneMoleFraction: Double
    ) async throws -> TeqpMixtureDensityResult

    func calculateBinaryThermodynamicState(
        formulation: TeqpBinaryFormulationID,
        pressurePa: Double,
        temperatureK: Double,
        component2MoleFraction: Double
    ) async throws -> TeqpMixtureThermodynamicResult

    func calculateBinaryCriticalPoint(
        formulation: TeqpBinaryFormulationID,
        component2MoleFraction: Double
    ) async throws -> TeqpBinaryCriticalResult

    func calculateBinaryVLE(
        formulation: TeqpBinaryFormulationID,
        temperatureK: Double,
        liquidComponent2MoleFraction: Double,
        initialGuess: TeqpBinaryVLEInitialGuess?
    ) async throws -> TeqpBinaryVLEResult
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

    public func calculateCarbonDioxideMethaneGasDensity(
        pressurePa: Double,
        temperatureK: Double,
        methaneMoleFraction: Double
    ) async throws -> TeqpMixtureDensityResult {
        throw ProviderError.modelUnavailable(
            "The teqp native XCFramework has not been linked."
        )
    }

    public func calculateBinaryVLE(
        formulation: TeqpBinaryFormulationID,
        temperatureK: Double,
        liquidComponent2MoleFraction: Double,
        initialGuess: TeqpBinaryVLEInitialGuess? = nil
    ) async throws -> TeqpBinaryVLEResult {
        throw ProviderError.modelUnavailable(
            "The teqp native XCFramework has not been linked."
        )
    }

    public func calculateBinaryThermodynamicState(
        formulation: TeqpBinaryFormulationID,
        pressurePa: Double,
        temperatureK: Double,
        component2MoleFraction: Double
    ) async throws -> TeqpMixtureThermodynamicResult {
        throw ProviderError.modelUnavailable(
            "The teqp native XCFramework has not been linked."
        )
    }

    public func calculateBinaryCriticalPoint(
        formulation: TeqpBinaryFormulationID,
        component2MoleFraction: Double
    ) async throws -> TeqpBinaryCriticalResult {
        throw ProviderError.modelUnavailable(
            "The teqp native XCFramework has not been linked."
        )
    }
}

public struct TeqpProvider<Engine: TeqpEngine>: ThermodynamicModelProvider {
    private let engine: Engine
    private let capabilityMatrix = AdvancedCCSCapabilityMatrix()

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
            equationOrMethod: "Pure CO₂ uses the pinned upstream CarbonDioxide.json multifluid model. CO₂+H₂ and CO₂+CH₄ homogeneous density use EOS-CG-2021 model data at the exact validated ThermoML density domains. Unsupported properties and domains do not fall back to CoolProp.",
            coefficientSetVersion: TeqpFormulationCatalog.pureCarbonDioxide.provenance,
            requiredResources: ["PhaseXpertTeqpBridge.xcframework"],
            limitations: [
                "Experimental local provider; no production accuracy claim.",
                "Pure CO₂ is supported for density, Cv, Cp, Cp/Cv, speed of sound and pure saturation.",
                "CO₂+H₂ is supported only for homogeneous gas density at xH₂ = 0.05362, on the validated 273.15 K, 293.15 K and 323.15 K isotherms, within the observed gas-pressure ranges.",
                "CO₂+CH₄ is supported only for homogeneous density at xCH₄ = 0.05 inside the encoded Ghafri et al. 2016 gas and high-temperature supercritical validation slices.",
                "CO₂+CH₄ VLE phase classification and continuous bubble/dew phase-envelope points are validation-gated to xCH₄ = 0.05 from 293.13 K to 298.142 K inside the ordinary Petropoulou et al. 2018 temperature bounds; two-phase bulk density is unavailable.",
                "N₂, O₂, Ar and simultaneous impurity mixtures remain unsupported and never fall back to CoolProp.",
                "Dynamic viscosity and all transport properties are unavailable for this provider.",
                "Subcritical states on or too close to pure-CO₂ saturation are reported as unavailable because they do not have a unique homogeneous bulk density.",
                "Phase classification is limited to pure-CO₂ stable vapor/liquid/supercritical states and the validated CO₂+CH₄ VLE gate; otherwise the phase remains unknown or unavailable.",
                "Pure-CO₂ phase-envelope generation is available; CO₂+CH₄ phase-envelope points are available only inside the validated VLE gate.",
                "Pure-CO₂ Cv, Cp and speed of sound are calculated from complete teqp ideal-gas plus residual Helmholtz derivatives; mixture Cv, Cp and speed of sound are implemented only as hidden diagnostics because no independent production validation gate has passed.",
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
                ),
                SourceReference(
                    authors: "Ghafri, Rowland, Hughes, May and others",
                    title: "Accurate density measurements on a binary mixture (carbon dioxide + methane) at the vicinity of the critical point in the supercritical state by a single-sinker densimeter",
                    year: 2016,
                    doiOrURL: "https://doi.org/10.1016/j.fluid.2015.08.029"
                )
            ]
        )
    }

    public func applicabilityIssues(
        for composition: [MixtureComponent]
    ) -> [ValidationIssue] {
        guard let canonical = try? CanonicalComposition(composition) else {
            return [
                ValidationIssue(
                    code: .compositionTotal,
                    severity: .error,
                    message: "Advanced CCS composition must be finite, duplicate-free, non-negative, and total exactly 100 mol% before provider routing."
                )
            ]
        }
        guard !isPureCarbonDioxide(canonical.components) else { return [] }
        if isSupportedHydrogenGasComposition(composition) {
            return []
        }
        if isSupportedMethaneGasComposition(composition) {
            return []
        }
        if canonical.components.count > 2 {
            let decision = capabilityMatrix.decision(
                for: canonical,
                property: .density
            )
            return [
                ValidationIssue(
                    code: .componentOutsideModelRange,
                    severity: .error,
                    message: "\(decision.reasons.joined(separator: " ")) No CoolProp fallback is used."
                )
            ]
        }
        return [
            ValidationIssue(
                code: .componentOutsideModelRange,
                severity: .error,
                message: "Advanced CCS Properties supports pure CO₂ plus validation-gated CO₂+H₂ and CO₂+CH₄ homogeneous density domains only. This mixture is unsupported and is not routed to CoolProp."
            )
        ]
    }

    public func operatingRangeGuidance(
        for context: OperatingGuidanceContext
    ) -> OperatingRangeGuidance? {
        guard engine.isAvailable else { return nil }
        guard !isPureCarbonDioxide(context.composition) else { return nil }

        if let hydrogen = context.composition.first(where: { $0.component == .hydrogen }) {
            return hydrogenOperatingRangeGuidance(
                hydrogenMoleFraction: hydrogen.moleFraction,
                pressurePa: context.pressurePa,
                temperatureK: context.temperatureK,
                requestedProperties: context.requestedProperties
            )
        }
        if let methane = context.composition.first(where: { $0.component == .methane }) {
            return methaneOperatingRangeGuidance(
                methaneMoleFraction: methane.moleFraction,
                pressurePa: context.pressurePa,
                temperatureK: context.temperatureK,
                requestedProperties: context.requestedProperties
            )
        }
        if context.composition.contains(where: { $0.component != .carbonDioxide }) {
            return OperatingRangeGuidance(
                title: "Model limits",
                summary: [
                    .init(
                        severity: .unsupported,
                        title: "Mixture unsupported",
                        detail: "Advanced CCS Properties is production-enabled only for pure CO₂, CO₂+H₂ density, and CO₂+CH₄ density/VLE gates. No CoolProp fallback is used."
                    )
                ]
            )
        }
        return nil
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
        let canonical: CanonicalComposition
        do {
            canonical = try CanonicalComposition(request.composition)
        } catch {
            throw ProviderError.invalidRequest(
                "Advanced CCS composition must be finite, duplicate-free, non-negative, and total exactly 100 mol% before provider routing."
            )
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
        if canonical.components.count > 2 {
            let decision = capabilityMatrix.decision(
                for: canonical,
                property: .density,
                pressurePa: request.pressurePa,
                temperatureK: request.temperatureK
            )
            throw ProviderError.invalidRequest(
                "\(decision.reasons.joined(separator: " ")) No CoolProp fallback is used."
            )
        }
        if isSupportedHydrogenGasComposition(request.composition) {
            return try await calculateHydrogenGasDensity(request)
        }
        if isSupportedMethaneGasComposition(request.composition) {
            if methaneDensityTemperatureGateContains(request.temperatureK) {
                return try await calculateMethaneGasDensity(request)
            }
            if methaneVLEProductionTemperatureContains(request.temperatureK) {
                return try await calculateMethaneVLEClassification(request)
            }
            throw ProviderError.invalidRequest(
                "CO₂+CH₄ teqp support at xCH₄ = 0.05 is limited to the Ghafri density slices and the Petropoulou 2018 ordinary VLE temperature interval 293.13 K (19.98 °C) to 298.142 K (24.99 °C)."
            )
        }
        guard isPureCarbonDioxide(request.composition) else {
            throw ProviderError.invalidRequest(
                "Advanced CCS Properties supports pure CO₂ plus validation-gated CO₂+H₂ and CO₂+CH₄ homogeneous density domains only. No CoolProp fallback is used."
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
        if isSupportedMethaneGasComposition(request.composition) {
            return try await methanePhaseEnvelope(request, startedAt: startedAt)
        }
        guard isPureCarbonDioxide(request.composition) else {
            throw ProviderError.invalidRequest(
                "Advanced CCS Properties phase diagrams are available only for pure CO₂ or the validated CO₂+CH₄ VLE gate at xCH₄ = 0.05. H₂ phase envelopes remain unavailable and no CoolProp fallback is used."
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
                    message: unsupportedHydrogenPropertyMessage(for: property)
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

    private func calculateMethaneGasDensity(
        _ request: CalculationRequest
    ) async throws -> CalculationResponse {
        try validateMethaneGasDomain(request)
        let startedAt = Date()
        let methaneMoleFraction = try methaneFraction(request.composition)
        let raw = try await engine.calculateCarbonDioxideMethaneGasDensity(
            pressurePa: request.pressurePa,
            temperatureK: request.temperatureK,
            methaneMoleFraction: methaneMoleFraction
        )
        guard raw.densityKilogramsPerCubicMetre.isFinite,
              raw.densityKilogramsPerCubicMetre > 0
        else {
            throw ProviderError.malformedResponse(
                "teqp returned a non-finite or non-positive CO₂+CH₄ gas density."
            )
        }
        guard raw.densityRootCount >= 1 else {
            throw ProviderError.malformedResponse(
                "teqp did not return a defensible CO₂+CH₄ gas-density root."
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
                        message: "Native teqp EOS-CG-2021 CO₂+CH₄ homogeneous density at the Ghafri et al. 2016 validated density domain."
                    )
                }
                return PropertyValue(
                    property: property,
                    value: nil,
                    unit: "",
                    status: .unavailable,
                    message: unsupportedMethanePropertyMessage(for: property)
                )
            }

        return CalculationResponse(
            requestID: request.requestID,
            model: descriptor,
            phase: phaseRegion(for: raw.phaseIdentifier),
            properties: values,
            solver: SolverMetadata(
                method: "teqp v0.23.1 EOS-CG-2021 CO₂+CH₄ homogeneous density solve; formulation \(raw.formulationID); validation artifact Documentation/Validation/MethaneDensityDomainExpansion2026-08-15.json",
                converged: true,
                iterationCount: nil,
                durationMilliseconds: Date().timeIntervalSince(startedAt) * 1_000
            ),
            warnings: [
                "LIMITED PASS — CO₂+CH₄ homogeneous density only at xCH₄ = 0.05 and the encoded Ghafri et al. 2016 gas/supercritical T/P slices.",
                "Phase equilibrium, phase envelopes, heat capacities, speed of sound, reference-state properties and transport are unavailable for this mixture.",
                "No CoolProp fallback is used."
            ],
            isScientificResult: true
        )
    }

    private func calculateMethaneVLEClassification(
        _ request: CalculationRequest
    ) async throws -> CalculationResponse {
        let startedAt = Date()
        let methaneMoleFraction = try methaneFraction(request.composition)
        let boundary = try await methaneVLEBoundary(
            temperatureK: request.temperatureK,
            methaneMoleFraction: methaneMoleFraction
        )
        let tolerance = max(2_000.0, 5e-4 * boundary.bubble.pressurePa)
        let phase: PhaseRegion
        let phaseMessage: String
        if abs(boundary.bubble.pressurePa - boundary.dew.pressurePa) <= tolerance {
            phase = .unknown
            phaseMessage = "CO₂+CH₄ state is too close to the validated VLE boundary for robust phase classification."
        } else if request.pressurePa < boundary.dew.pressurePa - tolerance {
            phase = .gas
            phaseMessage = "CO₂+CH₄ state is below the validated dew pressure on the Petropoulou 2018 VLE gate."
        } else if request.pressurePa > boundary.bubble.pressurePa + tolerance {
            phase = .dense
            phaseMessage = "CO₂+CH₄ state is above the validated bubble pressure on the Petropoulou 2018 VLE gate; homogeneous density remains unavailable outside the Ghafri density slices."
        } else {
            phase = .twoPhase
            phaseMessage = "CO₂+CH₄ state lies inside the validated two-phase pressure interval; PhaseXpert does not fabricate a bulk two-phase density."
        }

        let values = request.requestedProperties
            .sorted { $0.rawValue < $1.rawValue }
            .map { property in
                PropertyValue(
                    property: property,
                    value: nil,
                    unit: property == .density ? "kg/m³" : "",
                    status: .unavailable,
                    message: property == .density
                        ? "CO₂+CH₄ VLE phase classification is available here, but homogeneous bulk density is not validated for this two-phase/phase-boundary domain."
                        : unsupportedMethaneVLEPropertyMessage(for: property)
                )
            }

        return CalculationResponse(
            requestID: request.requestID,
            model: descriptor,
            phase: phase,
            properties: values,
            solver: SolverMetadata(
                method: "teqp v0.23.1 EOS-CG-2021 CO₂+CH₄ binary VLE classification; \(phaseMessage) validation artifact Documentation/Validation/MethaneVLEProductionGate2026-08-16.json",
                converged: boundary.bubble.converged && boundary.dew.converged,
                iterationCount: boundary.bubble.iterationCount
                    + boundary.dew.iterationCount,
                absoluteTolerance: tolerance,
                relativeTolerance: 5e-4,
                durationMilliseconds: Date().timeIntervalSince(startedAt) * 1_000
            ),
            warnings: [
                "LIMITED PASS — CO₂+CH₄ VLE classification at xCH₄ = 0.05 from 293.13 K to 298.142 K, calculated with EOS-CG-2021 inside the experimentally validated Petropoulou et al. 2018 ordinary VLE temperature bounds.",
                "Bulk density, phase fraction, heat capacities, speed of sound, h/u/s and transport are unavailable in this VLE domain.",
                "No CoolProp fallback is used."
            ],
            isScientificResult: true
        )
    }

    private struct MethaneVLEBoundary {
        let bubble: TeqpBinaryVLEResult
        let dew: TeqpBinaryVLEResult
    }

    private func methaneVLEBoundary(
        temperatureK: Double,
        methaneMoleFraction: Double
    ) async throws -> MethaneVLEBoundary {
        let isotherm = try methaneVLEProductionTemperature(for: temperatureK)
        return try await methaneVLEBoundaryAtTemperature(
            temperatureK: isotherm,
            methaneMoleFraction: methaneMoleFraction,
            bubbleInitialGuess: nil
        )
    }

    private func methaneVLEBoundaryAtTemperature(
        temperatureK: Double,
        methaneMoleFraction: Double,
        bubbleInitialGuess: TeqpBinaryVLEInitialGuess?
    ) async throws -> MethaneVLEBoundary {
        let bubble = try await methaneBubblePoint(
            temperatureK: temperatureK,
            liquidMethaneMoleFraction: methaneMoleFraction,
            initialGuess: bubbleInitialGuess
        )
        let dew = try await methaneDewPoint(
            temperatureK: temperatureK,
            vaporMethaneMoleFraction: methaneMoleFraction
        )
        guard bubble.liquidMolarDensityMolesPerCubicMetre
            > bubble.vaporMolarDensityMolesPerCubicMetre,
              dew.liquidMolarDensityMolesPerCubicMetre
            > dew.vaporMolarDensityMolesPerCubicMetre
        else {
            throw ProviderError.malformedResponse(
                "teqp CO₂+CH₄ VLE solve did not preserve liquid/vapor density identity."
            )
        }
        guard bubble.pressurePa > dew.pressurePa else {
            throw ProviderError.malformedResponse(
                "teqp CO₂+CH₄ VLE solve returned a nonphysical bubble/dew pressure ordering."
            )
        }
        return MethaneVLEBoundary(bubble: bubble, dew: dew)
    }

    private func methanePhaseEnvelope(
        _ request: PhaseEnvelopeRequest,
        startedAt: Date
    ) async throws -> PhaseEnvelopeResponse {
        let methaneMoleFraction = try methaneFraction(request.composition)
        guard methaneVLECompositionSupported(methaneMoleFraction) else {
            throw ProviderError.invalidRequest(
                "CO₂+CH₄ phase-envelope generation is validated only at xCH₄ = 0.05."
            )
        }

        var bubblePoints: [PhaseEnvelopePoint] = []
        var dewPoints: [PhaseEnvelopePoint] = []
        var failedTemperatures: [Double] = []
        var previousBubbleGuess: TeqpBinaryVLEInitialGuess?
        let temperatures = methaneProductionEnvelopeTemperatures()
        bubblePoints.reserveCapacity(temperatures.count)
        dewPoints.reserveCapacity(temperatures.count)
        for isotherm in temperatures {
            try Task.checkCancellation()
            let boundary: MethaneVLEBoundary
            do {
                boundary = try await methaneVLEBoundaryAtTemperature(
                    temperatureK: isotherm,
                    methaneMoleFraction: methaneMoleFraction,
                    bubbleInitialGuess: previousBubbleGuess
                )
            } catch {
                failedTemperatures.append(isotherm)
                previousBubbleGuess = nil
                continue
            }
            previousBubbleGuess = TeqpBinaryVLEInitialGuess(
                liquidMolarDensityMolesPerCubicMetre:
                    boundary.bubble.liquidMolarDensityMolesPerCubicMetre,
                vaporMolarDensityMolesPerCubicMetre:
                    boundary.bubble.vaporMolarDensityMolesPerCubicMetre,
                vaporComponent2MoleFraction:
                    boundary.bubble.vaporComponent2MoleFraction
            )
            bubblePoints.append(
                PhaseEnvelopePoint(
                    temperatureK: isotherm,
                    pressurePa: boundary.bubble.pressurePa,
                    branch: .bubble
                )
            )
            dewPoints.append(
                PhaseEnvelopePoint(
                    temperatureK: isotherm,
                    pressurePa: boundary.dew.pressurePa,
                    branch: .dew
                )
            )
        }
        guard failedTemperatures.isEmpty,
              bubblePoints.count == temperatures.count,
              dewPoints.count == temperatures.count
        else {
            throw ProviderError.malformedResponse(
                "teqp CO₂+CH₄ production VLE continuation did not converge at every validated interpolation temperature."
            )
        }
        let bubblePressures = bubblePoints.map(\.pressurePa)
        let dewPressures = dewPoints.map(\.pressurePa)
        guard methanePressuresAreMonotonic(bubblePressures),
              methanePressuresAreMonotonic(dewPressures)
        else {
            throw ProviderError.malformedResponse(
                "teqp CO₂+CH₄ production VLE continuation returned a non-monotonic pressure branch."
            )
        }

        return PhaseEnvelopeResponse(
            requestID: request.requestID,
            points: bubblePoints + dewPoints,
            warnings: [
                "LIMITED PASS — CO₂+CH₄ continuous bubble/dew envelope is production-enabled only at xCH₄ = 0.05 from 293.13 K to 298.142 K.",
                "Curve points between 293.13 K and 298.142 K are EOS-CG-2021 calculations inside the experimentally validated Petropoulou et al. 2018 ordinary VLE temperature bounds; only the anchor isotherms are direct experimental validation rows.",
                "Critical termination is not drawn for xCH₄ = 0.05 because the Petropoulou critical-region rows do not validate this composition; PhaseXpert does not interpolate to a critical endpoint.",
                "No failed or missing VLE points are connected; all \(temperatures.count) production temperature samples converged and no CoolProp fallback is used."
            ],
            isAvailable: true,
            boundaryKind: .mixtureEnvelope,
            model: descriptor,
            generatedAt: Date(),
            solver: SolverMetadata(
                method: "teqp v0.23.1 EOS-CG-2021 CO₂+CH₄ production VLE interpolation with previous-solution warm starts; \(bubblePoints.count + dewPoints.count) plotted points from \(temperatures.count) temperatures over 293.13 K to 298.142 K; \(TeqpFormulationCatalog.co2MethaneEOSCGVLE.accuracySummary) validation artifact \(TeqpFormulationCatalog.co2MethaneEOSCGVLE.validationArtifact)",
                converged: failedTemperatures.isEmpty,
                iterationCount: nil,
                durationMilliseconds: Date().timeIntervalSince(startedAt) * 1_000
            )
        )
    }

    private func methaneBubblePoint(
        temperatureK: Double,
        liquidMethaneMoleFraction: Double,
        initialGuess: TeqpBinaryVLEInitialGuess? = nil
    ) async throws -> TeqpBinaryVLEResult {
        try await engine.calculateBinaryVLE(
            formulation: .eoscgCarbonDioxideMethane,
            temperatureK: temperatureK,
            liquidComponent2MoleFraction: liquidMethaneMoleFraction,
            initialGuess: initialGuess ?? methaneInitialGuess(
                temperatureK: temperatureK,
                pressurePa: methanePressureGuess(for: temperatureK),
                vaporMethaneMoleFraction: min(
                    methaneVLEMaximumVaporMethaneMoleFraction,
                    max(2 * liquidMethaneMoleFraction, 1e-5)
                )
            )
        )
    }

    private func methaneProductionEnvelopeTemperatures() -> [Double] {
        let count = methaneVLEProductionEnvelopeTemperatureCount
        let lower = methaneVLEProductionTemperatureRange.lowerBound
        let upper = methaneVLEProductionTemperatureRange.upperBound
        let increment = (upper - lower) / Double(count - 1)

        return (0..<count).map { index in
            if index == count - 1 {
                return upper
            }
            return lower + Double(index) * increment
        }
    }

    private func methanePressuresAreMonotonic(_ pressures: [Double]) -> Bool {
        zip(pressures, pressures.dropFirst()).allSatisfy { previous, next in
            next > previous
        }
    }

    private func methaneDewPoint(
        temperatureK: Double,
        vaporMethaneMoleFraction: Double
    ) async throws -> TeqpBinaryVLEResult {
        var lower = methaneVLEMinimumMethaneMoleFraction
        var upper = min(vaporMethaneMoleFraction, methaneVLEMaximumLiquidMethaneMoleFraction)
        var lowerResult = try await methaneBubblePoint(
            temperatureK: temperatureK,
            liquidMethaneMoleFraction: lower
        )
        var upperResult = try await methaneBubblePoint(
            temperatureK: temperatureK,
            liquidMethaneMoleFraction: upper
        )

        while upperResult.vaporComponent2MoleFraction < vaporMethaneMoleFraction
                && upper < methaneVLEMaximumLiquidMethaneMoleFraction {
            try Task.checkCancellation()
            lower = upper
            lowerResult = upperResult
            upper = min(methaneVLEMaximumLiquidMethaneMoleFraction, upper * 1.35)
            upperResult = try await methaneBubblePoint(
                temperatureK: temperatureK,
                liquidMethaneMoleFraction: upper
            )
        }

        guard lowerResult.vaporComponent2MoleFraction <= vaporMethaneMoleFraction,
              upperResult.vaporComponent2MoleFraction >= vaporMethaneMoleFraction
        else {
            throw ProviderError.invalidRequest(
                "CO₂+CH₄ dew solve could not bracket the requested vapor composition inside the validated Petropoulou VLE domain."
            )
        }

        var best = upperResult
        for _ in 0..<36 {
            try Task.checkCancellation()
            let mid = 0.5 * (lower + upper)
            let result = try await methaneBubblePoint(
                temperatureK: temperatureK,
                liquidMethaneMoleFraction: mid
            )
            best = result
            let deviation = result.vaporComponent2MoleFraction
                - vaporMethaneMoleFraction
            if abs(deviation) <= 1e-7 {
                return result
            }
            if deviation < 0 {
                lower = mid
            } else {
                upper = mid
            }
        }
        return best
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

    private func validateMethaneGasDomain(_ request: CalculationRequest) throws {
        let supported = try supportedMethaneCapability()
        let methaneMoleFraction = try methaneFraction(request.composition)
        guard let compositionLimit = supported.compositionLimits
            .first(where: { $0.component == .methane })
        else {
            throw ProviderError.invalidRequest("CO₂+CH₄ validation metadata is incomplete.")
        }
        guard abs(methaneMoleFraction - compositionLimit.minimumMoleFraction)
            <= CalculationValidator.compositionTolerance
        else {
            throw ProviderError.invalidRequest(
                "CO₂+CH₄ teqp density is validated only at xCH₄ = 0.05."
            )
        }
        guard let gasBlock = supported.isothermPressureLimits.first(where: {
            request.temperatureK >= $0.minimumTemperatureK
                && request.temperatureK <= $0.maximumTemperatureK
        }) else {
            throw ProviderError.invalidRequest(
                "CO₂+CH₄ teqp density is validated only within these Ghafri et al. 2016 temperature slices: \(temperatureDomainSummary(for: supported))."
            )
        }
        guard request.pressurePa >= gasBlock.minimumPressurePa,
              request.pressurePa <= gasBlock.maximumPressurePa
        else {
            throw ProviderError.invalidRequest(
                "CO₂+CH₄ teqp density pressure is outside the validated range for this Ghafri et al. 2016 isotherm slice."
            )
        }
    }

    private func methaneDensityDomainContains(_ request: CalculationRequest) -> Bool {
        guard let supported = try? supportedMethaneCapability(),
              let methaneMoleFraction = try? methaneFraction(request.composition),
              let compositionLimit = supported.compositionLimits
                .first(where: { $0.component == .methane }),
              abs(methaneMoleFraction - compositionLimit.minimumMoleFraction)
                <= CalculationValidator.compositionTolerance
        else {
            return false
        }
        return supported.isothermPressureLimits.contains {
            request.temperatureK >= $0.minimumTemperatureK
                && request.temperatureK <= $0.maximumTemperatureK
                && request.pressurePa >= $0.minimumPressurePa
                && request.pressurePa <= $0.maximumPressurePa
        }
    }

    private func methaneDensityTemperatureGateContains(_ temperatureK: Double) -> Bool {
        guard let supported = try? supportedMethaneCapability() else {
            return false
        }
        return supported.isothermPressureLimits.contains {
            temperatureK >= $0.minimumTemperatureK - 0.05
                && temperatureK <= $0.maximumTemperatureK + 0.05
        }
    }

    private func methaneVLEProductionTemperatureContains(_ temperatureK: Double) -> Bool {
        (try? methaneVLEProductionTemperature(for: temperatureK)) != nil
    }

    private func methaneVLECompositionSupported(_ methaneMoleFraction: Double) -> Bool {
        abs(methaneMoleFraction - methaneVLEProductionMethaneMoleFraction)
            <= CalculationValidator.compositionTolerance
    }

    private func methaneVLEProductionTemperature(for temperatureK: Double) throws -> Double {
        let lower = methaneVLEProductionTemperatureRange.lowerBound
        let upper = methaneVLEProductionTemperatureRange.upperBound
        guard temperatureK >= lower - methaneVLETemperatureTolerance,
              temperatureK <= upper + methaneVLETemperatureTolerance
        else {
            throw ProviderError.invalidRequest(
                "CO₂+CH₄ VLE is production-enabled only inside the ordinary Petropoulou et al. 2018 temperature interval 293.13 K (19.98 °C) to 298.142 K (24.99 °C) for xCH₄ = 0.05."
            )
        }
        return min(max(temperatureK, lower), upper)
    }

    private func methaneInitialGuess(
        temperatureK: Double,
        pressurePa: Double,
        vaporMethaneMoleFraction: Double
    ) -> TeqpBinaryVLEInitialGuess {
        TeqpBinaryVLEInitialGuess(
            liquidMolarDensityMolesPerCubicMetre: 19_000,
            vaporMolarDensityMolesPerCubicMetre:
                pressurePa / (8.314_462_618_153_24 * temperatureK),
            vaporComponent2MoleFraction: vaporMethaneMoleFraction
        )
    }

    private func methanePressureGuess(for temperatureK: Double) -> Double {
        if abs(temperatureK - 293.13) <= 0.02 {
            return 6_975_550
        }
        if abs(temperatureK - 298.142) <= 0.02 {
            return 7_507_850
        }
        return 7_000_000
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

    private func supportedMethaneCapability() throws -> TeqpPropertyCapability {
        guard let capability = TeqpFormulationCatalog
            .co2MethaneEOSCGGasDensity
            .propertyCapabilities
            .first(where: { $0.property == .density })
        else {
            throw ProviderError.invalidRequest("CO₂+CH₄ validation metadata is incomplete.")
        }
        return capability
    }

    private func hydrogenOperatingRangeGuidance(
        hydrogenMoleFraction: Double,
        pressurePa: Double?,
        temperatureK: Double?,
        requestedProperties: Set<PropertyID>
    ) -> OperatingRangeGuidance {
        let capability = try? supportedHydrogenCapability()
        let limits = capability?.isothermPressureLimits ?? []
        let supportedMoleFraction = capability?.compositionLimits
            .first(where: { $0.component == .hydrogen })?
            .minimumMoleFraction ?? 0.05362
        var issues: [OperatingGuidanceLine] = []
        var summary: [OperatingGuidanceLine] = [
            .init(
                severity: .information,
                title: "H₂ validated composition",
                detail: "\(ppmString(supportedMoleFraction)) ppm"
            ),
            .init(
                severity: .information,
                title: "Validated temperature",
                detail: exactTemperatureList(limits)
            )
        ]

        if let temperatureK {
            if let isotherm = limits.first(where: {
                abs(temperatureK - $0.temperatureK) <= 0.02
            }) {
                summary.append(.init(
                    severity: .information,
                    title: "Validated pressure",
                    detail: pressureRangeString(isotherm)
                ))
                if let pressurePa,
                   pressurePa < isotherm.minimumPressurePa
                    || pressurePa > isotherm.maximumPressurePa {
                    issues.append(.init(
                        severity: .warning,
                        title: "Pressure outside validated range",
                        detail: "\(barString(pressurePa)) bar(a) is outside the validated H₂ pressure range for \(celsiusString(isotherm.temperatureK)) °C: \(pressureRangeString(isotherm))."
                    ))
                }
            } else {
                issues.append(.init(
                    severity: .unsupported,
                    title: "Temperature outside validation set",
                    detail: "\(celsiusString(temperatureK)) °C is outside the validated H₂ temperature set. Use \(exactTemperatureList(limits))."
                ))
            }
        } else {
            summary.append(.init(
                severity: .information,
                title: "Pressure",
                detail: "Validated range depends on the selected temperature."
            ))
        }

        if abs(hydrogenMoleFraction - supportedMoleFraction)
            > CalculationValidator.compositionTolerance {
            issues.append(.init(
                severity: .unsupported,
                title: "Composition outside validated value",
                detail: "Entered \(ppmString(hydrogenMoleFraction)) ppm H₂; validated H₂ composition is \(ppmString(supportedMoleFraction)) ppm."
            ))
        }

        return OperatingRangeGuidance(
            title: "Validated range",
            summary: summary,
            currentInputIssues: issues,
            propertyAvailability: propertyAvailabilityLines(
                requestedProperties: requestedProperties,
                supportedProperties: [.density, .molarMass, .compressibilityFactor, .specificVolume],
                system: "CO₂+H₂"
            ),
            phaseDiagram: [
                .init(
                    severity: .unsupported,
                    title: "Phase diagram",
                    detail: "Phase diagram not yet validated for CO₂+H₂."
                )
            ],
            suggestions: hydrogenSuggestions(
                currentMoleFraction: hydrogenMoleFraction,
                supportedMoleFraction: supportedMoleFraction,
                limits: limits
            )
        )
    }

    private func methaneOperatingRangeGuidance(
        methaneMoleFraction: Double,
        pressurePa: Double?,
        temperatureK: Double?,
        requestedProperties: Set<PropertyID>
    ) -> OperatingRangeGuidance {
        let density = try? supportedMethaneCapability()
        let densityLimits = density?.isothermPressureLimits ?? []
        let vle = TeqpFormulationCatalog.co2MethaneEOSCGVLE
        let supportedMoleFraction = density?.compositionLimits
            .first(where: { $0.component == .methane })?
            .minimumMoleFraction ?? 0.05
        var summary: [OperatingGuidanceLine] = [
            .init(
                severity: .information,
                title: "CH₄ validated composition",
                detail: "\(ppmString(supportedMoleFraction)) ppm"
            ),
            .init(
                severity: .information,
                title: "Density temperature",
                detail: "28.0 °C gas block; 35.0–40.0 °C high-temperature slices"
            ),
            .init(
                severity: .information,
                title: "Phase equilibrium",
                detail: "19.98–24.99 °C at \(ppmString(supportedMoleFraction)) ppm CH₄"
            )
        ]
        var issues: [OperatingGuidanceLine] = []

        if let temperatureK {
            if let densityLimit = densityLimits.first(where: {
                temperatureK >= $0.minimumTemperatureK
                    && temperatureK <= $0.maximumTemperatureK
            }) {
                summary.append(.init(
                    severity: .information,
                    title: "Validated density pressure",
                    detail: pressureRangeString(densityLimit)
                ))
                if let pressurePa,
                   pressurePa < densityLimit.minimumPressurePa
                    || pressurePa > densityLimit.maximumPressurePa {
                    issues.append(.init(
                        severity: .warning,
                        title: "Pressure outside validated density range",
                        detail: "\(barString(pressurePa)) bar(a) is outside the validated CH₄ density pressure range for \(celsiusString(densityLimit.temperatureK)) °C: \(pressureRangeString(densityLimit))."
                    ))
                }
            } else if methaneVLEProductionTemperatureContains(temperatureK) {
                summary.append(.init(
                    severity: .information,
                    title: "VLE pressure",
                    detail: "Bubble/dew pressure is calculated inside the Petropoulou validation interval; bulk density is unavailable here."
                ))
            } else {
                issues.append(.init(
                    severity: .unsupported,
                    title: "Temperature outside CH₄ gates",
                    detail: "\(celsiusString(temperatureK)) °C is outside the CH₄ density slices and VLE interval."
                ))
            }
        }

        if abs(methaneMoleFraction - supportedMoleFraction)
            > CalculationValidator.compositionTolerance {
            issues.append(.init(
                severity: .unsupported,
                title: "Composition outside validated value",
                detail: "Entered \(ppmString(methaneMoleFraction)) ppm CH₄; validated CH₄ composition is \(ppmString(supportedMoleFraction)) ppm."
            ))
        }

        return OperatingRangeGuidance(
            title: "Validated range",
            summary: summary,
            currentInputIssues: issues,
            propertyAvailability: propertyAvailabilityLines(
                requestedProperties: requestedProperties,
                supportedProperties: [.density, .molarMass, .compressibilityFactor, .specificVolume],
                system: "CO₂+CH₄"
            ),
            phaseDiagram: [
                .init(
                    severity: vle.supportsContinuousEnvelope ? .information : .unsupported,
                    title: "Phase diagram",
                    detail: "Continuous bubble/dew envelope is production-enabled only at \(ppmString(supportedMoleFraction)) ppm CH₄ from 19.98 °C to 24.99 °C; no validated critical marker."
                )
            ],
            suggestions: methaneSuggestions(
                currentMoleFraction: methaneMoleFraction,
                supportedMoleFraction: supportedMoleFraction
            )
        )
    }

    private func propertyAvailabilityLines(
        requestedProperties: Set<PropertyID>,
        supportedProperties: Set<PropertyID>,
        system: String
    ) -> [OperatingGuidanceLine] {
        let unavailable = requestedProperties.subtracting(supportedProperties)
        var lines: [OperatingGuidanceLine] = []
        if !unavailable.isDisjoint(with: [
            .isobaricHeatCapacity,
            .isochoricHeatCapacity,
            .heatCapacityRatio,
            .speedOfSound
        ]) {
            lines.append(.init(
                severity: .unsupported,
                title: "Cp/Cv/speed",
                detail: "Mixture heat capacities and speed of sound are not production-validated for \(system)."
            ))
        }
        if !unavailable.isDisjoint(with: [.dynamicViscosity, .thermalConductivity]) {
            lines.append(.init(
                severity: .unsupported,
                title: "Transport",
                detail: "Viscosity and thermal conductivity are unavailable for \(system); no fallback calculation is used."
            ))
        }
        if !unavailable.isDisjoint(with: [.enthalpy, .entropy, .internalEnergy]) {
            lines.append(.init(
                severity: .unsupported,
                title: "h/u/s",
                detail: "Reference-state properties are unavailable for \(system)."
            ))
        }
        return lines
    }

    private func hydrogenSuggestions(
        currentMoleFraction: Double,
        supportedMoleFraction: Double,
        limits: [TeqpTemperaturePressureLimit]
    ) -> [OperatingGuidanceSuggestion] {
        var suggestions: [OperatingGuidanceSuggestion] = []
        if abs(currentMoleFraction - supportedMoleFraction)
            > CalculationValidator.compositionTolerance {
            suggestions.append(.init(
                id: "use-h2-\(supportedMoleFraction)",
                label: "Use \(ppmString(supportedMoleFraction)) ppm H₂",
                action: .setComposition(
                    component: .hydrogen,
                    moleFraction: supportedMoleFraction
                )
            ))
        }
        suggestions.append(contentsOf: limits.map {
            OperatingGuidanceSuggestion(
                id: "use-h2-temperature-\($0.temperatureK)",
                label: "\(celsiusString($0.temperatureK)) °C",
                action: .setTemperature(kelvin: $0.temperatureK)
            )
        })
        return suggestions
    }

    private func methaneSuggestions(
        currentMoleFraction: Double,
        supportedMoleFraction: Double
    ) -> [OperatingGuidanceSuggestion] {
        guard abs(currentMoleFraction - supportedMoleFraction)
            > CalculationValidator.compositionTolerance
        else { return [] }
        return [
            OperatingGuidanceSuggestion(
                id: "use-ch4-\(supportedMoleFraction)",
                label: "Use \(ppmString(supportedMoleFraction)) ppm CH₄",
                action: .setComposition(
                    component: .methane,
                    moleFraction: supportedMoleFraction
                )
            )
        ]
    }

    private func exactTemperatureList(
        _ limits: [TeqpTemperaturePressureLimit]
    ) -> String {
        let values = limits.map { "\(celsiusString($0.temperatureK)) °C" }
        guard values.count > 1 else { return values.first ?? "Unavailable" }
        return values.dropLast().joined(separator: ", ")
            + " or "
            + (values.last ?? "")
    }

    private func pressureRangeString(_ limit: TeqpTemperaturePressureLimit) -> String {
        "\(barString(limit.minimumPressurePa))–\(barString(limit.maximumPressurePa)) bar(a)"
    }

    private func ppmString(_ moleFraction: Double) -> String {
        let ppm = moleFraction * 1_000_000
        if abs(ppm.rounded() - ppm) < 0.05 {
            return "\(Int(ppm.rounded()))"
        }
        return String(format: "%.0f", ppm)
    }

    private func celsiusString(_ kelvin: Double) -> String {
        let celsius = TemperatureUnit.celsius.fromKelvin(kelvin)
        return abs(celsius.rounded() - celsius) < 0.005
            ? String(format: "%.0f", celsius)
            : String(format: "%.2f", celsius)
    }

    private func barString(_ pascal: Double) -> String {
        let bar = PressureUnit.bara.fromPascal(pascal)
        return String(format: "%.1f", bar)
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

    private func unsupportedHydrogenPropertyMessage(
        for property: PropertyID
    ) -> String {
        guard let capability = try? supportedHydrogenCapability() else {
            return "This property is not validated for CO₂+H₂; no CoolProp fallback is used."
        }
        return unsupportedPropertyMessage(
            property: property,
            system: "CO₂+H₂",
            enabledCapability: capability,
            unavailableDetail: "mixture Cv, Cp, speed of sound, VLE, phase envelope, h/u/s and transport remain unavailable"
        )
    }

    private func unsupportedMethanePropertyMessage(
        for property: PropertyID
    ) -> String {
        guard let capability = try? supportedMethaneCapability() else {
            return "This property is not validated for CO₂+CH₄; no CoolProp fallback is used."
        }
        return unsupportedPropertyMessage(
            property: property,
            system: "CO₂+CH₄",
            enabledCapability: capability,
            unavailableDetail: "mixture Cv, Cp, speed of sound, h/u/s and transport remain unavailable"
        )
    }

    private func unsupportedMethaneVLEPropertyMessage(
        for property: PropertyID
    ) -> String {
        let capability = TeqpFormulationCatalog.co2MethaneEOSCGVLE
        let propertyName = displayName(for: property)
        return "\(propertyName) for CO₂+CH₄ is not production-validated in the VLE gate; \(capability.validationSummary) enables phase classification and bubble/dew points only. \(capability.accuracySummary) No CoolProp fallback is used."
    }

    private func unsupportedPropertyMessage(
        property: PropertyID,
        system: String,
        enabledCapability: TeqpPropertyCapability,
        unavailableDetail: String
    ) -> String {
        let propertyName = displayName(for: property)
        let accuracy = enabledCapability.accuracySummary.map { " \($0)" } ?? ""
        return "\(propertyName) for \(system) is not production-validated; the enabled gate is \(enabledCapability.validationSummary)\(accuracy) \(unavailableDetail). No CoolProp fallback is used."
    }

    private func displayName(for property: PropertyID) -> String {
        switch property {
        case .isobaricHeatCapacity:
            "Cp"
        case .isochoricHeatCapacity:
            "Cv"
        case .speedOfSound:
            "Speed of sound"
        case .heatCapacityRatio:
            "Cp/Cv"
        default:
            property.rawValue
        }
    }

    private func temperatureDomainSummary(
        for capability: TeqpPropertyCapability
    ) -> String {
        capability.isothermPressureLimits
            .map { limit in
                if limit.minimumTemperatureK == limit.maximumTemperatureK {
                    return "\(limit.temperatureK) K"
                }
                return "\(limit.minimumTemperatureK)-\(limit.maximumTemperatureK) K"
            }
            .joined(separator: ", ")
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

    private func isSupportedMethaneGasComposition(
        _ composition: [MixtureComponent]
    ) -> Bool {
        guard composition.count == 2,
              let carbonDioxide = composition.first(where: {
                  $0.component == .carbonDioxide
              }),
              let methane = composition.first(where: {
                  $0.component == .methane
              })
        else {
            return false
        }
        return abs(carbonDioxide.moleFraction + methane.moleFraction - 1)
            <= CalculationValidator.compositionTolerance
            && abs(methane.moleFraction - 0.05)
                <= CalculationValidator.compositionTolerance
    }

    private func hydrogenFraction(_ composition: [MixtureComponent]) throws -> Double {
        guard let hydrogen = composition.first(where: { $0.component == .hydrogen }) else {
            throw ProviderError.invalidRequest("CO₂+H₂ composition is missing H₂.")
        }
        return hydrogen.moleFraction
    }

    private func methaneFraction(_ composition: [MixtureComponent]) throws -> Double {
        guard let methane = composition.first(where: { $0.component == .methane }) else {
            throw ProviderError.invalidRequest("CO₂+CH₄ composition is missing CH₄.")
        }
        return methane.moleFraction
    }

    private var methaneVLEProductionMethaneMoleFraction: Double { 0.05 }
    private var methaneVLEMinimumMethaneMoleFraction: Double { 0.00001 }
    private var methaneVLEMaximumLiquidMethaneMoleFraction: Double { 0.06165 }
    private var methaneVLEMaximumVaporMethaneMoleFraction: Double { 0.13134 }
    private var methaneVLEProductionIsotherms: [Double] { [293.13, 298.142] }
    private var methaneVLEProductionTemperatureRange: ClosedRange<Double> { 293.13...298.142 }
    private var methaneVLETemperatureTolerance: Double { 0.02 }
    private var methaneVLEProductionEnvelopeTemperatureCount: Int { 41 }
}
