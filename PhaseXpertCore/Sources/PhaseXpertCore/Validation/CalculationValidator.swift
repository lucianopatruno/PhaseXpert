import Foundation

public enum ValidationSeverity: String, Codable, Equatable, Sendable {
    case warning
    case error
}

public enum ValidationCode: String, Codable, Equatable, Sendable {
    case modelUnavailable
    case nonFiniteInput
    case negativeComposition
    case duplicateComponent
    case tooManyImpurities
    case missingCarbonDioxide
    case carbonDioxideNotLargest
    case compositionTotal
    case normalizationAvailable
    case pressureOutsideDomain
    case temperatureOutsideDomain
    case unsupportedComponent
    case componentOutsideModelRange
}

public struct ValidationIssue: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "\(code.rawValue):\(message)" }
    public let code: ValidationCode
    public let severity: ValidationSeverity
    public let message: String

    public init(code: ValidationCode, severity: ValidationSeverity, message: String) {
        self.code = code
        self.severity = severity
        self.message = message
    }
}

public struct ValidationReport: Codable, Equatable, Sendable {
    public let issues: [ValidationIssue]
    public let normalizedComposition: [MixtureComponent]?

    public var canCalculate: Bool {
        !issues.contains { $0.severity == .error }
    }

    public init(issues: [ValidationIssue], normalizedComposition: [MixtureComponent]?) {
        self.issues = issues
        self.normalizedComposition = normalizedComposition
    }
}

public struct ScientificDomain: Codable, Equatable, Sendable {
    public let minimumPressurePa: Double
    public let maximumPressurePa: Double
    public let minimumTemperatureK: Double
    public let maximumTemperatureK: Double

    public init(
        minimumPressurePa: Double,
        maximumPressurePa: Double,
        minimumTemperatureK: Double,
        maximumTemperatureK: Double
    ) {
        self.minimumPressurePa = minimumPressurePa
        self.maximumPressurePa = maximumPressurePa
        self.minimumTemperatureK = minimumTemperatureK
        self.maximumTemperatureK = maximumTemperatureK
    }

    public static let initialCO2Transport = ScientificDomain(
        minimumPressurePa: 80_000,
        maximumPressurePa: 30_000_000,
        minimumTemperatureK: 218.15,
        maximumTemperatureK: 423.15
    )
}

public struct CalculationValidator: Sendable {
    /// Exact-total acceptance tolerance: 0.01 mol%.
    public static let compositionTolerance = 0.0001
    /// Normalization may be offered up to a deviation of 0.1 mol%.
    public static let normalizationTolerance = 0.001

    public init() {}

    public func validate(
        pressurePa: Double,
        temperatureK: Double,
        composition: [MixtureComponent],
        supportedComponents: Set<ComponentID>,
        domain: ScientificDomain
    ) -> ValidationReport {
        var issues: [ValidationIssue] = []
        let allValues = [pressurePa, temperatureK] + composition.map(\.moleFraction)

        if allValues.contains(where: { !$0.isFinite }) {
            issues.append(.init(
                code: .nonFiniteInput,
                severity: .error,
                message: "Pressure, temperature, and composition must be finite numbers."
            ))
        }

        if composition.contains(where: { $0.moleFraction < 0 }) {
            issues.append(.init(
                code: .negativeComposition,
                severity: .error,
                message: "Composition values cannot be negative."
            ))
        }

        let grouped = Dictionary(grouping: composition, by: \.component)
        if grouped.values.contains(where: { $0.count > 1 }) {
            issues.append(.init(
                code: .duplicateComponent,
                severity: .error,
                message: "Each component may appear only once."
            ))
        }

        let impurityCount = composition.filter { $0.component != .carbonDioxide }.count
        if impurityCount > 20 {
            issues.append(.init(
                code: .tooManyImpurities,
                severity: .error,
                message: "A case may contain at most 20 impurity components."
            ))
        }

        guard let carbonDioxide = composition.first(where: { $0.component == .carbonDioxide }) else {
            issues.append(.init(
                code: .missingCarbonDioxide,
                severity: .error,
                message: "Carbon dioxide must be present."
            ))
            return ValidationReport(issues: issues, normalizedComposition: nil)
        }

        if composition.contains(where: {
            $0.component != .carbonDioxide && $0.moleFraction >= carbonDioxide.moleFraction
        }) {
            issues.append(.init(
                code: .carbonDioxideNotLargest,
                severity: .error,
                message: "CO₂ must be the unique largest component."
            ))
        }

        let unsupported = Set(composition.map(\.component)).subtracting(supportedComponents)
        if !unsupported.isEmpty {
            let names = unsupported.map(\.symbol).sorted().joined(separator: ", ")
            issues.append(.init(
                code: .unsupportedComponent,
                severity: .error,
                message: "The selected model does not support: \(names)."
            ))
        }

        let total = composition.reduce(0) { $0 + $1.moleFraction }
        let deviation = abs(total - 1)
        var normalized: [MixtureComponent]?

        if deviation > Self.compositionTolerance {
            if deviation <= Self.normalizationTolerance, total > 0 {
                normalized = composition.map {
                    MixtureComponent(component: $0.component, moleFraction: $0.moleFraction / total)
                }
                issues.append(.init(
                    code: .normalizationAvailable,
                    severity: .error,
                    message: "Composition totals \(total.formatted(.percent.precision(.fractionLength(4)))). Review and explicitly normalize before calculation."
                ))
            } else {
                issues.append(.init(
                    code: .compositionTotal,
                    severity: .error,
                    message: "Composition must total 100 mol% within ±0.01 mol%."
                ))
            }
        }

        if pressurePa < domain.minimumPressurePa || pressurePa > domain.maximumPressurePa {
            issues.append(.init(
                code: .pressureOutsideDomain,
                severity: .error,
                message: "Pressure is outside the selected model domain."
            ))
        }

        if temperatureK < domain.minimumTemperatureK || temperatureK > domain.maximumTemperatureK {
            issues.append(.init(
                code: .temperatureOutsideDomain,
                severity: .error,
                message: "Temperature is outside the selected model domain."
            ))
        }

        return ValidationReport(issues: issues, normalizedComposition: normalized)
    }
}
