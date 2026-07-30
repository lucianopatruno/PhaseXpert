import Foundation

public enum PressureUnit: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case pascal = "Pa"
    case kilopascal = "kPa"
    case megapascal = "MPa"
    case bar = "bar"
    case bara = "bara"
    case barg = "barg"
    case psi = "psi"
    case psia = "psia"

    public var id: String { rawValue }

    public var isGauge: Bool { self == .barg }

    public func toPascal(
        _ value: Double,
        atmosphericReferencePa: Double = UnitConstants.standardAtmospherePa
    ) -> Double {
        switch self {
        case .pascal: value
        case .kilopascal: value * 1_000
        case .megapascal: value * 1_000_000
        case .bar, .bara: value * 100_000
        case .barg: value * 100_000 + atmosphericReferencePa
        case .psi, .psia: value * UnitConstants.psiToPascal
        }
    }

    public func fromPascal(
        _ value: Double,
        atmosphericReferencePa: Double = UnitConstants.standardAtmospherePa
    ) -> Double {
        switch self {
        case .pascal: value
        case .kilopascal: value / 1_000
        case .megapascal: value / 1_000_000
        case .bar, .bara: value / 100_000
        case .barg: (value - atmosphericReferencePa) / 100_000
        case .psi, .psia: value / UnitConstants.psiToPascal
        }
    }
}

public enum TemperatureUnit: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case kelvin = "K"
    case celsius = "°C"
    case fahrenheit = "°F"

    public var id: String { rawValue }

    public func toKelvin(_ value: Double) -> Double {
        switch self {
        case .kelvin: value
        case .celsius: value + 273.15
        case .fahrenheit: (value - 32) * 5 / 9 + 273.15
        }
    }

    public func fromKelvin(_ value: Double) -> Double {
        switch self {
        case .kelvin: value
        case .celsius: value - 273.15
        case .fahrenheit: (value - 273.15) * 9 / 5 + 32
        }
    }
}

public enum CompositionUnit: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case moleFraction = "Mole fraction"
    case molePercent = "mol%"
    case massFraction = "Mass fraction"

    public var id: String { rawValue }
}

public enum DynamicViscosityUnit: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case pascalSecond = "Pa·s"
    case millipascalSecond = "mPa·s"

    public var id: String { rawValue }

    public func fromPascalSeconds(_ value: Double) -> Double {
        switch self {
        case .pascalSecond: value
        case .millipascalSecond: value * 1_000
        }
    }

    public func toPascalSeconds(_ value: Double) -> Double {
        switch self {
        case .pascalSecond: value
        case .millipascalSecond: value / 1_000
        }
    }
}

public enum UnitConstants {
    public static let standardAtmospherePa = 101_325.0
    public static let psiToPascal = 6_894.757_293_168
}
