import Foundation

/// One original stream, never an automatically reacted or renormalized mixture.
public enum StreamScreeningSpecies: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case water, oxygen, hydrogenSulfide, sulfurDioxide, nitrogenDioxide
    case nitrogen, argon, methane, hydrogen, carbonMonoxide, helium, ethane, propane

    public var id: String { rawValue }
    public var symbol: String {
        switch self {
        case .sulfurDioxide: "SO₂"
        case .nitrogenDioxide: "NO₂"
        default: componentID?.symbol ?? rawValue
        }
    }
    public var componentID: ComponentID? {
        switch self {
        case .water: .water
        case .oxygen: .oxygen
        case .hydrogenSulfide: .hydrogenSulfide
        case .nitrogen: .nitrogen
        case .argon: .argon
        case .methane: .methane
        case .hydrogen: .hydrogen
        case .carbonMonoxide: .carbonMonoxide
        case .helium: .helium
        case .ethane: .ethane
        case .propane: .propane
        case .sulfurDioxide, .nitrogenDioxide: nil
        }
    }
}

public struct StreamScreeningInput: Equatable, Sendable {
    public let pressurePa: Double
    public let temperatureK: Double
    public let impurityPpm: [StreamScreeningSpecies: Double]
    /// Explicit permission to inspect a hypothetical binary reference. This never
    /// expands the supported domain of the original stream's water assessment.
    public let includeBinaryWaterReference: Bool

    public init(pressurePa: Double, temperatureK: Double,
                impurityPpm: [StreamScreeningSpecies: Double],
                includeBinaryWaterReference: Bool = false) {
        self.pressurePa = pressurePa
        self.temperatureK = temperatureK
        self.impurityPpm = impurityPpm
        self.includeBinaryWaterReference = includeBinaryWaterReference
    }
    public var totalImpurityPpm: Double {
        StreamScreeningSpecies.allCases.reduce(0) { $0 + (impurityPpm[$1] ?? 0) }
    }
    public var carbonDioxidePpm: Double { 1_000_000 - totalImpurityPpm }
    public var activeImpurities: [StreamScreeningSpecies] {
        StreamScreeningSpecies.allCases.filter { (impurityPpm[$0] ?? 0) > 0 }
    }
    public var isBinaryWaterStream: Bool {
        activeImpurities == [.water]
    }
    public func validate() throws {
        guard pressurePa.isFinite, pressurePa > 0,
              temperatureK.isFinite, temperatureK > 0 else {
            throw StreamScreeningInputError.invalidOperatingPoint
        }
        for species in StreamScreeningSpecies.allCases {
            let value = impurityPpm[species] ?? 0
            guard value.isFinite, value >= 0 else {
                throw StreamScreeningInputError.invalidConcentration(species)
            }
        }
        guard totalImpurityPpm.isFinite, totalImpurityPpm < 1_000_000 else {
            throw StreamScreeningInputError.noCarbonDioxideRemainder
        }
    }
    public var reactionInput: ToCoMoInput {
        ToCoMoInput(oxygenPpm: impurityPpm[.oxygen] ?? 0,
                    waterPpm: impurityPpm[.water] ?? 0,
                    hydrogenSulfidePpm: impurityPpm[.hydrogenSulfide] ?? 0,
                    sulfurDioxidePpm: impurityPpm[.sulfurDioxide] ?? 0,
                    nitrogenDioxidePpm: impurityPpm[.nitrogenDioxide] ?? 0)
    }
    /// No composition is returned if even one input species cannot be represented.
    /// Unsupported SO₂/NO₂ are never silently discarded to obtain EOS results.
    public func thermophysicalComposition() throws -> [MixtureComponent] {
        try validate()
        guard !activeImpurities.contains(where: { $0.componentID == nil }) else {
            throw StreamScreeningInputError.unmappedThermophysicalSpecies
        }
        return [MixtureComponent(component: .carbonDioxide, moleFraction: carbonDioxidePpm / 1_000_000)]
            + activeImpurities.compactMap { species in
                species.componentID.map {
                    MixtureComponent(component: $0, moleFraction: (impurityPpm[species] ?? 0) / 1_000_000)
                }
            }
    }
}

public enum StreamScreeningInputError: Error, Equatable, Sendable, LocalizedError {
    case invalidOperatingPoint
    case invalidConcentration(StreamScreeningSpecies)
    case noCarbonDioxideRemainder
    case unmappedThermophysicalSpecies

    public var errorDescription: String? {
        switch self {
        case .invalidOperatingPoint: "Enter a finite pressure above 0 bar(a) and temperature above absolute zero."
        case .invalidConcentration(let species): "\(species.symbol) must be a finite, non-negative ppm value."
        case .noCarbonDioxideRemainder: "Total impurities must be below 1,000,000 ppm so that CO₂ remains present. Inputs are not normalized."
        case .unmappedThermophysicalSpecies: "SO₂ and NO₂ are not supported by the thermophysical engine. No impurity was removed or substituted."
        }
    }
}

public struct StreamScreeningIssue: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case unsupportedComposition, outsideDomain, modelUnavailable, calculationFailed, noWater
    }
    public let kind: Kind
    public let message: String
    public init(_ kind: Kind, _ message: String) {
        self.kind = kind
        self.message = message
    }
}

public enum StreamReactionOutcome: Equatable, Sendable {
    case result(ToCoMoResult)
    case unavailable(StreamScreeningIssue)
}

public enum StreamThermophysicalOutcome: Equatable, Sendable {
    case result(CalculationResponse)
    case unavailable(StreamScreeningIssue)
}

public enum StreamWaterOutcome: Equatable, Sendable {
    case result(CarbonDioxideWaterEquilibriumResult)
    case unavailable(StreamScreeningIssue)
}

public struct StreamScreeningResult: Equatable, Sendable {
    public let input: StreamScreeningInput
    public let reactions: StreamReactionOutcome
    public let thermophysical: StreamThermophysicalOutcome
    /// Applies to the original stream only when it is binary CO₂ + H₂O.
    public let streamWater: StreamWaterOutcome
    /// A separate hypothetical stream: same original H₂O ppm, all other material
    /// treated as CO₂. This is not the reacted stream or a mixture prediction.
    public let binaryWaterReference: StreamWaterOutcome?
    public let generatedAt: Date

    public var reactionResult: ToCoMoResult? {
        if case .result(let result) = reactions { return result }
        return nil
    }
    /// nil means unassessed, never a negative acid-formation conclusion.
    public var acidFormationEstimated: Bool? {
        guard let result = reactionResult else { return nil }
        return (result.finalPpm[.sulfuricAcid] ?? 0) > 0
            || (result.finalPpm[.nitricAcid] ?? 0) > 0
            || (result.finalPpm[.nitrousAcid] ?? 0) > 0
    }
    public var binaryReferenceWaterExpected: Bool {
        if case .result(let water) = binaryWaterReference {
            return water.waterStatus == .aqueousWaterExpected
        }
        return false
    }
}

/// Coordinates existing models without coupling chemistry and phase equilibrium.
/// Every model receives inputs on the original stream basis. No ToCoMo output is
/// ever fed into the EOS or water model, and no validation gate is broadened.
public struct StreamScreeningService: Sendable {
    private let provider: (any ThermodynamicModelProvider)?
    private let waterModel: any CarbonDioxideWaterEquilibriumEvaluating
    private let reactionModel: @Sendable (ToCoMoInput) throws -> ToCoMoResult

    public init(provider: (any ThermodynamicModelProvider)? = ProviderRegistry().provider(id: "coolprop-heos"),
                waterModel: any CarbonDioxideWaterEquilibriumEvaluating = CarbonDioxideWaterEquilibrium.standard,
                reactionModel: @escaping @Sendable (ToCoMoInput) throws -> ToCoMoResult = ToCoMoModel.run) {
        self.provider = provider
        self.waterModel = waterModel
        self.reactionModel = reactionModel
    }

    public func screen(_ input: StreamScreeningInput, clientVersion: String) async throws -> StreamScreeningResult {
        try input.validate()
        try Task.checkCancellation()
        // Keep even bounded chemistry and water-boundary solving off the UI actor.
        let localTask = Task.detached(priority: .userInitiated) { [waterModel, reactionModel] in
            try Task.checkCancellation()
            let reactions: StreamReactionOutcome
            do { reactions = .result(try reactionModel(input.reactionInput)) }
            catch is CancellationError { throw CancellationError() }
            catch {
                reactions = .unavailable(.init(.calculationFailed,
                    "Reaction estimate unavailable: \(error.localizedDescription) No acid-formation conclusion is inferred."))
            }
            let streamWater: StreamWaterOutcome
            if (input.impurityPpm[.water] ?? 0) == 0 {
                streamWater = .unavailable(.init(.noWater, "No water was entered. Reaction-produced water is not passed to the water model."))
            } else if input.isBinaryWaterStream {
                streamWater = Self.waterOutcome(input, model: waterModel)
            } else {
                streamWater = .unavailable(.init(.unsupportedComposition,
                    "Water dropout for this mixture is not assessed: the water model supports binary CO₂ + H₂O only. No other impurity has been removed."))
            }
            let reference: StreamWaterOutcome? = input.includeBinaryWaterReference && !input.isBinaryWaterStream
                && (input.impurityPpm[.water] ?? 0) > 0
                ? Self.waterOutcome(input, model: waterModel) : nil
            try Task.checkCancellation()
            return (reactions, streamWater, reference)
        }
        let local = try await withTaskCancellationHandler {
            try await localTask.value
        } onCancel: { localTask.cancel() }
        try Task.checkCancellation()
        let properties = try await thermophysicalOutcome(input, clientVersion: clientVersion)
        try Task.checkCancellation()
        return StreamScreeningResult(input: input, reactions: local.0, thermophysical: properties,
            streamWater: local.1, binaryWaterReference: local.2, generatedAt: Date())
    }

    private static func waterOutcome(_ input: StreamScreeningInput,
                                     model: any CarbonDioxideWaterEquilibriumEvaluating) -> StreamWaterOutcome {
        do {
            return .result(try model.equilibrium(pressurePa: input.pressurePa,
                temperatureK: input.temperatureK,
                currentWaterMoleFraction: (input.impurityPpm[.water] ?? 0) / 1_000_000))
        } catch let error as CarbonDioxideWaterEquilibriumError {
            let kind: StreamScreeningIssue.Kind = error == .outsideValidatedDomain ? .outsideDomain : .calculationFailed
            return .unavailable(.init(kind, "Water calculation unavailable: \(error.failureDescription). Supported ranges: \(model.validatedRangeSummary)"))
        } catch {
            return .unavailable(.init(.calculationFailed, "Water calculation failed; no result is inferred."))
        }
    }

    private func thermophysicalOutcome(_ input: StreamScreeningInput,
                                       clientVersion: String) async throws -> StreamThermophysicalOutcome {
        let composition: [MixtureComponent]
        do { composition = try input.thermophysicalComposition() }
        catch {
            return .unavailable(.init(.unsupportedComposition, error.localizedDescription))
        }
        guard let provider, provider.descriptor.availability != .unavailable else {
            return .unavailable(.init(.modelUnavailable, "General Properties is unavailable in this build. The other screening results remain independent."))
        }
        let unsupported = composition.filter { !provider.descriptor.supportedComponents.contains($0.component) }
        guard unsupported.isEmpty else {
            return .unavailable(.init(.unsupportedComposition,
                "General Properties does not support all original stream components: \(unsupported.map { $0.component.symbol }.joined(separator: ", ")). No component was omitted."))
        }
        do {
            let response = try await provider.calculate(CalculationRequest(modelID: provider.descriptor.id,
                pressurePa: input.pressurePa, temperatureK: input.temperatureK,
                composition: composition, clientVersion: clientVersion))
            return .result(response)
        } catch is CancellationError { throw CancellationError() }
        catch let error as ProviderError {
            switch error {
            case .cancelled: throw CancellationError()
            case .invalidRequest(let message): return .unavailable(.init(.unsupportedComposition, message))
            case .unsupportedComponent(let component): return .unavailable(.init(.unsupportedComposition, "Unsupported component: \(component.symbol). No substitute calculation was performed."))
            case .modelUnavailable(let message): return .unavailable(.init(.modelUnavailable, message))
            case .timeout: return .unavailable(.init(.calculationFailed, "General Properties timed out; no result is inferred."))
            case .malformedResponse(let message): return .unavailable(.init(.calculationFailed, message))
            }
        } catch {
            return .unavailable(.init(.calculationFailed, "General Properties failed; no result is inferred."))
        }
    }
}
