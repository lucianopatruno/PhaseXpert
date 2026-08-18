import Foundation

/// Stable identifiers used by persistence and calculation-provider contracts.
public enum ComponentID: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case carbonDioxide = "co2"
    case nitrogen = "n2"
    case oxygen = "o2"
    case argon = "ar"
    case water = "h2o"
    case methane = "ch4"
    case hydrogen = "h2"
    case carbonMonoxide = "co"
    case hydrogenSulfide = "h2s"
    case helium = "he"
    case ethane = "c2h6"
    case propane = "c3h8"

    public var id: String { rawValue }

    public var symbol: String {
        switch self {
        case .carbonDioxide: "CO₂"
        case .nitrogen: "N₂"
        case .oxygen: "O₂"
        case .argon: "Ar"
        case .water: "H₂O"
        case .methane: "CH₄"
        case .hydrogen: "H₂"
        case .carbonMonoxide: "CO"
        case .hydrogenSulfide: "H₂S"
        case .helium: "He"
        case .ethane: "C₂H₆"
        case .propane: "C₃H₈"
        }
    }

    public var name: String {
        switch self {
        case .carbonDioxide: "Carbon dioxide"
        case .nitrogen: "Nitrogen"
        case .oxygen: "Oxygen"
        case .argon: "Argon"
        case .water: "Water"
        case .methane: "Methane"
        case .hydrogen: "Hydrogen"
        case .carbonMonoxide: "Carbon monoxide"
        case .hydrogenSulfide: "Hydrogen sulfide"
        case .helium: "Helium"
        case .ethane: "Ethane"
        case .propane: "Propane"
        }
    }

    /// Molar mass in kg/mol when a reviewed value is available.
    ///
    /// Values are from the NIST Chemistry WebBook, SRD 69. They are used only
    /// for transparent M = ΣxᵢMᵢ derivations, never as equation-of-state data.
    public var molarMassKilogramsPerMole: Double? {
        switch self {
        case .carbonDioxide: 0.044_009_5
        case .nitrogen: 0.028_013_4
        case .oxygen: 0.031_998_8
        case .argon: 0.039_948
        case .methane: 0.016_042_5
        case .hydrogen: 0.002_015_88
        case .carbonMonoxide: 0.028_010_1
        case .hydrogenSulfide: 0.034_081
        default: nil
        }
    }
}

public struct MixtureComponent: Codable, Equatable, Sendable, Identifiable {
    public var id: ComponentID { component }
    public let component: ComponentID
    public let moleFraction: Double

    public init(component: ComponentID, moleFraction: Double) {
        self.component = component
        self.moleFraction = moleFraction
    }
}
