import Observation
import PhaseXpertCore

/// What the Impurity Reactions screen shows for the current input.
enum ImpurityReactionsOutcome: Equatable {
    /// Nothing has been entered yet.
    case empty
    /// A field holds text that is not a number. No result is shown.
    case unreadable(ImpurityReactionSpecies)
    /// The model rejected the values, with its own explanation.
    case rejected(String)
    case result(ToCoMoResult)
}

/// Holds the five ppm fields and recomputes the ToCoMo result from them.
///
/// The model is instantaneous, so the result follows the text directly: there is
/// no stale state to track. Nothing is stored, exported or sent anywhere.
@MainActor
@Observable
final class ImpurityReactionsViewModel {
    var texts: [ImpurityReactionSpecies: String] = [:]

    /// A blank field counts as 0 ppm. Anything else must parse as a number;
    /// a comma is accepted as the decimal separator.
    static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }

    var outcome: ImpurityReactionsOutcome {
        var values: [ImpurityReactionSpecies: Double] = [:]
        var enteredAnything = false
        for species in ToCoMoInput.species {
            let text = (texts[species] ?? "").trimmingCharacters(in: .whitespaces)
            if text.isEmpty {
                values[species] = 0
                continue
            }
            guard let value = Self.parse(text) else { return .unreadable(species) }
            enteredAnything = true
            values[species] = value
        }
        guard enteredAnything else { return .empty }

        let input = ToCoMoInput(
            oxygenPpm: values[.oxygen] ?? 0,
            waterPpm: values[.water] ?? 0,
            hydrogenSulfidePpm: values[.hydrogenSulfide] ?? 0,
            sulfurDioxidePpm: values[.sulfurDioxide] ?? 0,
            nitrogenDioxidePpm: values[.nitrogenDioxide] ?? 0
        )
        do {
            return .result(try ToCoMoModel.run(input))
        } catch {
            return .rejected(error.localizedDescription)
        }
    }

    func clear() {
        texts = [:]
    }
}
