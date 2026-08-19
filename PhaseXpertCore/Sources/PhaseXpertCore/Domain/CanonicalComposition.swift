import Foundation

public enum CanonicalCompositionError: Error, Equatable, Sendable {
    case empty
    case nonFinite(ComponentID)
    case negative(ComponentID)
    case duplicate(ComponentID)
    case total(Double)
}

/// Canonical mole-fraction composition used at provider boundaries.
///
/// This type preserves every supplied component, validates an exact total, and
/// only reorders by the stable ComponentID catalog order. It never normalizes,
/// drops zero-fraction entries, or rewrites component identity.
public struct CanonicalComposition: Equatable, Sendable {
    public let components: [MixtureComponent]

    public init(
        _ components: [MixtureComponent],
        tolerance: Double = CalculationValidator.compositionTolerance
    ) throws {
        guard !components.isEmpty else {
            throw CanonicalCompositionError.empty
        }

        var seen: Set<ComponentID> = []
        for entry in components {
            guard entry.moleFraction.isFinite else {
                throw CanonicalCompositionError.nonFinite(entry.component)
            }
            guard entry.moleFraction >= 0 else {
                throw CanonicalCompositionError.negative(entry.component)
            }
            guard seen.insert(entry.component).inserted else {
                throw CanonicalCompositionError.duplicate(entry.component)
            }
        }

        let total = components.reduce(0) { $0 + $1.moleFraction }
        guard abs(total - 1) <= tolerance else {
            throw CanonicalCompositionError.total(total)
        }

        let order = Dictionary(
            uniqueKeysWithValues: ComponentID.allCases.enumerated().map { index, component in
                (component, index)
            }
        )
        self.components = components.sorted {
            order[$0.component, default: Int.max] < order[$1.component, default: Int.max]
        }
    }

    public var componentSet: Set<ComponentID> {
        Set(components.map(\.component))
    }

    public func moleFraction(of component: ComponentID) -> Double? {
        components.first { $0.component == component }?.moleFraction
    }
}
