import Foundation

public enum PhaseDiagramEligibility: Equatable, Sendable {
    case pureCarbonDioxide
    case multicomponent
    case invalidComposition

    public static let title = "Phase diagram"
    public static let pureCarbonDioxideScopeMessage =
        "Phase diagrams are available for pure CO₂. Remove all impurities to view the CO₂ phase diagram."
    public static let mixturePropertySupportMessage =
        "Property calculations for the selected mixture remain available."

    public static func evaluate(
        composition: [MixtureComponent]
    ) -> PhaseDiagramEligibility {
        guard !composition.isEmpty else {
            return .invalidComposition
        }
        guard composition.allSatisfy({
            $0.moleFraction.isFinite && $0.moleFraction >= 0
        }) else {
            return .invalidComposition
        }
        let grouped = Dictionary(grouping: composition, by: \.component)
        guard grouped.values.allSatisfy({ $0.count == 1 }) else {
            return .invalidComposition
        }

        let total = composition.reduce(0) { $0 + $1.moleFraction }
        guard total.isFinite,
              abs(total - 1) <= CalculationValidator.compositionTolerance
        else {
            return .invalidComposition
        }

        guard let carbonDioxide = composition.first(where: {
            $0.component == .carbonDioxide
        }) else {
            return .invalidComposition
        }
        guard abs(carbonDioxide.moleFraction - total)
                <= CalculationValidator.compositionTolerance
        else {
            return .multicomponent
        }

        let hasPositiveImpurity = composition.contains {
            $0.component != .carbonDioxide && $0.moleFraction > 0
        }
        return hasPositiveImpurity ? .multicomponent : .pureCarbonDioxide
    }

    public static func isPureCarbonDioxide(
        composition: [MixtureComponent]
    ) -> Bool {
        evaluate(composition: composition) == .pureCarbonDioxide
    }
}
