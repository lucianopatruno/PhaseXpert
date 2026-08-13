import Foundation

public struct TeqpEngineResult: Equatable, Sendable {
    public let densityKilogramsPerCubicMetre: Double
    public let densityRootCount: Int
    public let phaseIdentifier: String

    public init(
        densityKilogramsPerCubicMetre: Double,
        densityRootCount: Int,
        phaseIdentifier: String
    ) {
        self.densityKilogramsPerCubicMetre = densityKilogramsPerCubicMetre
        self.densityRootCount = densityRootCount
        self.phaseIdentifier = phaseIdentifier
    }
}

public protocol TeqpEngine: Sendable {
    var isAvailable: Bool { get }
    var libraryVersion: String { get }

    func calculatePureCarbonDioxide(
        pressurePa: Double,
        temperatureK: Double
    ) async throws -> TeqpEngineResult
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
}

public struct TeqpProvider<Engine: TeqpEngine>: ThermodynamicModelProvider {
    private let engine: Engine

    public init(engine: Engine) {
        self.engine = engine
    }

    public var descriptor: ModelDescriptor {
        ModelDescriptor(
            id: "teqp-pure-co2-experimental",
            name: "Advanced Phase & Mixture Model (teqp)",
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
            scientificBasis: "Native teqp multiparameter multifluid model for pure carbon dioxide only.",
            equationOrMethod: "teqp multifluid pure-CO₂ model loaded from the pinned upstream CarbonDioxide.json data; density is solved from P,T and subcritical multiple-root states use teqp pure-fluid VLE pressure and chemical-potential equality to select the stable vapor or liquid branch away from saturation.",
            coefficientSetVersion: TeqpFormulationCatalog.pureCarbonDioxide.provenance,
            requiredResources: ["PhaseXpertTeqpBridge.xcframework"],
            limitations: [
                "Experimental local provider; no production accuracy claim.",
                "Only exactly 100 mol% CO₂ is supported.",
                "CO₂ mixtures, including CO₂+N₂, are unsupported and never fall back to CoolProp.",
                "Dynamic viscosity and all transport properties are unavailable for this provider.",
                "Subcritical states on or too close to pure-CO₂ saturation are reported as unavailable because they do not have a unique homogeneous bulk density.",
                "Phase classification is limited to stable vapor, stable liquid, and supercritical states that the bridge can identify robustly; otherwise the phase remains unknown.",
                "Phase-envelope generation is unavailable in this teqp milestone."
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
                )
            ]
        )
    }

    public func applicabilityIssues(
        for composition: [MixtureComponent]
    ) -> [ValidationIssue] {
        guard !isPureCarbonDioxide(composition) else { return [] }
        return [
            ValidationIssue(
                code: .componentOutsideModelRange,
                severity: .error,
                message: "The experimental teqp provider supports only exactly 100 mol% CO₂. Mixtures are unsupported and are not routed to CoolProp."
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
        guard isPureCarbonDioxide(request.composition) else {
            throw ProviderError.invalidRequest(
                "The experimental teqp provider supports only exactly 100 mol% CO₂. No CoolProp fallback is used."
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
                derivedByProperty[property] ?? propertyValue(for: property, density: raw.densityKilogramsPerCubicMetre)
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
        PhaseEnvelopeResponse(
            requestID: request.requestID,
            points: [],
            warnings: [
                "The experimental teqp provider does not expose phase-envelope generation in this milestone."
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

    private func propertyValue(
        for property: PropertyID,
        density: Double
    ) -> PropertyValue {
        switch property {
        case .density:
            PropertyValue(
                property: property,
                value: density,
                unit: "kg/m³",
                status: .calculated,
                message: "Native teqp pure-CO₂ density from P,T with stable-root selection where required."
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
}
