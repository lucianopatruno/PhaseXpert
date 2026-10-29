import PhaseXpertCore
import SwiftUI

struct ImpurityReactionsView: View {
    @Bindable var viewModel: ImpurityReactionsViewModel
    @FocusState private var focusedSpecies: ImpurityReactionSpecies?

    private static let formedSpecies: [ImpurityReactionSpecies] = [
        .sulfuricAcid, .nitricAcid, .elementalSulfur
    ]

    var body: some View {
        let outcome = viewModel.outcome

        IFEPage {
            ScientificStatusBanner(
                title: String(localized: "Preliminary estimate"),
                message: String(localized: "A stoichiometric heuristic that assumes the reactions run to completion. It is not a thermodynamic equilibrium calculation and has not been validated by PhaseXpert.")
            )
            .accessibilityIdentifier("impurity-reactions-preliminary")

            inputGroup(outcome)

            switch outcome {
            case .empty:
                Text("Enter the impurity amounts above to see what they could turn into.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("impurity-reactions-empty")
            case let .unreadable(species):
                ScientificStatusBanner(
                    title: String(localized: "Not a number"),
                    message: String(localized: "Enter a number for \(species.displaySymbol), or leave the field empty for 0 ppm."),
                    isError: true
                )
                .accessibilityIdentifier("impurity-reactions-error")
            case let .rejected(message):
                ScientificStatusBanner(
                    title: String(localized: "These values cannot be used"),
                    message: message,
                    isError: true
                )
                .accessibilityIdentifier("impurity-reactions-error")
            case let .result(result):
                resultSections(result)
            }

            aboutGroup
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Impurity Reactions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                // The decimal pad has no Return key, so step through the fields here.
                if let next = nextSpecies(after: focusedSpecies) {
                    Button("Next") { focusedSpecies = next }
                        .accessibilityIdentifier("impurity-reactions-keyboard-next")
                }
                Button("Done") { focusedSpecies = nil }
                    .accessibilityIdentifier("impurity-reactions-keyboard-done")
            }
        }
    }

    // MARK: - Input

    private func nextSpecies(after current: ImpurityReactionSpecies?) -> ImpurityReactionSpecies? {
        guard let current,
              let index = ToCoMoInput.species.firstIndex(of: current),
              index + 1 < ToCoMoInput.species.count
        else { return nil }
        return ToCoMoInput.species[index + 1]
    }

    private func inputGroup(_ outcome: ImpurityReactionsOutcome) -> some View {
        IFEGroup("Impurities in CO₂") {
            ForEach(Array(ToCoMoInput.species.enumerated()), id: \.element) { index, species in
                if index > 0 { Divider() }
                HStack(spacing: IFESpacing.regular) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(species.displaySymbol)
                            .font(.headline)
                        Text(Self.name(of: species))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: IFESpacing.small)
                    TextField(
                        "0",
                        text: Binding(
                            get: { viewModel.texts[species] ?? "" },
                            set: { viewModel.texts[species] = $0 }
                        )
                    )
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedSpecies, equals: species)
                    .frame(width: 104)
                    .padding(.horizontal, IFESpacing.small)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: IFECornerRadius.field, style: .continuous)
                            .fill(Color.ifeMist.opacity(0.55))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: IFECornerRadius.field, style: .continuous)
                            .stroke(
                                isUnreadable(species, in: outcome)
                                    ? Color.pxError
                                    : (focusedSpecies == species ? Color.ifePrimary : Color.secondary.opacity(0.22)),
                                lineWidth: focusedSpecies == species ? IFELine.focus : IFELine.hairline
                            )
                    }
                    .accessibilityLabel("\(species.displaySymbol), ppm")
                    .accessibilityIdentifier("impurity-reactions-input-\(species.rawValue)")
                    Text("ppm")
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .leading)
                        .accessibilityHidden(true)
                }
            }

            Text("Mole ppm (µmol/mol) of the stream. CO₂ is the remainder.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Clear", systemImage: "arrow.counterclockwise") {
                focusedSpecies = nil
                viewModel.clear()
            }
            .buttonStyle(.ifeTonal)
            .disabled(viewModel.texts.values.allSatisfy { $0.isEmpty })
            .accessibilityIdentifier("impurity-reactions-clear")
        }
    }

    private func isUnreadable(_ species: ImpurityReactionSpecies, in outcome: ImpurityReactionsOutcome) -> Bool {
        if case let .unreadable(bad) = outcome { return bad == species }
        return false
    }

    // MARK: - Results

    @ViewBuilder
    private func resultSections(_ result: ToCoMoResult) -> some View {
        if result.reactionApplied {
            IFEHeroCard(tint: .ifePeach) {
                VStack(alignment: .leading, spacing: IFESpacing.regular) {
                    Text("Formed")
                        .font(IFETypography.cardTitle)
                        .foregroundStyle(Color.ifeText)
                    HStack(spacing: IFESpacing.regular) {
                        ForEach(Self.formedSpecies, id: \.self) { species in
                            IFEMetricTile(
                                title: LocalizedStringKey(species.displaySymbol),
                                value: Self.format(change(of: species, in: result)),
                                unit: "ppm",
                                tint: .ifeCard
                            )
                        }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("impurity-reactions-result")
        } else {
            IFECard {
                VStack(alignment: .leading, spacing: IFESpacing.small) {
                    Label("No reaction could be applied", systemImage: "equal.circle")
                        .font(.headline)
                    Text("With these amounts no reaction in the sequence can start, so the stream is unchanged.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("impurity-reactions-no-reaction")
        }

        comparisonGroup(result)

        if result.reactionApplied {
            IFECard {
                IFEExpandableRow(String(localized: "Reaction steps (\(result.steps.count))")) {
                    stepsList(result)
                }
            }
            .accessibilityIdentifier("impurity-reactions-steps")
        }
    }

    private func comparisonGroup(_ result: ToCoMoResult) -> some View {
        let rows = ImpurityReactionSpecies.allCases.filter {
            abs(result.initialPpm[$0] ?? 0) > 1e-9 || abs(result.finalPpm[$0] ?? 0) > 1e-9
        }
        return IFEGroup("Initial and final") {
            Grid(alignment: .trailing, horizontalSpacing: IFESpacing.regular, verticalSpacing: IFESpacing.small) {
                GridRow {
                    Text("Species").gridColumnAlignment(.leading)
                    Text("Initial")
                    Text("Final")
                    Text("Change")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(rows, id: \.self) { species in
                    GridRow {
                        Text(species.displaySymbol)
                            .gridColumnAlignment(.leading)
                            .font(.subheadline.weight(.medium))
                        Text(Self.format(result.initialPpm[species] ?? 0))
                        Text(Self.format(result.finalPpm[species] ?? 0))
                        Text(Self.format(change(of: species, in: result), signed: true))
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline.monospacedDigit())
                }
            }
            Text("Values in ppm. A small NO₂ and NO residue can remain because the sequence stops once the next step is below 0.001 ppm.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("impurity-reactions-comparison")
    }

    private func stepsList(_ result: ToCoMoResult) -> some View {
        VStack(alignment: .leading, spacing: IFESpacing.regular) {
            ForEach(result.steps) { step in
                if let reaction = ToCoMoModel.reactions.first(where: { $0.index == step.reactionIndex }) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(step.order). \(reaction.displayText)")
                            .font(.subheadline)
                        Text("Reaction \(step.reactionIndex) × \(Self.format(step.multiplier))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(.top, IFESpacing.small)
    }

    // MARK: - About

    private var aboutGroup: some View {
        IFEGroup("About this model") {
            Text("Concentrations are tracked as the reactions are tried in a fixed order: the first reaction that has enough of its reactants is applied, and the list is tried again until nothing can react. It ignores temperature, pressure, reaction rates and any water or acid phase that could separate.")
                .font(.subheadline)
            Divider()
            IFEInfoRow("Model", value: Text(verbatim: "ToCoMo"))
            IFEInfoRow("Algorithm", value: Text("Sven Morten Hesjevik and Anne Marie Koren Halvorsen"))
            IFEInfoRow("Licence", value: Text(verbatim: "MIT, \(ToCoMoModel.reference.copyright)"))
            IFEInfoRow("Version", value: Text(verbatim: String(ToCoMoModel.reference.commit.prefix(7))))
            Link(destination: ToCoMoModel.reference.repository) {
                Label("ToCoMo on GitHub", systemImage: "arrow.up.right.square")
            }
            .accessibilityIdentifier("impurity-reactions-source-link")
            Text("PhaseXpert contains its own Swift version of this calculation and has not validated it. It runs on the device and sends nothing anywhere.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("impurity-reactions-about")
    }

    // MARK: - Helpers

    private func change(of species: ImpurityReactionSpecies, in result: ToCoMoResult) -> Double {
        (result.finalPpm[species] ?? 0) - (result.initialPpm[species] ?? 0)
    }

    private static func name(of species: ImpurityReactionSpecies) -> LocalizedStringKey {
        switch species {
        case .water: "Water"
        case .oxygen: "Oxygen"
        case .hydrogenSulfide: "Hydrogen sulfide"
        case .sulfurDioxide: "Sulfur dioxide"
        case .nitrogenDioxide: "Nitrogen dioxide"
        case .sulfuricAcid: "Sulfuric acid"
        case .nitricAcid: "Nitric acid"
        case .nitrousAcid: "Nitrous acid"
        case .elementalSulfur: "Elemental sulfur"
        case .nitricOxide: "Nitric oxide"
        }
    }

    /// Display only: floating-point dust below 1e-9 ppm is shown as 0.
    /// The values held in the result are never altered.
    private static func format(_ value: Double, signed: Bool = false) -> String {
        let shown = abs(value) < 1e-9 ? 0 : value
        let text = shown.formatted(.number.precision(.significantDigits(1...4)))
        return signed && shown > 0 ? "+\(text)" : text
    }
}
