import Foundation

// ToCoMo (Total Consumption Model) port.
//
// This is a line-for-line port of `run_model_sm1` and the reaction list in
// `tocomo/reactions.py` from https://github.com/equinor/tocomo (MIT, © 2025
// Equinor), commit 74e23131bd27d63dcf71b4a62eb81cdb76d981c9. The algorithm is
// described by the repository as implemented "as described by Sven Morten
// Hesjevik and Anne Marie Koren Halvorsen".
//
// It is a stoichiometric heuristic: reactions are applied in a fixed priority
// order until the reactants are consumed. It has no temperature, pressure,
// equilibrium, kinetic or phase-separation content and is NOT validated by
// PhaseXpert. Do not add reactions, change the order or the cutoff without the
// reference changing first; the tests compare against the reference output.

/// Species that take part in the ToCoMo reactions.
public enum ImpurityReactionSpecies: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case sulfuricAcid = "H2SO4"
    case nitricAcid = "HNO3"
    case nitrousAcid = "HNO2"
    case sulfurDioxide = "SO2"
    case nitrogenDioxide = "NO2"
    case hydrogenSulfide = "H2S"
    case water = "H2O"
    case elementalSulfur = "S8"
    case oxygen = "O2"
    case nitricOxide = "NO"

    /// Formula with Unicode subscripts, as used for display.
    public var displaySymbol: String {
        switch self {
        case .sulfuricAcid: "H₂SO₄"
        case .nitricAcid: "HNO₃"
        case .nitrousAcid: "HNO₂"
        case .sulfurDioxide: "SO₂"
        case .nitrogenDioxide: "NO₂"
        case .hydrogenSulfide: "H₂S"
        case .water: "H₂O"
        case .elementalSulfur: "S₈"
        case .oxygen: "O₂"
        case .nitricOxide: "NO"
        }
    }

    /// Atom counts per molecule, used to check that every reaction is balanced.
    public var atoms: [String: Int] {
        switch self {
        case .sulfuricAcid: ["H": 2, "S": 1, "O": 4]
        case .nitricAcid: ["H": 1, "N": 1, "O": 3]
        case .nitrousAcid: ["H": 1, "N": 1, "O": 2]
        case .sulfurDioxide: ["S": 1, "O": 2]
        case .nitrogenDioxide: ["N": 1, "O": 2]
        case .hydrogenSulfide: ["H": 2, "S": 1]
        case .water: ["H": 2, "O": 1]
        case .elementalSulfur: ["S": 8]
        case .oxygen: ["O": 2]
        case .nitricOxide: ["N": 1, "O": 1]
        }
    }
}

/// The five impurities PhaseXpert lets the user enter, in mole ppm (µmol/mol)
/// of the stream. CO₂ is the remainder and is not part of the model.
public struct ToCoMoInput: Codable, Equatable, Sendable {
    public static let maximumTotalPpm = 1_000_000.0

    public var oxygenPpm: Double
    public var waterPpm: Double
    public var hydrogenSulfidePpm: Double
    public var sulfurDioxidePpm: Double
    public var nitrogenDioxidePpm: Double

    public init(
        oxygenPpm: Double = 0,
        waterPpm: Double = 0,
        hydrogenSulfidePpm: Double = 0,
        sulfurDioxidePpm: Double = 0,
        nitrogenDioxidePpm: Double = 0
    ) {
        self.oxygenPpm = oxygenPpm
        self.waterPpm = waterPpm
        self.hydrogenSulfidePpm = hydrogenSulfidePpm
        self.sulfurDioxidePpm = sulfurDioxidePpm
        self.nitrogenDioxidePpm = nitrogenDioxidePpm
    }

    /// The species the model accepts as input.
    public static let species: [ImpurityReactionSpecies] = [
        .water, .oxygen, .hydrogenSulfide, .sulfurDioxide, .nitrogenDioxide
    ]

    public func value(for species: ImpurityReactionSpecies) -> Double? {
        switch species {
        case .oxygen: oxygenPpm
        case .water: waterPpm
        case .hydrogenSulfide: hydrogenSulfidePpm
        case .sulfurDioxide: sulfurDioxidePpm
        case .nitrogenDioxide: nitrogenDioxidePpm
        default: nil
        }
    }

    public var totalPpm: Double {
        oxygenPpm + waterPpm + hydrogenSulfidePpm + sulfurDioxidePpm + nitrogenDioxidePpm
    }
}

/// One stoichiometric term, such as the `3 NO₂` in `H₂S + 3 NO₂ → …`.
public struct ToCoMoTerm: Equatable, Sendable {
    public let coefficient: Int
    public let species: ImpurityReactionSpecies

    public init(_ coefficient: Int, _ species: ImpurityReactionSpecies) {
        self.coefficient = coefficient
        self.species = species
    }
}

public struct ToCoMoReaction: Equatable, Sendable, Identifiable {
    public let index: Int
    public let reactants: [ToCoMoTerm]
    public let products: [ToCoMoTerm]
    /// Inactive reactions are part of the reference list but are never applied.
    public let isActive: Bool

    public var id: Int { index }

    /// Human-readable form, for example `H₂S + 3 NO₂ → SO₂ + H₂O + 3 NO`.
    public var displayText: String {
        "\(Self.text(reactants)) → \(Self.text(products))"
    }

    private static func text(_ terms: [ToCoMoTerm]) -> String {
        terms.map { $0.coefficient == 1 ? $0.species.displaySymbol : "\($0.coefficient) \($0.species.displaySymbol)" }
            .joined(separator: " + ")
    }
}

/// The concentrations after one reaction was applied.
public struct ToCoMoStep: Equatable, Sendable, Identifiable {
    public let order: Int
    public let reactionIndex: Int
    public let multiplier: Double
    public let concentrationsPpm: [ImpurityReactionSpecies: Double]

    public var id: Int { order }
}

public struct ToCoMoResult: Equatable, Sendable {
    public let input: ToCoMoInput
    public let initialPpm: [ImpurityReactionSpecies: Double]
    public let finalPpm: [ImpurityReactionSpecies: Double]
    public let steps: [ToCoMoStep]

    /// `false` when no reaction could be applied: the stream is returned unchanged.
    public var reactionApplied: Bool { !steps.isEmpty }
}

public enum ToCoMoError: Error, Equatable, Sendable {
    case invalidValue(ImpurityReactionSpecies, Double)
    case totalExceedsLimit(Double)
    case didNotTerminate(steps: Int)
}

extension ToCoMoError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .invalidValue(species, value):
            "\(species.displaySymbol) must be a finite number of at least 0 ppm; received \(value)."
        case let .totalExceedsLimit(total):
            "The impurities add up to \(total) ppm, which exceeds 1,000,000 ppm. CO₂ is the remainder and is not normalized silently."
        case let .didNotTerminate(steps):
            "The reaction sequence did not finish within \(steps) steps, so no result is reported."
        }
    }
}

/// Where the model comes from, for in-app attribution and tests.
public struct ToCoMoReference: Equatable, Sendable {
    public let name: String
    public let repository: URL
    public let commit: String
    public let licence: String
    public let copyright: String
    public let attribution: String
}

public enum ToCoMoModel {
    /// A reaction is skipped when its limiting multiplier is below this value (ppm).
    public static let minimumMultiplier = 0.001
    /// Guard against a runaway loop. The reference has no limit; real inputs finish
    /// in far fewer steps, and hitting the guard is reported, never hidden.
    public static let maximumSteps = 100_000

    public static let reference = ToCoMoReference(
        name: "ToCoMo (Total Consumption Model)",
        repository: URL(string: "https://github.com/equinor/tocomo")!,
        commit: "74e23131bd27d63dcf71b4a62eb81cdb76d981c9",
        licence: "MIT",
        copyright: "Copyright (c) 2025 Equinor",
        attribution: "Algorithm as described by Sven Morten Hesjevik and Anne Marie Koren Halvorsen"
    )

    /// Reactions in the priority order of the reference implementation.
    public static let reactions: [ToCoMoReaction] = [
        ToCoMoReaction(
            index: 3,
            reactants: [.init(1, .hydrogenSulfide), .init(3, .nitrogenDioxide)],
            products: [.init(1, .sulfurDioxide), .init(1, .water), .init(3, .nitricOxide)],
            isActive: true
        ),
        ToCoMoReaction(
            index: 2,
            reactants: [.init(2, .nitricOxide), .init(1, .oxygen)],
            products: [.init(2, .nitrogenDioxide)],
            isActive: true
        ),
        ToCoMoReaction(
            index: 1,
            reactants: [.init(1, .nitrogenDioxide), .init(1, .sulfurDioxide), .init(1, .water)],
            products: [.init(1, .nitricOxide), .init(1, .sulfuricAcid)],
            isActive: true
        ),
        ToCoMoReaction(
            index: 4,
            reactants: [.init(3, .nitrogenDioxide), .init(1, .water)],
            products: [.init(2, .nitricAcid), .init(1, .nitricOxide)],
            isActive: true
        ),
        ToCoMoReaction(
            index: 5,
            reactants: [.init(2, .nitrogenDioxide), .init(1, .water)],
            products: [.init(1, .nitricAcid), .init(1, .nitrousAcid)],
            isActive: false
        ),
        ToCoMoReaction(
            index: 6,
            reactants: [.init(8, .hydrogenSulfide), .init(4, .oxygen)],
            products: [.init(8, .water), .init(1, .elementalSulfur)],
            isActive: true
        )
    ]

    public static func validate(_ input: ToCoMoInput) throws {
        for species in ToCoMoInput.species {
            let value = input.value(for: species) ?? 0
            guard value.isFinite, value >= 0 else {
                throw ToCoMoError.invalidValue(species, value)
            }
        }
        guard input.totalPpm <= ToCoMoInput.maximumTotalPpm else {
            throw ToCoMoError.totalExceedsLimit(input.totalPpm)
        }
    }

    /// Runs the reaction sequence. Concentrations stay in ppm of the initial stream:
    /// the reference does not renormalize after reactions change the mole count.
    public static func run(_ input: ToCoMoInput) throws -> ToCoMoResult {
        try validate(input)

        var concentrations: [ImpurityReactionSpecies: Double] = [:]
        for species in ImpurityReactionSpecies.allCases {
            concentrations[species] = input.value(for: species) ?? 0
        }
        let initial = concentrations

        var steps: [ToCoMoStep] = []
        var applied = true
        while applied {
            applied = false
            for reaction in reactions where reaction.isActive {
                let multiplier = reaction.reactants
                    .map { (concentrations[$0.species] ?? 0) / Double($0.coefficient) }
                    .min() ?? 0
                if multiplier < minimumMultiplier { continue }

                for term in reaction.reactants {
                    concentrations[term.species, default: 0] -= multiplier * Double(term.coefficient)
                }
                for term in reaction.products {
                    concentrations[term.species, default: 0] += multiplier * Double(term.coefficient)
                }
                steps.append(
                    ToCoMoStep(
                        order: steps.count + 1,
                        reactionIndex: reaction.index,
                        multiplier: multiplier,
                        concentrationsPpm: concentrations
                    )
                )
                guard steps.count < maximumSteps else {
                    throw ToCoMoError.didNotTerminate(steps: steps.count)
                }
                applied = true
                break
            }
        }

        return ToCoMoResult(
            input: input,
            initialPpm: initial,
            finalPpm: concentrations,
            steps: steps
        )
    }
}
