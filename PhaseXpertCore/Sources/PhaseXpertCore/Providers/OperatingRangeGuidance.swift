import Foundation

public struct OperatingGuidanceContext: Codable, Equatable, Sendable {
    public let pressurePa: Double?
    public let temperatureK: Double?
    public let composition: [MixtureComponent]
    public let requestedProperties: Set<PropertyID>

    public init(
        pressurePa: Double?,
        temperatureK: Double?,
        composition: [MixtureComponent],
        requestedProperties: Set<PropertyID> = Set(PropertyID.allCases)
    ) {
        self.pressurePa = pressurePa
        self.temperatureK = temperatureK
        self.composition = composition
        self.requestedProperties = requestedProperties
    }
}

public enum OperatingGuidanceSeverity: String, Codable, Equatable, Sendable {
    case information
    case warning
    case unsupported
}

public struct OperatingGuidanceLine: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "\(severity.rawValue):\(title):\(detail)" }
    public let severity: OperatingGuidanceSeverity
    public let title: String
    public let detail: String

    public init(
        severity: OperatingGuidanceSeverity,
        title: String,
        detail: String
    ) {
        self.severity = severity
        self.title = title
        self.detail = detail
    }
}

public enum OperatingGuidanceSuggestionAction: Codable, Equatable, Sendable {
    case setComposition(component: ComponentID, moleFraction: Double)
    case setTemperature(kelvin: Double)
}

public struct OperatingGuidanceSuggestion: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let action: OperatingGuidanceSuggestionAction

    public init(
        id: String,
        label: String,
        action: OperatingGuidanceSuggestionAction
    ) {
        self.id = id
        self.label = label
        self.action = action
    }
}

public struct OperatingRangeGuidance: Codable, Equatable, Sendable {
    public let title: String
    public let summary: [OperatingGuidanceLine]
    public let currentInputIssues: [OperatingGuidanceLine]
    public let propertyAvailability: [OperatingGuidanceLine]
    public let phaseDiagram: [OperatingGuidanceLine]
    public let suggestions: [OperatingGuidanceSuggestion]

    public init(
        title: String,
        summary: [OperatingGuidanceLine],
        currentInputIssues: [OperatingGuidanceLine] = [],
        propertyAvailability: [OperatingGuidanceLine] = [],
        phaseDiagram: [OperatingGuidanceLine] = [],
        suggestions: [OperatingGuidanceSuggestion] = []
    ) {
        self.title = title
        self.summary = summary
        self.currentInputIssues = currentInputIssues
        self.propertyAvailability = propertyAvailability
        self.phaseDiagram = phaseDiagram
        self.suggestions = suggestions
    }

    public var isEmpty: Bool {
        summary.isEmpty
            && currentInputIssues.isEmpty
            && propertyAvailability.isEmpty
            && phaseDiagram.isEmpty
            && suggestions.isEmpty
    }
}
