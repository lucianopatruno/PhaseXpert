import PhaseXpertCore
import SwiftUI

struct CalculatorView: View {
    private enum InputField: Hashable {
        case pressure
        case temperature
        case composition
    }

    @State private var viewModel = CalculatorViewModel()
    @FocusState private var focusedField: InputField?

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            Form {
                Section {
                    if let descriptor = viewModel.selectedDescriptor {
                        ScientificStatusBanner(
                            title: modelBannerTitle(descriptor),
                            message: modelBannerMessage(descriptor)
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }

                Section("Calculation model") {
                    Picker("Model", selection: $viewModel.selectedModelID) {
                        ForEach(viewModel.descriptors) { descriptor in
                            Text(descriptor.name).tag(descriptor.id)
                        }
                    }

                    if let descriptor = viewModel.selectedDescriptor {
                        LabeledContent("Status", value: descriptor.availability.rawValue.capitalized)
                        LabeledContent("Execution", value: descriptor.calculationMode.rawValue.capitalized)
                    }
                }

                Section("Operating point") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Pressure")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.ifeText)

                        HStack(spacing: 12) {
                            TextField("Value", text: $viewModel.pressureText)
                                .keyboardType(.decimalPad)
                                .focused($focusedField, equals: .pressure)
                                .accessibilityLabel("Pressure value")

                            Text("bar abs")
                                .foregroundStyle(.secondary)
                                .frame(width: 64, alignment: .trailing)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Temperature")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.ifeText)

                        HStack(spacing: 12) {
                            TextField("Value", text: $viewModel.temperatureText)
                                .keyboardType(.numbersAndPunctuation)
                                .focused($focusedField, equals: .temperature)
                                .accessibilityLabel("Temperature value")

                            Text("°C")
                                .foregroundStyle(.secondary)
                                .frame(width: 64, alignment: .trailing)
                        }
                    }
                }

                Section {
                    ForEach($viewModel.composition) { $entry in
                        HStack {
                            if entry.component == .carbonDioxide {
                                Text(entry.component.symbol)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Picker("Component", selection: $entry.component) {
                                    ForEach(ComponentID.allCases.filter { $0 != .carbonDioxide }) { component in
                                        Text(component.symbol).tag(component)
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            TextField("mol%", text: $entry.molPercent)
                                .keyboardType(.decimalPad)
                                .focused($focusedField, equals: .composition)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                            Text("mol%")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .onDelete(perform: viewModel.removeImpurities)
                    .onMove(perform: viewModel.moveImpurities)

                    Button("Add impurity", systemImage: "plus") {
                        viewModel.addImpurity()
                    }
                    .disabled(viewModel.composition.count >= 21)
                } header: {
                    HStack {
                        Text("Composition")
                        Spacer()
                        EditButton()
                    }
                } footer: {
                    Text("Values are entered as mol%. The app never normalizes composition silently.")
                }

                if !viewModel.validationReport.issues.isEmpty {
                    Section("Input review") {
                        ForEach(viewModel.validationReport.issues) { issue in
                            Label(
                                issue.message,
                                systemImage: issue.severity == .error
                                    ? "xmark.octagon.fill"
                                    : "exclamationmark.triangle.fill"
                            )
                            .foregroundStyle(issue.severity == .error ? .red : Color.ifePrimary)
                        }

                        if viewModel.canNormalize {
                            Button("Review and apply normalization") {
                                viewModel.normalizeComposition()
                            }
                        }
                    }
                }

                Section {
                    Button {
                        Task { await viewModel.calculate() }
                    } label: {
                        if viewModel.isCalculating {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Run calculation")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isCalculating || !viewModel.validationReport.canCalculate)
                    .accessibilityIdentifier("run-calculation")
                }

                if let record = viewModel.calculationRecord {
                    CalculationResultSections(record: record)
                }

                if let error = viewModel.calculationError {
                    Section("Calculation error") {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.ifeBackground)
            .navigationTitle("PhaseXpert")
            .onAppear { viewModel.validate() }
            .onChange(of: viewModel.selectedModelID) { _, _ in viewModel.validate() }
            .onSubmit { viewModel.validate() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Validate", systemImage: "checkmark.shield") {
                        viewModel.validate()
                    }
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("OK") {
                        focusedField = nil
                        viewModel.validate()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func modelBannerTitle(_ descriptor: ModelDescriptor) -> String {
        switch descriptor.availability {
        case .available: "Model available"
        case .preliminary: "Preliminary scientific model"
        case .unavailable: "Model unavailable"
        }
    }

    private func modelBannerMessage(_ descriptor: ModelDescriptor) -> String {
        switch descriptor.availability {
        case .available:
            descriptor.id == "architecture-demo"
                ? "Workflow demonstration only. No thermophysical values are calculated."
                : "Review the model domain and limitations before calculating."
        case .preliminary:
            "Pure CO₂ density and dynamic viscosity only. Validation remains incomplete; do not use results for engineering decisions."
        case .unavailable:
            "This provider cannot perform calculations in the current build."
        }
    }
}

private struct CalculationResultSections: View {
    let record: CalculationRecord

    private var calculatedProperties: [PropertyValue] {
        record.response.properties
            .filter { $0.status == .calculated }
            .sorted { $0.property.displayName < $1.property.displayName }
    }

    private var unavailableProperties: [PropertyValue] {
        record.response.properties
            .filter { $0.status != .calculated }
            .sorted { $0.property.displayName < $1.property.displayName }
    }

    var body: some View {
        Group {
            Section("Results") {
                ScientificStatusBanner(
                    title: record.response.isScientificResult
                        ? "Preliminary — validation incomplete"
                        : "Non-scientific demonstration",
                    message: record.response.warnings.joined(separator: " ")
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                LabeledContent("Pressure", value: "\(number(record.input.pressureValue)) bar abs")
                LabeledContent("Temperature", value: "\(number(record.input.temperatureValue)) °C")
                LabeledContent("Phase", value: record.response.phase.displayName)

                ForEach(calculatedProperties, id: \.property) { property in
                    PropertyResultRow(property: property)
                }
            }

            if !unavailableProperties.isEmpty {
                Section {
                    DisclosureGroup("Unavailable properties (\(unavailableProperties.count))") {
                        ForEach(unavailableProperties, id: \.property) { property in
                            PropertyResultRow(property: property)
                        }
                    }
                }
            }

            Section("Scientific traceability") {
                DisclosureGroup("Calculation details") {
                    traceabilityContent
                }
            }
        }
    }

    @ViewBuilder
    private var traceabilityContent: some View {
        LabeledContent("Calculated at") {
            Text(record.response.calculatedAt.formatted(
                .dateTime.year().month().day().hour().minute().second()
            ))
        }
        LabeledContent("Calculation ID") {
            Text(record.response.calculationID.uuidString)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
        LabeledContent("Request ID") {
            Text(record.response.requestID.uuidString)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }

        LabeledContent("Pressure — displayed", value: "\(number(record.input.pressureValue)) bar abs")
        LabeledContent("Pressure — SI", value: "\(number(record.input.pressurePa)) Pa")
        LabeledContent("Temperature — displayed", value: "\(number(record.input.temperatureValue)) °C")
        LabeledContent("Temperature — SI", value: "\(number(record.input.temperatureK)) K")

        LabeledContent("Original composition") {
            Text(originalCompositionText)
                .multilineTextAlignment(.trailing)
        }
        if let normalized = record.input.normalizedComposition {
            LabeledContent("Normalized composition") {
                Text(normalized.map {
                    "\($0.component.symbol) \(number($0.moleFraction * 100)) mol%"
                }.joined(separator: ", "))
                .multilineTextAlignment(.trailing)
            }
        }

        LabeledContent("Model", value: record.response.model.name)
        LabeledContent("Model ID", value: record.response.model.id)
        LabeledContent("Model version", value: record.response.model.modelVersion)
        LabeledContent("Provider version", value: record.response.model.providerVersion)
        LabeledContent(
            "Coefficient/library version",
            value: record.response.model.coefficientSetVersion ?? "Not specified"
        )
        LabeledContent("Execution", value: record.response.model.calculationMode.rawValue.capitalized)
        LabeledContent("Equation or method") {
            Text(record.response.model.equationOrMethod)
                .multilineTextAlignment(.trailing)
        }
        LabeledContent("Solver", value: record.response.solver.method)
        LabeledContent("Converged", value: record.response.solver.converged ? "Yes" : "No")
        LabeledContent(
            "Duration",
            value: "\(number(record.response.solver.durationMilliseconds)) ms"
        )
        if let iterations = record.response.solver.iterationCount {
            LabeledContent("Iterations", value: "\(iterations)")
        }
        if let tolerance = record.response.solver.absoluteTolerance {
            LabeledContent("Absolute tolerance", value: number(tolerance))
        }
        if let tolerance = record.response.solver.relativeTolerance {
            LabeledContent("Relative tolerance", value: number(tolerance))
        }
        LabeledContent(
            "Application",
            value: "\(record.application.version) (\(record.application.build))"
        )

        if !record.response.model.references.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Scientific references")
                    .font(.subheadline.weight(.semibold))
                ForEach(Array(record.response.model.references.enumerated()), id: \.offset) { _, reference in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(reference.authors) (\(reference.year))")
                            .font(.caption.weight(.semibold))
                        Text(reference.title)
                            .font(.caption)
                        if
                            let address = reference.doiOrURL,
                            let url = URL(string: address)
                        {
                            Link(address, destination: url)
                                .font(.caption)
                        }
                    }
                }
            }
        }
    }

    private var originalCompositionText: String {
        record.input.originalComposition.map {
            "\($0.component.symbol) \(number($0.value)) \($0.unit.rawValue)"
        }.joined(separator: ", ")
    }

    private func number(_ value: Double) -> String {
        guard value.isFinite else { return "Invalid" }
        return value.formatted(.number.precision(.significantDigits(1...8)))
    }
}

private struct PropertyResultRow: View {
    let property: PropertyValue

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(property.property.displayName)
                    .font(.body.weight(.semibold))
                if let message = property.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(displayValue)
                    .monospacedDigit()
                PropertyStatusBadge(status: effectiveStatus)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(property.property.displayName), \(displayValue), \(effectiveStatus.displayName)"
        )
    }

    private var effectiveStatus: PropertyStatus {
        property.status == .calculated && !property.hasFiniteCalculatedValue
            ? .failed
            : property.status
    }

    private var displayValue: String {
        guard property.hasFiniteCalculatedValue, let value = property.value else {
            return effectiveStatus.displayName
        }
        if property.property == .dynamicViscosity, property.unit == "Pa·s" {
            let converted = DynamicViscosityUnit.millipascalSecond.fromPascalSeconds(value)
            return "\(format(converted)) \(DynamicViscosityUnit.millipascalSecond.rawValue)"
        }
        return "\(format(value)) \(property.unit)"
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.significantDigits(1...7)))
    }
}

private struct PropertyStatusBadge: View {
    let status: PropertyStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(status == .failed ? Color.red : Color.ifePrimary)
            .background(
                (status == .failed ? Color.red : Color.ifeBlue).opacity(0.12),
                in: Capsule()
            )
    }
}

private extension PropertyID {
    var displayName: String {
        switch self {
        case .density: "Density"
        case .dynamicViscosity: "Dynamic viscosity"
        case .molarMass: "Molar mass"
        case .compressibilityFactor: "Compressibility factor"
        case .specificVolume: "Specific volume"
        case .enthalpy: "Enthalpy"
        case .entropy: "Entropy"
        case .internalEnergy: "Internal energy"
        case .isobaricHeatCapacity: "Isobaric heat capacity"
        case .isochoricHeatCapacity: "Isochoric heat capacity"
        case .heatCapacityRatio: "Heat-capacity ratio"
        case .speedOfSound: "Speed of sound"
        case .thermalConductivity: "Thermal conductivity"
        case .jouleThomsonCoefficient: "Joule–Thomson coefficient"
        case .isothermalCompressibility: "Isothermal compressibility"
        case .thermalExpansionCoefficient: "Thermal expansion coefficient"
        case .vapourFraction: "Vapour fraction"
        }
    }
}

private extension PropertyStatus {
    var displayName: String {
        switch self {
        case .calculated: "Calculated"
        case .unavailable: "Unavailable"
        case .outsideValidatedRange: "Outside validated range"
        case .extrapolated: "Extrapolated"
        case .failed: "Calculation failed"
        }
    }
}

private extension PhaseRegion {
    var displayName: String {
        switch self {
        case .gas: "Gas"
        case .liquid: "Liquid"
        case .dense: "Dense phase"
        case .supercritical: "Supercritical"
        case .twoPhase: "Two-phase"
        case .solid: "Solid"
        case .unknown: "Unknown"
        case .unavailable: "Unavailable"
        }
    }
}

#Preview {
    CalculatorView()
}
