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
