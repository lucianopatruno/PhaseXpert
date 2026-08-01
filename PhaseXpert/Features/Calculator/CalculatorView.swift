import PhaseXpertCore
import SwiftData
import SwiftUI
import UIKit

struct CalculatorView: View {
    private enum InputField: Hashable {
        case pressure
        case temperature
        case composition(UUID)
    }

    @State private var viewModel = CalculatorViewModel()
    @FocusState private var focusedField: InputField?
    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigationState.self) private var navigationState
    @State private var recordToSave: CalculationRecord?
    @State private var saveConfirmation: String?
    @State private var saveError: String?
    @State private var showsScientificTraceability = false
    @State private var pressureSelection: TextSelection?
    @State private var temperatureSelection: TextSelection?
    @State private var compositionSelections: [UUID: TextSelection] = [:]

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
                    operatingPointRow(
                        title: "Pressure",
                        value: $viewModel.pressureText,
                        selection: $pressureSelection,
                        unit: "bar(a)",
                        keyboardType: .decimalPad,
                        field: .pressure
                    )

                    operatingPointRow(
                        title: "Temperature",
                        value: $viewModel.temperatureText,
                        selection: $temperatureSelection,
                        unit: "°C",
                        keyboardType: .numbersAndPunctuation,
                        field: .temperature
                    )
                }

                Section {
                    ForEach($viewModel.composition) { $entry in
                        HStack(spacing: 10) {
                            if entry.component == .carbonDioxide {
                                Text(entry.component.symbol)
                                    .font(.body.weight(.medium))
                                    .accessibilityLabel("Carbon dioxide")
                            } else {
                                Picker("Impurity", selection: $entry.component) {
                                    ForEach(ComponentID.allCases.filter { $0 != .carbonDioxide }) { component in
                                        Text(component.symbol).tag(component)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                .fixedSize(horizontal: true, vertical: false)
                                .accessibilityLabel("Impurity component")
                            }

                            Spacer(minLength: 8)

                            TextField(
                                "Value",
                                text: $entry.molPercent,
                                selection: compositionSelectionBinding(for: entry.id)
                            )
                                .keyboardType(.decimalPad)
                                .focused($focusedField, equals: .composition(entry.id))
                                .multilineTextAlignment(.trailing)
                                .frame(width: 104)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.secondary.opacity(0.08))
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(
                                            focusedField == .composition(entry.id)
                                                ? Color.ifePrimary
                                                : Color.secondary.opacity(0.22),
                                            lineWidth: focusedField == .composition(entry.id) ? 1.5 : 1
                                        )
                                }
                                .contentShape(Rectangle())
                                .accessibilityLabel("\(entry.component.symbol) mole percent")

                            Text("mol%")
                                .foregroundStyle(.secondary)
                                .frame(width: 42, alignment: .leading)
                                .accessibilityHidden(true)
                        }
                        .accessibilityElement(children: .contain)
                    }
                    .onDelete(perform: viewModel.removeImpurities)
                    .onMove(perform: viewModel.moveImpurities)

                    Button("Add impurity", systemImage: "plus") {
                        if let addedID = viewModel.addImpurity() {
                            focusedField = .composition(addedID)
                        }
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
                        Task {
                            await viewModel.calculate()
                            if let record = viewModel.calculationRecord {
                                navigationState.latestCalculationRecord = record
                            }
                        }
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

                    Section {
                        Button("View phase diagram", systemImage: "chart.xyaxis.line") {
                            navigationState.showPhaseDiagram(for: record)
                        }
                        .accessibilityIdentifier("view-phase-diagram")

                        NavigationLink {
                            PropertySweepView(record: record)
                        } label: {
                            Label("Explore property sweep", systemImage: "chart.xyaxis.line")
                        }
                        .accessibilityIdentifier("open-property-sweep")

                        Button("Copy result summary", systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = CalculationSummaryFormatter.text(for: record)
                        }
                        .accessibilityIdentifier("copy-calculation-summary")

                        ShareLink(item: CalculationSummaryFormatter.text(for: record)) {
                            Label("Share result summary", systemImage: "square.and.arrow.up")
                        }

                        Button("Save case", systemImage: "square.and.arrow.down") {
                            recordToSave = record
                        }
                        .accessibilityIdentifier("save-calculation")
                    }
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
            .onAppear {
                viewModel.validate()
                loadPendingSavedCase()
            }
            .onChange(of: navigationState.pendingCalculationRecord?.id) { _, _ in
                loadPendingSavedCase()
            }
            .onChange(of: viewModel.selectedModelID) { _, _ in viewModel.validate() }
            .onChange(of: focusedField) { _, newField in
                guard let newField else { return }
                Task { @MainActor in
                    // Let SwiftUI finish making the field first responder before
                    // changing its selection. Updating selection in the same
                    // transaction can cause the numeric keyboard to lose focus.
                    await Task.yield()
                    guard focusedField == newField else { return }
                    selectAllText(in: newField)
                }
            }
            .onSubmit { viewModel.validate() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Scientific traceability", systemImage: "checkmark.shield") {
                        viewModel.validate()
                        showsScientificTraceability = true
                    }
                    .accessibilityHint("Opens model and latest calculation provenance.")
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Button {
                        moveFocus(by: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(!canMoveFocus(by: -1))
                    .accessibilityLabel("Previous input field")

                    Button {
                        moveFocus(by: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(!canMoveFocus(by: 1))
                    .accessibilityLabel("Next input field")

                    Spacer()

                    Button("OK") {
                        focusedField = nil
                        viewModel.validate()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showsScientificTraceability) {
                ScientificTraceabilityView(
                    descriptor: viewModel.selectedDescriptor,
                    record: viewModel.calculationRecord
                )
            }
            .sheet(item: $recordToSave) { record in
                SaveCalculationSheet(record: record) { name, notes in
                    save(record: record, name: name, notes: notes)
                }
            }
            .alert(
                "Case saved",
                isPresented: Binding(
                    get: { saveConfirmation != nil },
                    set: { if !$0 { saveConfirmation = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveConfirmation ?? "")
            }
            .alert(
                "Unable to save case",
                isPresented: Binding(
                    get: { saveError != nil },
                    set: { if !$0 { saveError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private func compositionSelectionBinding(
        for id: UUID
    ) -> Binding<TextSelection?> {
        Binding(
            get: { compositionSelections[id] },
            set: { selection in
                if let selection {
                    compositionSelections[id] = selection
                } else {
                    compositionSelections.removeValue(forKey: id)
                }
            }
        )
    }

    private func selectAllText(in field: InputField) {
        switch field {
        case .pressure:
            pressureSelection = fullSelection(for: viewModel.pressureText)
        case .temperature:
            temperatureSelection = fullSelection(for: viewModel.temperatureText)
        case let .composition(id):
            let value = viewModel.composition.first(where: { $0.id == id })?.molPercent ?? ""
            compositionSelections[id] = fullSelection(for: value)
        }
    }

    private func fullSelection(for value: String) -> TextSelection? {
        guard !value.isEmpty else { return nil }
        return TextSelection(range: value.startIndex..<value.endIndex)
    }

    private func operatingPointRow(
        title: String,
        value: Binding<String>,
        selection: Binding<TextSelection?>,
        unit: String,
        keyboardType: UIKeyboardType,
        field: InputField
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.body.weight(.medium))
            Spacer(minLength: 8)
            TextField("Value", text: value, selection: selection)
                .keyboardType(keyboardType)
                .focused($focusedField, equals: field)
                .multilineTextAlignment(.trailing)
                .frame(width: 104)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.08))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            focusedField == field
                                ? Color.ifePrimary
                                : Color.secondary.opacity(0.22),
                            lineWidth: focusedField == field ? 1.5 : 1
                        )
                }
                .contentShape(Rectangle())
                .accessibilityLabel("\(title) value")
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
    }

    private var orderedInputFields: [InputField] {
        [.pressure, .temperature]
            + viewModel.composition.map { .composition($0.id) }
    }

    private func canMoveFocus(by offset: Int) -> Bool {
        guard
            let focusedField,
            let index = orderedInputFields.firstIndex(of: focusedField)
        else {
            return false
        }
        return orderedInputFields.indices.contains(index + offset)
    }

    private func moveFocus(by offset: Int) {
        guard
            let focusedField,
            let index = orderedInputFields.firstIndex(of: focusedField),
            orderedInputFields.indices.contains(index + offset)
        else {
            return
        }
        self.focusedField = orderedInputFields[index + offset]
    }

    private func loadPendingSavedCase() {
        guard let record = navigationState.pendingCalculationRecord else { return }
        viewModel.loadInputs(from: record)
        navigationState.pendingCalculationRecord = nil
    }

    private func save(record: CalculationRecord, name: String, notes: String) {
        do {
            let savedCase = try SavedCalculation(name: name, notes: notes, record: record)
            modelContext.insert(savedCase)
            try modelContext.save()
            recordToSave = nil
            saveConfirmation = "\(savedCase.name) is available in Saved Cases."
        } catch {
            modelContext.rollback()
            saveError = error.localizedDescription
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
            "Pure CO₂: density, viscosity, caloric and heat-capacity properties, sound speed, conductivity, Joule–Thomson coefficient and derived values. CO₂-N₂ up to 10 mol% N₂ remains limited to density, phase and derived values. Validation remains incomplete."
        case .unavailable:
            "This provider cannot perform calculations in the current build."
        }
    }
}

struct CalculationResultSections: View {
    let record: CalculationRecord

    private enum ResultGroup: String, CaseIterable {
        case derived = "Derived"
        case thermodynamic = "Thermodynamic"
        case transport = "Transport and acoustic"
        case additional = "Additional"

        var properties: Set<PropertyID> {
            switch self {
            case .derived:
                [.molarMass, .compressibilityFactor, .specificVolume]
            case .thermodynamic:
                [
                    .enthalpy, .entropy, .internalEnergy,
                    .isobaricHeatCapacity, .isochoricHeatCapacity,
                    .heatCapacityRatio, .jouleThomsonCoefficient
                ]
            case .transport:
                [.dynamicViscosity, .thermalConductivity, .speedOfSound]
            case .additional:
                [
                    .isothermalCompressibility,
                    .thermalExpansionCoefficient,
                    .vapourFraction
                ]
            }
        }
    }

    private var stateProperties: [PropertyValue] {
        calculatedProperties(in: [.density])
    }

    private func calculatedProperties(in identifiers: Set<PropertyID>) -> [PropertyValue] {
        record.response.properties
            .filter { $0.status == .calculated && identifiers.contains($0.property) }
            .sorted { $0.property.displayName < $1.property.displayName }
    }

    private var unavailableProperties: [PropertyValue] {
        record.response.properties
            .filter { $0.status != .calculated }
            .sorted { $0.property.displayName < $1.property.displayName }
    }

    var body: some View {
        Group {
            Section("State") {
                ScientificStatusBanner(
                    title: record.response.isScientificResult
                        ? "Preliminary — validation incomplete"
                        : "Non-scientific demonstration",
                    message: record.response.warnings.joined(separator: " ")
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                LabeledContent("Pressure", value: "\(number(record.input.pressureValue)) bar(a)")
                LabeledContent("Temperature", value: "\(number(record.input.temperatureValue)) °C")
                LabeledContent("Phase", value: record.response.phase.displayName)

                ForEach(stateProperties, id: \.property) { property in
                    PropertyResultRow(property: property)
                }
            }

            ForEach(ResultGroup.allCases, id: \.self) { group in
                let properties = calculatedProperties(in: group.properties)
                if !properties.isEmpty {
                    Section(group.rawValue) {
                        ForEach(properties, id: \.property) { property in
                            PropertyResultRow(property: property)
                        }
                    }
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

        LabeledContent("Pressure — displayed", value: "\(number(record.input.pressureValue)) bar(a)")
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
                ForEach(Array(record.response.model.references.enumerated()), id: \.offset) { index, reference in
                    if
                        let address = reference.doiOrURL,
                        let url = URL(string: address)
                    {
                        Link(destination: url) {
                            scientificReferenceLabel(reference, address: address)
                        }
                        .buttonStyle(.plain)
                        .id("scientific-reference-\(index)-\(address)")
                        .accessibilityHint("Opens this reference in the browser.")
                    } else {
                        scientificReferenceLabel(reference, address: nil)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func scientificReferenceLabel(
        _ reference: SourceReference,
        address: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(reference.authors) (\(reference.year))")
                .font(.caption.weight(.semibold))
            Text(reference.title)
                .font(.caption)
            if let address {
                Label(address, systemImage: "arrow.up.right.square")
                    .font(.caption)
                    .foregroundStyle(Color.ifePrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
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

private struct SaveCalculationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let record: CalculationRecord
    let onSave: (String, String) -> Void
    @State private var name: String
    @State private var notes = ""

    init(record: CalculationRecord, onSave: @escaping (String, String) -> Void) {
        self.record = record
        self.onSave = onSave
        _name = State(initialValue: Self.defaultName(for: record))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Case information") {
                    TextField("Case name", text: $name)
                    TextField("Description or notes", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section("Calculation") {
                    LabeledContent(
                        "Pressure",
                        value: "\(number(record.input.pressurePa / 100_000)) bar(a)"
                    )
                    LabeledContent(
                        "Temperature",
                        value: "\(number(record.input.temperatureK - 273.15)) °C"
                    )
                    LabeledContent("Model", value: record.response.model.name)
                }
            }
            .navigationTitle("Save Calculation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name, notes)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private static func defaultName(for record: CalculationRecord) -> String {
        let pressure = (record.input.pressurePa / 100_000)
            .formatted(.number.precision(.significantDigits(1...6)))
        let temperature = (record.input.temperatureK - 273.15)
            .formatted(.number.precision(.significantDigits(1...6)))
        let composition = SavedCaseNameFormatter.compositionLabel(
            for: record.request.composition
        )
        return "\(composition) — \(pressure) bar, \(temperature) °C"
    }

    private func number(_ value: Double) -> String {
        value.formatted(.number.precision(.significantDigits(1...6)))
    }
}

enum SavedCaseNameFormatter {
    static func compositionLabel(for composition: [MixtureComponent]) -> String {
        let active = composition
            .filter { $0.moleFraction.isFinite && $0.moleFraction > 0 }
            .sorted { $0.moleFraction > $1.moleFraction }

        guard active.count > 1 else {
            return active.first?.component.symbol ?? "CO₂-rich mixture"
        }

        let displayedComponents = active.prefix(3).map { entry in
            let percentage = (entry.moleFraction * 100)
                .formatted(.number.precision(.significantDigits(1...6)))
            return "\(entry.component.symbol) \(percentage) mol%"
        }
        let remainingCount = active.count - displayedComponents.count
        let displayed = displayedComponents.joined(separator: " + ")

        guard remainingCount > 0 else {
            return displayed
        }
        return "\(displayed) + \(remainingCount) more"
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
        EngineeringPropertyFormatter.effectiveStatus(for: property)
    }

    private var displayValue: String {
        EngineeringPropertyFormatter.text(for: property)
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

extension PropertyID {
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

extension PropertyStatus {
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

extension PhaseRegion {
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
