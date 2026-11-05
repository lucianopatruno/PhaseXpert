import PhaseXpertCore
import SwiftUI

struct StreamScreeningView: View {
    @State private var viewModel: StreamScreeningViewModel
    @FocusState private var focusedField: String?

    init(viewModel: StreamScreeningViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        @Bindable var model = viewModel
        IFEPage {
            ScientificStatusBanner(
                title: String(localized: "Independent assessments • Preview"),
                message: String(localized: "One original stream, three separate assessments. Reaction estimates are not fed into property or water calculations. This is not a coupled equilibrium model or a corrosion-rate prediction.")
            )
            .accessibilityIdentifier("stream-screening-scope")

            operatingInputs
            compositionInputs

            IFEGroup("Water reference assumption") {
                Toggle("Include a binary CO₂–water reference", isOn: $model.includeBinaryWaterReference)
                    .accessibilityIdentifier("screening-binary-reference")
                Text("For mixtures, this optional reference keeps the original water ppm and treats all remaining material as CO₂. It excludes every other impurity and all reaction products. It does not predict water dropout for the actual mixture.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if let error = viewModel.inputError {
                Text(error).font(.caption).foregroundStyle(Color.pxError)
            }
            Button {
                focusedField = nil
                viewModel.run()
            } label: {
                Label(viewModel.isRunning ? String(localized: "Assessing…") : String(localized: "Run assessments"), systemImage: "checklist")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.input == nil || viewModel.isRunning)
            .accessibilityIdentifier("run-stream-screening")

            if viewModel.isRunning { ProgressView().accessibilityLabel("Assessments in progress") }
            if let error = viewModel.errorMessage {
                Text(error).foregroundStyle(Color.pxError).accessibilityIdentifier("screening-error")
            }
            if let result = viewModel.result {
                StreamScreeningResultsView(result: result)
                    .accessibilityIdentifier("screening-results")
            }
            Text("All assessments use the input composition before reaction. No result means no conclusion; unavailable calculations do not imply a safe stream.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .navigationTitle("Reactions & Water")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
        .onDisappear { viewModel.cancel() }
    }

    private var operatingInputs: some View {
        IFEGroup("Operating point") {
            inputRow("Pressure", unit: "bar(a)", text: $viewModel.pressureText, id: "screening-pressure")
            Divider()
            inputRow("Temperature", unit: "°C", text: $viewModel.temperatureText, id: "screening-temperature")
            if let id = viewModel.sourceCalculationID {
                Text("Inputs copied from calculation \(id.uuidString)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var compositionInputs: some View {
        IFEGroup("Original stream composition") {
            Text("Enter mole ppm (µmol/mol). CO₂ is the exact remainder; inputs are never normalized.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(Array(StreamScreeningSpecies.allCases.prefix(5))) { species in
                compositionRow(species)
            }
            DisclosureGroup("Other impurities") {
                ForEach(Array(StreamScreeningSpecies.allCases.dropFirst(5))) { species in
                    compositionRow(species)
                }
            }
            if let input = viewModel.input {
                LabeledContent("CO₂ remainder", value: "\(format(input.carbonDioxidePpm)) ppm")
            }
            HStack {
                Menu("Examples") {
                    Button("Binary water example") { focusedField = nil; viewModel.loadWaterExample() }
                    Button("Reactive mixture example") { focusedField = nil; viewModel.loadReactiveExample() }
                }
                .accessibilityIdentifier("screening-examples")
                Spacer()
                Button("Clear") { focusedField = nil; viewModel.clear() }
                    .accessibilityIdentifier("clear-stream-screening")
            }
        }
    }

    private func compositionRow(_ species: StreamScreeningSpecies) -> some View {
        inputRow(species.symbol, unit: "ppm", text: Binding(
            get: { viewModel.ppmTexts[species] ?? "" },
            set: { viewModel.ppmTexts[species] = $0 }
        ), id: "screening-\(species.rawValue)")
    }

    private func inputRow(_ title: String, unit: String, text: Binding<String>, id: String) -> some View {
        HStack {
            Text(LocalizedStringKey(title))
            Spacer()
            TextField("0", text: text)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 70, maxWidth: 130)
                .focused($focusedField, equals: id)
                .accessibilityLabel("\(title), \(unit)")
                .accessibilityIdentifier(id)
            Text(unit).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.significantDigits(1...7)))
    }
}

private struct StreamScreeningResultsView: View {
    let result: StreamScreeningResult

    var body: some View {
        IFEGroup("Reaction and water observations") {
            Text(observation).font(.subheadline)
                .accessibilityIdentifier("screening-observation")
            Text("These independent results do not establish acid partitioning, pH, corrosion rate or material suitability.")
                .font(.caption).foregroundStyle(.secondary)
            LabeledContent("Pressure", value: "\(format(result.input.pressurePa / 100_000)) bar(a)")
            LabeledContent("Temperature", value: "\(format(result.input.temperatureK - 273.15)) °C")
        }
        reactions
        IFEGroup("Water dropout • Original stream") {
            waterOutcome(result.streamWater)
        }
        if let reference = result.binaryWaterReference {
            IFEGroup("Binary CO₂–water reference only") {
                Text("Hypothetical binary composition. Actual mixture water dropout remains unassessed.")
                    .font(.subheadline.weight(.semibold))
                Text("Excluded impurities: \(excludedImpurities)")
                    .font(.caption).foregroundStyle(.secondary)
                waterOutcome(reference)
            }
            .accessibilityIdentifier("screening-water-reference-result")
        }
        thermophysical
    }

    private var observation: String {
        if result.acidFormationEstimated == nil {
            return String(localized: "Acid formation could not be assessed. Review the independent water and property outcomes; no safety conclusion is inferred.")
        }
        if result.acidFormationEstimated == true && result.binaryReferenceWaterExpected {
            return String(localized: "Acid formation is estimated by ToCoMo, and a water-rich phase is indicated in the separate binary reference. This is a screening flag only: acid and liquid-water coexistence in the actual mixture has not been calculated.")
        }
        if result.acidFormationEstimated == true {
            return String(localized: "Acid formation is estimated by ToCoMo. Water dropout in the reactive mixture is not assessed; a negative or unavailable binary reference does not establish safety.")
        }
        return String(localized: "No acid formation is estimated by this reaction sequence. Review the independent water and property results below; this is not a safety classification.")
    }

    private var excludedImpurities: String {
        result.input.activeImpurities.filter { $0 != .water }.map {
            "\($0.symbol) \(format(result.input.impurityPpm[$0] ?? 0)) ppm"
        }.joined(separator: ", ")
    }

    private var reactions: some View {
        IFEGroup("Impurity reactions • ToCoMo preview") {
            if let reactionResult = result.reactionResult {
                reactionDetails(reactionResult)
            } else if case .unavailable(let issue) = result.reactions {
                Text(issue.message)
            }
        }
    }

    private func reactionDetails(_ reactionResult: ToCoMoResult) -> some View {
        VStack(alignment: .leading, spacing: IFESpacing.regular) {
            Text("Preliminary, not independently validated by PhaseXpert. Completion estimate without temperature, pressure, kinetics or phase separation. All ppm remain on the original stream basis; other impurities do not participate in ToCoMo.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach([ImpurityReactionSpecies.sulfuricAcid, .nitricAcid, .nitrousAcid, .elementalSulfur], id: \.self) { species in
                LabeledContent(species.displaySymbol, value: "\(format(reactionResult.finalPpm[species] ?? 0)) ppm")
            }
            DisclosureGroup("Initial and final reactive species") {
                ForEach(ImpurityReactionSpecies.allCases, id: \.self) { species in
                    LabeledContent(species.displaySymbol,
                        value: "\(format(reactionResult.initialPpm[species] ?? 0)) → \(format(reactionResult.finalPpm[species] ?? 0)) ppm")
                }
            }
            DisclosureGroup("Reaction steps") {
                if reactionResult.steps.isEmpty { Text("No reaction could be applied") }
                ForEach(reactionResult.steps) { step in
                    if let reaction = ToCoMoModel.reactions.first(where: { $0.index == step.reactionIndex }) {
                        Text("\(step.order). \(reaction.displayText) × \(format(step.multiplier)) ppm")
                            .font(.caption)
                    }
                }
            }
            Text("ToCoMo • \(String(ToCoMoModel.reference.commit.prefix(7))) • MIT • © 2025 Equinor")
                .font(.caption).foregroundStyle(.secondary)
            Link("Model source and licence", destination: ToCoMoModel.reference.repository)
        }
    }

    @ViewBuilder
    private func waterOutcome(_ outcome: StreamWaterOutcome) -> some View {
        switch outcome {
        case .unavailable(let issue):
            Text(issue.message).font(.subheadline)
        case .result(let water):
            LabeledContent("Water status", value: water.waterStatus.displayName)
            if let originalWater = water.currentWaterPPM {
                LabeledContent("Original water", value: "\(format(originalWater)) ppm")
            }
            LabeledContent("Water saturation", value: "\(format(water.waterInCarbonDioxideRichPhasePPM)) ppm")
            if let margin = water.marginToSaturationPPM {
                LabeledContent("Margin to saturation", value: "\(format(margin)) ppm")
            }
            if let pressure = water.waterDropoutPressurePa {
                LabeledContent("Dropout pressure", value: "\(format(pressure / 100_000)) bar(a)")
            } else {
                Text("Dropout pressure unavailable within the supported range.").font(.caption)
            }
            if let temperature = water.waterDropoutTemperatureK {
                LabeledContent("Dropout temperature", value: "\(format(temperature - 273.15)) °C")
            } else {
                Text("Dropout temperature unavailable within the supported range.").font(.caption)
            }
            Link("Water model source", destination: URL(string: "https://doi.org/10.1016/S0016-7037(03)00273-4")!)
            Text(water.modelIdentifier).font(.caption)
            Text(water.validationStatus).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var thermophysical: some View {
        IFEGroup("General Properties • Original stream") {
            switch result.thermophysical {
            case .unavailable(let issue):
                Text(issue.message).font(.subheadline)
            case .result(let response):
                if !response.isScientificResult {
                    Text("Non-scientific provider result").foregroundStyle(Color.pxError)
                }
                LabeledContent("Phase", value: response.phase.displayName)
                ForEach(response.properties, id: \.property) { property in
                    LabeledContent(property.property.displayName, value: EngineeringPropertyFormatter.text(for: property))
                    if let message = property.message {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                }
                ForEach(Array(response.warnings.enumerated()), id: \.offset) { _, warning in
                    Text(warning).font(.caption).foregroundStyle(.secondary)
                }
                Text("\(response.model.name) • \(response.model.modelVersion) • \(response.model.providerVersion)")
                    .font(.caption)
                Text("Calculation ID: \(response.calculationID.uuidString)").font(.caption)
            }
        }
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.significantDigits(1...7)))
    }
}
