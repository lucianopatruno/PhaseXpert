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
    @State private var validationDetailsExpanded = false

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            ScrollViewReader { scrollProxy in
            Form {
                Section {
                    CalculatorBrandHeader()
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowBackground(Color.clear)
                }

                Section {
                    ForEach(viewModel.descriptors) { descriptor in
                        ModelSelectionRow(
                            descriptor: descriptor,
                            isSelected: descriptor.id == viewModel.selectedModelID
                        ) {
                            focusedField = nil
                            if descriptor.availability != .unavailable {
                                viewModel.selectedModelID = descriptor.id
                            }
                        }
                        .disabled(descriptor.availability == .unavailable)
                        .accessibilityIdentifier("model-\(descriptor.id)")
                    }
                } header: {
                    IFESectionHeader(
                        step: 1,
                        title: "Thermodynamic model",
                        subtitle: "Choose the calculation provider."
                    )
                }

                Section {
                    operatingPointRow(
                        title: "Pressure",
                        value: $viewModel.pressureText,
                        selection: $pressureSelection,
                        unit: Binding(
                            get: { viewModel.pressureDisplayUnit },
                            set: { unit in
                                focusedField = nil
                                viewModel.changePressureDisplayUnit(to: unit)
                            }
                        ),
                        keyboardType: .decimalPad,
                        field: .pressure
                    )

                    operatingPointRow(
                        title: "Temperature",
                        value: $viewModel.temperatureText,
                        selection: $temperatureSelection,
                        unit: Binding(
                            get: { viewModel.temperatureDisplayUnit },
                            set: { unit in
                                focusedField = nil
                                viewModel.changeTemperatureDisplayUnit(to: unit)
                            }
                        ),
                        keyboardType: .decimalPad,
                        field: .temperature
                    )
                } header: {
                    IFESectionHeader(
                        step: 2,
                        title: "Pressure and temperature"
                    )
                }

                Section {
                    Picker(
                        "Composition basis",
                        selection: Binding(
                            get: { viewModel.compositionBasis },
                            set: { basis in
                                focusedField = nil
                                viewModel.changeCompositionBasis(to: basis)
                            }
                        )
                    ) {
                        ForEach(CompositionInputBasis.allCases) { basis in
                            Text(basis.rawValue).tag(basis)
                        }
                    }
                    .pickerStyle(.segmented)

                    ForEach($viewModel.composition) { $entry in
                        HStack(spacing: 10) {
                            if entry.component == .carbonDioxide {
                                Text(entry.component.symbol)
                                    .font(.body.weight(.medium))
                                    .accessibilityLabel("Carbon dioxide")
                            } else {
                                Menu {
                                    ForEach(
                                        viewModel.impurityOptions(including: entry.component)
                                    ) { component in
                                        Button {
                                            viewModel.updateImpurity(
                                                id: entry.id,
                                                component: component
                                            )
                                        } label: {
                                            if component == entry.component {
                                                Label(component.symbol, systemImage: "checkmark")
                                            } else {
                                                Text(component.symbol)
                                            }
                                        }
                                    }

                                    Divider()

                                    Button(role: .destructive) {
                                        removeImpurity(id: entry.id)
                                    } label: {
                                        Label("Remove impurity", systemImage: "trash")
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(entry.component.symbol)
                                        Image(systemName: "chevron.down")
                                            .font(.caption.weight(.semibold))
                                    }
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)
                                }
                                .fixedSize(horizontal: true, vertical: false)
                                .accessibilityLabel(
                                    "\(entry.component.symbol) impurity menu"
                                )
                                .accessibilityHint(
                                    "Changes or removes this impurity."
                                )
                            }

                            Spacer(minLength: 8)

                            if entry.component == .carbonDioxide {
                                Text(viewModel.displayedCompositionValue(for: entry))
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 104)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 7)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.secondary.opacity(0.08))
                                    )
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel("Calculated carbon dioxide remainder")
                            } else {
                                TextField(
                                    "Value",
                                    text: $entry.value,
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
                                .accessibilityLabel(
                                    "\(entry.component.symbol) \(viewModel.compositionBasis.rawValue)"
                                )
                            }

                            Text(viewModel.compositionBasis.rawValue)
                                .foregroundStyle(.secondary)
                                .frame(width: 48, alignment: .leading)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    dismissImpurityKeyboardIfNeeded()
                                }
                                .accessibilityHidden(true)
                        }
                        .accessibilityElement(children: .contain)
                    }
                    .onDelete(perform: removeImpurities)
                    .onMove(perform: viewModel.moveImpurities)

                    Button("Add impurity", systemImage: "plus") {
                        if let addedID = viewModel.addImpurity() {
                            focusedField = .composition(addedID)
                        }
                    }
                    .disabled(viewModel.composition.count >= viewModel.supportedImpurityComponents.count + 1)

                    if !viewModel.validatedCompositionOptions.isEmpty {
                        if viewModel.validatedCompositionOptions.count == 1,
                           let option = viewModel.validatedCompositionOptions.first {
                            Button("Use validated composition", systemImage: "checkmark.shield") {
                                focusedField = nil
                                viewModel.useValidatedComposition(option)
                            }
                            .accessibilityHint("Changes composition only; pressure and temperature are unchanged.")
                            .accessibilityIdentifier("use-validated-composition")
                        } else {
                            Menu("Use validated composition", systemImage: "checkmark.shield") {
                                ForEach(viewModel.validatedCompositionOptions) { option in
                                    Button(option.name) {
                                        focusedField = nil
                                        viewModel.useValidatedComposition(option)
                                    }
                                }
                            }
                            .accessibilityHint("Choose an exact validated composition. Pressure and temperature are unchanged.")
                            .accessibilityIdentifier("use-validated-composition")
                        }
                    }

                    if !viewModel.validatedStateOptions.isEmpty {
                        if viewModel.validatedStateOptions.count == 1,
                           let option = viewModel.validatedStateOptions.first {
                            Button("Use validated state", systemImage: "target") {
                                focusedField = nil
                                viewModel.useValidatedState(option)
                            }
                            .accessibilityLabel("Use validated state. \(option.name), \(option.detail)")
                            .accessibilityHint("Changes composition and operating conditions to a validated state.")
                            .accessibilityIdentifier("use-validated-state")
                        } else {
                            Menu("Use validated state", systemImage: "target") {
                                ForEach(viewModel.validatedStateOptions) { option in
                                    Button("\(option.name) — \(option.detail)") {
                                        focusedField = nil
                                        viewModel.useValidatedState(option)
                                    }
                                    .accessibilityLabel("\(option.name), \(option.detail)")
                                }
                            }
                            .accessibilityHint("Choose a validated composition and operating point. Changes composition and operating conditions.")
                            .accessibilityIdentifier("use-validated-state")
                        }
                    }
                } header: {
                    IFESectionHeader(
                        step: 3,
                        title: "Composition",
                        subtitle: "CO₂ is the remainder."
                    )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            dismissImpurityKeyboardIfNeeded()
                        }
                } footer: {
                    Text(compositionFooterText)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissImpurityKeyboardIfNeeded()
                    }
                }

                if let guidance = viewModel.operatingRangeGuidance, !guidance.isEmpty {
                    Section {
                        CompactValidationStatusView(
                            guidance: guidance,
                            validatedProperties: viewModel.validatedPropertiesAtCurrentState
                        )
                        DisclosureGroup(
                            "Validation details",
                            isExpanded: $validationDetailsExpanded
                        ) {
                            ValidatedRangeGuidanceView(guidance: guidance) { suggestion in
                                focusedField = nil
                                viewModel.applyGuidanceSuggestion(suggestion)
                            }
                        }
                        .accessibilityValue(validationDetailsExpanded ? "Expanded" : "Collapsed")
                        .accessibilityIdentifier("validation-details-disclosure")
                    } header: {
                        IFESectionHeader(step: 4, title: "Validation status")
                    }
                }

                if let notice = viewModel.calculationNotice {
                    Section {
                        Label(notice, systemImage: "info.circle.fill")
                            .foregroundStyle(Color.ifePrimary)
                    } header: {
                        Text("Independent capability result")
                    }
                }

                if let equilibrium = viewModel.displayedWaterEquilibrium {
                    WaterEquilibriumSection(equilibrium: equilibrium)
                } else if let waterMessage = viewModel.waterEquilibriumUnavailableMessage {
                    Section {
                        Label(waterMessage, systemImage: "info.circle.fill")
                            .foregroundStyle(Color.ifePrimary)
                    } header: {
                        Text("Water equilibrium")
                    }
                }

                if !viewModel.validationReport.issues.isEmpty {
                    Section {
                        ForEach(viewModel.validationReport.issues) { issue in
                            let isNonfatalHomogeneousIssue =
                                issue.severity == .error
                                && viewModel.homogeneousPropertiesUnavailableWhileEquilibriumAvailable
                            Label(
                                issue.message,
                                systemImage: issue.severity == .error && !isNonfatalHomogeneousIssue
                                    ? "xmark.octagon.fill"
                                    : "exclamationmark.triangle.fill"
                            )
                            .foregroundStyle(
                                issue.severity == .error && !isNonfatalHomogeneousIssue
                                    ? .red
                                    : Color.ifePrimary
                            )
                        }

                        if viewModel.canNormalize {
                            Button("Review and apply normalization") {
                                viewModel.normalizeComposition()
                            }
                        }
                    } header: {
                        IFESectionHeader(step: nil, title: "Validation and capability state")
                            .contentShape(Rectangle())
                            .onTapGesture {
                                focusedField = nil
                            }
                    }
                }

                Section {
                    Button {
                        focusedField = nil
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
                    .disabled(viewModel.isCalculating || !viewModel.canRunCalculation)
                    .accessibilityIdentifier("run-calculation")

                    Button("Reset", systemImage: "arrow.counterclockwise") {
                        resetCalculator()
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isCalculating)
                    .accessibilityIdentifier("reset-calculator")
                    .accessibilityHint("Restores the clean calculator defaults and clears results.")
                } header: {
                    IFESectionHeader(step: 5, title: "Run calculation")
                }

                if let record = viewModel.calculationRecord {
                    CalculationResultSections(record: record)
                        .id("calculation-results")

                    Section {
                        Button("View phase diagram", systemImage: "chart.xyaxis.line") {
                            navigationState.showPhaseDiagram(for: record)
                        }
                        .accessibilityIdentifier("view-phase-diagram")

                        NavigationLink {
                            PropertySweepView(record: record)
                        } label: {
                            Label("Explore property sweep", systemImage: "chart.xyaxis.line")
                                .foregroundStyle(Color.accentColor)
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
                    } header: {
                        IFESectionHeader(step: 7, title: "Traceability, save and export")
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
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                Color.clear
                    .frame(height: IFESpacing.extraLarge)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .ifeDottedBackground()
            .toolbarTitleDisplayMode(.inline)
            .onAppear {
                viewModel.validate()
                loadPendingInputs()
            }
            .onChange(of: navigationState.pendingCalculationRecord?.id) { _, _ in
                loadPendingInputs()
            }
            .onChange(of: navigationState.pendingBuiltInCase?.id) { _, _ in
                loadPendingInputs()
            }
            .onChange(of: viewModel.selectedModelID) { _, _ in viewModel.validate() }
            .onChange(of: viewModel.pressureText) { _, _ in viewModel.validate() }
            .onChange(of: viewModel.temperatureText) { _, _ in viewModel.validate() }
            .onChange(of: viewModel.composition) { _, _ in
                reconcileCompositionFocus()
                viewModel.validate()
            }
            .onChange(of: viewModel.calculationRecord?.id) { _, newID in
                guard newID != nil else { return }
                focusedField = nil
                withAnimation(.easeInOut(duration: 0.28)) {
                    scrollProxy.scrollTo("calculation-results", anchor: .top)
                }
            }
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
                    Button {
                        viewModel.validate()
                        showsScientificTraceability = true
                    } label: {
                        Label(
                            "Scientific traceability",
                            systemImage: viewModel.scientificShieldIsActive
                                ? "checkmark.shield.fill"
                                : "checkmark.shield"
                        )
                    }
                    .foregroundStyle(viewModel.scientificShieldIsActive ? Color.ifePrimary : .primary)
                    .symbolRenderingMode(viewModel.scientificShieldIsActive ? .hierarchical : .monochrome)
                    .accessibilityValue(
                        viewModel.scientificShieldIsActive
                            ? "Validated capability available for current state"
                            : "No validated capability for current state"
                    )
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

                    if focusedField == .temperature {
                        Button("Minus") {
                            insertMinusSign()
                        }
                        .accessibilityIdentifier("keyboard-minus")
                        .accessibilityLabel("Insert minus sign")
                    }

                    if focusedField != nil {
                        Button("Done") {
                            focusedField = nil
                        }
                        .font(.body.weight(.semibold))
                        .accessibilityIdentifier("keyboard-done")
                        .accessibilityLabel("Done")
                    }
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
                isPresented: saveConfirmationIsPresented
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveConfirmation ?? "")
            }
            .alert(
                "Unable to save case",
                isPresented: saveErrorIsPresented
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
            }
        }
    }

    private func removeImpurity(id: UUID) {
        if focusedField == .composition(id) {
            focusedField = nil
        }
        compositionSelections.removeValue(forKey: id)
        viewModel.removeImpurity(id: id)
    }

    private var saveConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { saveConfirmation != nil },
            set: { if !$0 { saveConfirmation = nil } }
        )
    }

    private var saveErrorIsPresented: Binding<Bool> {
        Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )
    }

    private func removeImpurities(at offsets: IndexSet) {
        let removedIDs = offsets.compactMap { index -> UUID? in
            guard viewModel.composition.indices.contains(index) else { return nil }
            let entry = viewModel.composition[index]
            return entry.component == .carbonDioxide ? nil : entry.id
        }
        if let focusedImpurityID, removedIDs.contains(focusedImpurityID) {
            focusedField = nil
        }
        for id in removedIDs {
            compositionSelections.removeValue(forKey: id)
        }
        viewModel.removeImpurities(at: offsets)
    }

    private func resetCalculator() {
        focusedField = nil
        pressureSelection = nil
        temperatureSelection = nil
        compositionSelections.removeAll()
        recordToSave = nil
        saveConfirmation = nil
        saveError = nil
        navigationState.pendingCalculationRecord = nil
        navigationState.pendingBuiltInCase = nil
        navigationState.latestCalculationRecord = nil
        viewModel.reset()
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
            let value = viewModel.composition.first(where: { $0.id == id })?.value ?? ""
            compositionSelections[id] = fullSelection(for: value)
        }
    }

    private var focusedImpurityID: UUID? {
        guard case let .composition(id) = focusedField else { return nil }
        return id
    }

    private var isImpurityAmountFocused: Bool {
        guard let focusedImpurityID else { return false }
        return viewModel.composition.contains {
            $0.id == focusedImpurityID && $0.component != .carbonDioxide
        }
    }

    private func dismissImpurityKeyboardIfNeeded() {
        if isImpurityAmountFocused {
            focusedField = nil
        }
    }

    private func reconcileCompositionFocus() {
        let activeImpurityIDs = Set(
            viewModel.composition
                .filter { $0.component != .carbonDioxide }
                .map(\.id)
        )
        if let focusedImpurityID, !activeImpurityIDs.contains(focusedImpurityID) {
            focusedField = nil
        }
        compositionSelections = compositionSelections.filter {
            activeImpurityIDs.contains($0.key)
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
        unit: Binding<PressureDisplayUnit>,
        keyboardType: UIKeyboardType,
        field: InputField
    ) -> some View {
        UnitAwareNumericField(
            title: title,
            text: value,
            selection: selection,
            keyboardType: keyboardType,
            isFocused: focusedField == field,
            unitLabel: unit.wrappedValue.rawValue,
            unitOptions: PressureDisplayUnit.allCases.map(\.rawValue),
            selectedUnit: unit.wrappedValue.rawValue,
            accessibilityIdentifier: title.lowercased(),
            unitAction: { selectedUnit in
                guard let selected = PressureDisplayUnit.allCases.first(where: {
                    $0.rawValue == selectedUnit
                }) else { return }
                unit.wrappedValue = selected
            }
        )
        .focused($focusedField, equals: field)
    }

    private func operatingPointRow(
        title: String,
        value: Binding<String>,
        selection: Binding<TextSelection?>,
        unit: Binding<TemperatureDisplayUnit>,
        keyboardType: UIKeyboardType,
        field: InputField
    ) -> some View {
        UnitAwareNumericField(
            title: title,
            text: value,
            selection: selection,
            keyboardType: keyboardType,
            isFocused: focusedField == field,
            unitLabel: unit.wrappedValue.rawValue,
            unitOptions: TemperatureDisplayUnit.allCases.map(\.rawValue),
            selectedUnit: unit.wrappedValue.rawValue,
            accessibilityIdentifier: title.lowercased(),
            unitAction: { selectedUnit in
                guard let selected = TemperatureDisplayUnit.allCases.first(where: {
                    $0.rawValue == selectedUnit
                }) else { return }
                unit.wrappedValue = selected
            }
        )
        .focused($focusedField, equals: field)
    }

    private var compositionFooterText: String {
        viewModel.compositionBasis == .partsPerMillion
            ? "Impurity total cannot exceed 1,000,000 ppm. CO₂ is not normalized silently."
            : "Impurity total cannot exceed 100 mol%. CO₂ is not normalized silently."
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

    private func loadPendingInputs() {
        if let record = navigationState.pendingCalculationRecord {
            viewModel.loadInputs(from: record)
            navigationState.pendingCalculationRecord = nil
        }
        if let builtInCase = navigationState.pendingBuiltInCase {
            viewModel.loadInputs(from: builtInCase)
            navigationState.pendingBuiltInCase = nil
        }
        if let batchCase = navigationState.pendingBatchCase {
            viewModel.loadInputs(from: batchCase.input, model: batchCase.model)
            navigationState.pendingBatchCase = nil
        }
    }

    private func insertMinusSign() {
        guard focusedField == .temperature else { return }
        if viewModel.temperatureText.hasPrefix("-") {
            viewModel.temperatureText.removeFirst()
        } else if viewModel.temperatureText.hasPrefix("−") {
            viewModel.temperatureText.removeFirst()
        } else {
            // The dedicated key starts a new negative entry, matching the
            // calculator's replace-on-focus behavior for numeric fields.
            viewModel.temperatureText = "-"
        }
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

}

private struct CalculatorBrandHeader: View {
    var body: some View {
        HStack(alignment: .center, spacing: IFESpacing.regular) {
            VStack(alignment: .leading, spacing: 3) {
                Text("PhaseXpert")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(Color.ifeText)
                Text("Phase behavior and properties of CO₂ mixtures")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: IFESpacing.regular)
            Image("IFELogoEnglish")
                .resizable()
                .scaledToFit()
                .frame(width: 82, height: 34)
                .accessibilityLabel("IFE — Institute for Energy Technology")
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ValidatedRangeGuidanceView: View {
    let guidance: OperatingRangeGuidance
    let applySuggestion: (OperatingGuidanceSuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: IFESpacing.small) {
            ForEach(guidance.summary) { line in
                GuidanceLineView(line: line)
            }

            ForEach(guidance.currentInputIssues) { line in
                GuidanceLineView(line: line)
            }

            ForEach(guidance.propertyAvailability) { line in
                GuidanceLineView(line: line)
            }

            ForEach(guidance.phaseDiagram) { line in
                GuidanceLineView(line: line)
            }

            if !guidance.suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: IFESpacing.small) {
                        ForEach(guidance.suggestions) { suggestion in
                            Button(suggestion.label) {
                                applySuggestion(suggestion)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityIdentifier("guidance-suggestion-\(suggestion.id)")
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(.vertical, IFESpacing.xSmall)
        .accessibilityIdentifier("validated-range-guidance")
    }
}

private struct CompactValidationStatusView: View {
    let guidance: OperatingRangeGuidance
    let validatedProperties: [PropertyID]

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: validatedProperties.isEmpty
                ? "shield.lefthalf.filled"
                : "checkmark.shield.fill")
                .foregroundStyle(validatedProperties.isEmpty ? Color.pxWarning : Color.pxSuccess)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("compact-validation-status")
    }

    private var title: String {
        if !validatedProperties.isEmpty { return "Limited validation" }
        if homogeneousUnavailableWhileWaterEquilibriumAvailable {
            return "Capability-specific validation"
        }
        if guidance.currentInputIssues.contains(where: { $0.severity == .unsupported }) {
            return "Outside validated range"
        }
        return guidance.title
    }

    private var detail: String {
        if homogeneousUnavailableWhileWaterEquilibriumAvailable {
            return "Water equilibrium validated; homogeneous properties unavailable at this state"
        }
        guard !validatedProperties.isEmpty else {
            return guidance.currentInputIssues.first?.title
                ?? "Open validation details after calculation for scientific scope."
        }
        return AdvancedValidationPresentation.propertyList(validatedProperties)
    }

    private var homogeneousUnavailableWhileWaterEquilibriumAvailable: Bool {
        guidance.currentInputIssues.contains {
            $0.title == "Homogeneous properties outside preliminary range"
                && $0.detail.contains("Water-equilibrium results remain available")
        }
    }
}

private struct GuidanceLineView: View {
    let line: OperatingGuidanceLine

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.title)
                    .font(.subheadline.weight(.semibold))
                Text(line.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
        }
        .accessibilityElement(children: .combine)
    }

    private var iconName: String {
        switch line.severity {
        case .information:
            "checkmark.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .unsupported:
            "xmark.octagon.fill"
        }
    }

    private var iconColor: Color {
        switch line.severity {
        case .information:
            Color.pxSuccess
        case .warning:
            Color.pxWarning
        case .unsupported:
            Color.pxError
        }
    }
}

private enum StreamMixingInputField: Hashable {
    case outletPressure
    case outletTemperature
    case streamName(UUID)
    case streamFlow(UUID)
    case streamPressure(UUID)
    case streamTemperature(UUID)
    case composition(UUID, UUID)
}

struct StreamMixingView: View {
    private let wrapsInNavigationStack: Bool
    @State private var viewModel: StreamMixingViewModel
    @FocusState private var focusedField: StreamMixingInputField?
    @State private var textSelections: [String: TextSelection] = [:]

    init(
        viewModel: StreamMixingViewModel = StreamMixingViewModel(),
        wrapsInNavigationStack: Bool = true
    ) {
        _viewModel = State(initialValue: viewModel)
        self.wrapsInNavigationStack = wrapsInNavigationStack
    }

    var body: some View {
        if wrapsInNavigationStack {
            NavigationStack {
                content
            }
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        @Bindable var viewModel = viewModel

        Form {
            Section {
                ScientificStatusBanner(
                    title: "Stream Mixing v1",
                    message: "Aggregates inlet component molar flows into a mixed composition at user-defined outlet pressure and temperature."
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } footer: {
                Text("V1 does not calculate pressure equalization, heat transfer, phase separation, outlet temperature or thermodynamic properties.")
            }

            Section {
                HStack {
                    Button("Add stream", systemImage: "plus") {
                        focusedField = nil
                        _ = viewModel.addStream()
                    }
                    .disabled(!viewModel.canAddStream)
                    .accessibilityIdentifier("stream-mixing-add-stream")

                    Spacer()

                    Text("\(viewModel.streams.count)/6")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("\(viewModel.streams.count) of 6 streams")
                        .accessibilityIdentifier("stream-mixing-stream-count")
                }

                ForEach($viewModel.streams) { $stream in
                    StreamInputCard(
                        stream: $stream,
                        viewModel: viewModel,
                        focusedField: $focusedField,
                        textSelections: $textSelections
                    )
                    .accessibilityIdentifier("stream-card-\(stream.id.uuidString)")
                }
                .onMove { source, destination in
                    focusedField = nil
                    viewModel.moveStreams(from: source, to: destination)
                }
            } header: {
                IFESectionHeader(
                    step: 1,
                    title: "Inlet streams",
                    subtitle: "Two to six streams. Drag to reorder without changing the result."
                )
            } footer: {
                if viewModel.streams.count >= StreamMixingRequest.maximumStreamCount {
                    Text("Maximum of six inlet streams reached.")
                }
            }

            Section {
                operatingPointRow(
                    title: "Outlet pressure",
                    value: Binding(
                        get: { viewModel.outletPressureText },
                        set: { viewModel.updateOutletPressureText($0) }
                    ),
                    unit: Binding(
                        get: { viewModel.outletPressureDisplayUnit },
                        set: { unit in
                            focusedField = nil
                            viewModel.changeOutletPressureUnit(to: unit)
                        }
                    ),
                    field: .outletPressure,
                    accessibilityIdentifier: "stream-mixing-outlet-pressure"
                )

                operatingPointRow(
                    title: "Outlet temperature",
                    value: Binding(
                        get: { viewModel.outletTemperatureText },
                        set: { viewModel.updateOutletTemperatureText($0) }
                    ),
                    unit: Binding(
                        get: { viewModel.outletTemperatureDisplayUnit },
                        set: { unit in
                            focusedField = nil
                            viewModel.changeOutletTemperatureUnit(to: unit)
                        }
                    ),
                    field: .outletTemperature,
                    accessibilityIdentifier: "stream-mixing-outlet-temperature"
                )

                ForEach(viewModel.outletIssues()) { issue in
                    ValidationIssueLabel(issue: issue)
                }
            } header: {
                IFESectionHeader(
                    step: 2,
                    title: "Outlet conditions",
                    subtitle: "Defined by the user for later property evaluation."
                )
            } footer: {
                Text("Stream Mixing v1 does not infer outlet pressure or temperature from inlet streams.")
            }

            Section {
                Button {
                    focusedField = nil
                    viewModel.calculate()
                } label: {
                    Text("Calculate mixture")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canCalculate)
                .accessibilityIdentifier("stream-mixing-calculate")
            } header: {
                IFESectionHeader(step: 3, title: "Calculate mixture")
            }

            Section {
                Label(
                    viewModel.statusMessage,
                    systemImage: viewModel.validationReport.canCalculate
                        ? "checkmark.circle.fill"
                        : "xmark.octagon.fill"
                )
                .foregroundStyle(viewModel.validationReport.canCalculate ? Color.pxSuccess : Color.pxError)
                .accessibilityIdentifier("stream-mixing-status")

                let globalIssues = viewModel.validationReport.issues.filter { $0.streamID == nil }
                ForEach(globalIssues) { issue in
                    ValidationIssueLabel(issue: issue)
                }

                if viewModel.result != nil, viewModel.isResultStale {
                    Label(
                        "Displayed result is stale because inputs changed.",
                        systemImage: "clock.badge.exclamationmark"
                    )
                    .foregroundStyle(Color.pxWarning)
                    .accessibilityIdentifier("stream-mixing-stale-result")
                }

                if let result = viewModel.result {
                    ForEach(result.warnings) { warning in
                        Label(warning.message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.pxWarning)
                            .accessibilityIdentifier("stream-mixing-warning")
                    }
                }
            } header: {
                IFESectionHeader(step: 4, title: "Validation and status")
            }

            if let result = viewModel.result {
                StreamMixingResultSections(
                    result: result,
                    displayCompositionBasis: $viewModel.displayCompositionBasis,
                    isStale: viewModel.isResultStale
                )
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .ifeDottedBackground()
        .navigationTitle("Stream Mixing")
        .accessibilityIdentifier("stream-mixing-screen")
        .onAppear { viewModel.validate() }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                if isTemperatureField(focusedField) {
                    Button("Minus") {
                        insertMinusSign()
                    }
                    .accessibilityIdentifier("stream-mixing-keyboard-minus")
                    .accessibilityLabel("Insert minus sign")
                }
                if focusedField != nil {
                    Button("Done") {
                        focusedField = nil
                    }
                    .font(.body.weight(.semibold))
                    .accessibilityIdentifier("stream-mixing-keyboard-done")
                }
            }
        }
    }

    private func operatingPointRow(
        title: String,
        value: Binding<String>,
        unit: Binding<PressureDisplayUnit>,
        field: StreamMixingInputField,
        accessibilityIdentifier: String
    ) -> some View {
        UnitAwareNumericField(
            title: title,
            text: value,
            selection: textSelectionBinding(for: accessibilityIdentifier),
            keyboardType: .decimalPad,
            isFocused: focusedField == field,
            unitLabel: unit.wrappedValue.rawValue,
            unitOptions: PressureDisplayUnit.allCases.map(\.rawValue),
            selectedUnit: unit.wrappedValue.rawValue,
            accessibilityIdentifier: accessibilityIdentifier,
            unitAction: { selectedUnit in
                guard let selected = PressureDisplayUnit.allCases.first(where: {
                    $0.rawValue == selectedUnit
                }) else { return }
                unit.wrappedValue = selected
            }
        )
        .focused($focusedField, equals: field)
    }

    private func operatingPointRow(
        title: String,
        value: Binding<String>,
        unit: Binding<TemperatureDisplayUnit>,
        field: StreamMixingInputField,
        accessibilityIdentifier: String
    ) -> some View {
        UnitAwareNumericField(
            title: title,
            text: value,
            selection: textSelectionBinding(for: accessibilityIdentifier),
            keyboardType: .decimalPad,
            isFocused: focusedField == field,
            unitLabel: unit.wrappedValue.rawValue,
            unitOptions: TemperatureDisplayUnit.allCases.map(\.rawValue),
            selectedUnit: unit.wrappedValue.rawValue,
            accessibilityIdentifier: accessibilityIdentifier,
            unitAction: { selectedUnit in
                guard let selected = TemperatureDisplayUnit.allCases.first(where: {
                    $0.rawValue == selectedUnit
                }) else { return }
                unit.wrappedValue = selected
            }
        )
        .focused($focusedField, equals: field)
    }

    private func isTemperatureField(_ field: StreamMixingInputField?) -> Bool {
        switch field {
        case .outletTemperature, .streamTemperature:
            true
        default:
            false
        }
    }

    private func insertMinusSign() {
        switch focusedField {
        case .outletTemperature:
            toggleMinus(in: &viewModel.outletTemperatureText)
        case let .streamTemperature(id):
            guard let index = viewModel.streams.firstIndex(where: { $0.id == id }) else { return }
            toggleMinus(in: &viewModel.streams[index].temperatureText)
            viewModel.markInputsChanged()
        default:
            break
        }
    }

    private func toggleMinus(in text: inout String) {
        if text.hasPrefix("-") || text.hasPrefix("−") {
            text.removeFirst()
        } else {
            text.insert("-", at: text.startIndex)
        }
    }

    private func textSelectionBinding(for id: String) -> Binding<TextSelection?> {
        Binding(
            get: { textSelections[id] },
            set: { selection in
                if let selection {
                    textSelections[id] = selection
                } else {
                    textSelections.removeValue(forKey: id)
                }
            }
        )
    }
}

private struct StreamInputCard: View {
    @Binding var stream: StreamInputState
    let viewModel: StreamMixingViewModel
    var focusedField: FocusState<StreamMixingInputField?>.Binding
    @Binding var textSelections: [String: TextSelection]

    var body: some View {
        VStack(alignment: .leading, spacing: IFESpacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                TextField(
                    "Stream name",
                    text: Binding(
                        get: { stream.name },
                        set: { viewModel.updateStreamName(streamID: stream.id, value: $0) }
                    )
                )
                    .font(.headline)
                    .textInputAutocapitalization(.words)
                    .focused(focusedField, equals: .streamName(stream.id))
                    .accessibilityLabel("Stream name")
                    .accessibilityIdentifier("stream-name-\(stream.id.uuidString)")

                Menu {
                    Button("Duplicate stream", systemImage: "plus.square.on.square") {
                        _ = viewModel.duplicateStream(id: stream.id)
                    }
                    .disabled(!viewModel.canAddStream)

                    Button("Move up", systemImage: "chevron.up") {
                        viewModel.moveStreamUp(id: stream.id)
                    }
                    .disabled(!viewModel.canMoveStreamUp(id: stream.id))

                    Button("Move down", systemImage: "chevron.down") {
                        viewModel.moveStreamDown(id: stream.id)
                    }
                    .disabled(!viewModel.canMoveStreamDown(id: stream.id))

                    Button("Remove stream", systemImage: "trash", role: .destructive) {
                        viewModel.removeStream(id: stream.id)
                    }
                    .disabled(!viewModel.canRemoveStream)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Stream actions")
                .accessibilityIdentifier("stream-actions-\(stream.id.uuidString)")
            }

            flowRow

            UnitAwareNumericField(
                title: "Pressure",
                text: Binding(
                    get: { stream.pressureText },
                    set: { viewModel.updatePressureText(streamID: stream.id, value: $0) }
                ),
                selection: textSelectionBinding(for: "stream-pressure-\(stream.id.uuidString)"),
                keyboardType: .decimalPad,
                isFocused: focusedField.wrappedValue == .streamPressure(stream.id),
                unitLabel: stream.pressureDisplayUnit.rawValue,
                unitOptions: PressureDisplayUnit.allCases.map(\.rawValue),
                selectedUnit: stream.pressureDisplayUnit.rawValue,
                accessibilityIdentifier: "stream-pressure-\(stream.id.uuidString)",
                unitAction: { selectedUnit in
                    guard let selected = PressureDisplayUnit.allCases.first(where: {
                        $0.rawValue == selectedUnit
                    }) else { return }
                    viewModel.changeStreamPressureUnit(streamID: stream.id, to: selected)
                }
            )
            .focused(focusedField, equals: .streamPressure(stream.id))

            UnitAwareNumericField(
                title: "Temperature",
                text: Binding(
                    get: { stream.temperatureText },
                    set: { viewModel.updateTemperatureText(streamID: stream.id, value: $0) }
                ),
                selection: textSelectionBinding(for: "stream-temperature-\(stream.id.uuidString)"),
                keyboardType: .decimalPad,
                isFocused: focusedField.wrappedValue == .streamTemperature(stream.id),
                unitLabel: stream.temperatureDisplayUnit.rawValue,
                unitOptions: TemperatureDisplayUnit.allCases.map(\.rawValue),
                selectedUnit: stream.temperatureDisplayUnit.rawValue,
                accessibilityIdentifier: "stream-temperature-\(stream.id.uuidString)",
                unitAction: { selectedUnit in
                    guard let selected = TemperatureDisplayUnit.allCases.first(where: {
                        $0.rawValue == selectedUnit
                    }) else { return }
                    viewModel.changeStreamTemperatureUnit(streamID: stream.id, to: selected)
                }
            )
            .focused(focusedField, equals: .streamTemperature(stream.id))

            Menu("Load built-in case", systemImage: "tray.and.arrow.down") {
                ForEach(BuiltInCaseCatalog.cases) { builtInCase in
                    Button(builtInCase.name) {
                        viewModel.loadBuiltInCase(builtInCase, into: stream.id)
                    }
                    .accessibilityIdentifier("load-\(builtInCase.id)-into-\(stream.id.uuidString)")
                }
            }
            .accessibilityIdentifier("load-built-in-case-\(stream.id.uuidString)")

            StreamCompositionEditor(
                stream: $stream,
                viewModel: viewModel,
                focusedField: focusedField,
                textSelections: $textSelections
            )

            let issues = viewModel.issues(for: stream.id)
            if !issues.isEmpty {
                VStack(alignment: .leading, spacing: IFESpacing.small) {
                    ForEach(issues) { issue in
                        ValidationIssueLabel(issue: issue)
                    }

                    if viewModel.canNormalize(streamID: stream.id) {
                        Button("Review and apply normalization") {
                            viewModel.applyExplicitNormalization(for: stream.id)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("stream-normalize-\(stream.id.uuidString)")
                    }
                }
            }
        }
        .padding(.vertical, IFESpacing.small)
    }

    private var flowRow: some View {
        UnitAwareNumericField(
            title: "Flow rate",
            text: Binding(
                get: { stream.flowText },
                set: { viewModel.updateFlowText(streamID: stream.id, value: $0) }
            ),
            selection: textSelectionBinding(for: "stream-flow-\(stream.id.uuidString)"),
            keyboardType: .decimalPad,
            isFocused: focusedField.wrappedValue == .streamFlow(stream.id),
            unitLabel: stream.flowUnit.rawValue,
            unitOptions: StreamFlowUnit.allCases.map(\.rawValue),
            selectedUnit: stream.flowUnit.rawValue,
            accessibilityIdentifier: "stream-flow-\(stream.id.uuidString)",
            unitAction: { selectedUnit in
                guard let selected = StreamFlowUnit.allCases.first(where: {
                    $0.rawValue == selectedUnit
                }) else { return }
                viewModel.changeStreamFlowUnit(streamID: stream.id, to: selected)
            }
        )
        .focused(focusedField, equals: .streamFlow(stream.id))
    }

    private func textSelectionBinding(for id: String) -> Binding<TextSelection?> {
        Binding(
            get: { textSelections[id] },
            set: { selection in
                if let selection {
                    textSelections[id] = selection
                } else {
                    textSelections.removeValue(forKey: id)
                }
            }
        )
    }
}

private struct StreamCompositionEditor: View {
    @Binding var stream: StreamInputState
    let viewModel: StreamMixingViewModel
    var focusedField: FocusState<StreamMixingInputField?>.Binding
    @Binding var textSelections: [String: TextSelection]

    var body: some View {
        VStack(alignment: .leading, spacing: IFESpacing.small) {
            Picker(
                "Composition basis",
                selection: Binding(
                    get: { stream.compositionBasis },
                    set: { basis in
                        viewModel.changeCompositionBasis(streamID: stream.id, to: basis)
                    }
                )
            ) {
                ForEach(CompositionUnit.allCases) { basis in
                    Text(compositionBasisLabel(basis)).tag(basis)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("stream-composition-basis-\(stream.id.uuidString)")

            ForEach($stream.composition) { $entry in
                HStack(spacing: IFESpacing.small) {
                    if entry.component == .carbonDioxide {
                        Text(entry.component.symbol)
                            .font(.body.weight(.medium))
                            .accessibilityLabel("Carbon dioxide")
                    } else {
                        Menu {
                            ForEach(viewModel.impurityOptions(
                                streamID: stream.id,
                                including: entry.component
                            )) { component in
                                Button {
                                    viewModel.updateImpurity(
                                        streamID: stream.id,
                                        entryID: entry.id,
                                        component: component
                                    )
                                } label: {
                                    if component == entry.component {
                                        Label(component.symbol, systemImage: "checkmark")
                                    } else {
                                        Text(component.symbol)
                                    }
                                }
                            }

                            Divider()

                            Button("Remove impurity", systemImage: "trash", role: .destructive) {
                                viewModel.removeImpurity(streamID: stream.id, entryID: entry.id)
                            }
                        } label: {
                            HStack(spacing: IFESpacing.xSmall) {
                                Text(entry.component.symbol)
                                Image(systemName: "chevron.down")
                                    .font(.caption.weight(.semibold))
                            }
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        }
                        .accessibilityLabel("\(entry.component.symbol) impurity menu")
                        .accessibilityIdentifier("stream-\(stream.id.uuidString)-\(entry.component.rawValue)-menu")
                    }

                    Spacer(minLength: IFESpacing.small)

                    TextField(
                        "Value",
                        text: Binding(
                            get: { entry.value },
                            set: {
                                viewModel.updateCompositionValue(
                                    streamID: stream.id,
                                    entryID: entry.id,
                                    value: $0
                                )
                            }
                        ),
                        selection: textSelectionBinding(for: "stream-composition-\(stream.id.uuidString)-\(entry.id.uuidString)")
                    )
                    .keyboardType(.decimalPad)
                    .focused(focusedField, equals: .composition(stream.id, entry.id))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 104)
                    .padding(.horizontal, IFESpacing.small)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: IFECornerRadius.field)
                            .fill(Color.secondary.opacity(0.08))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: IFECornerRadius.field)
                            .stroke(Color.secondary.opacity(0.22), lineWidth: IFELine.hairline)
                    }
                    .accessibilityLabel("\(entry.component.symbol) \(compositionBasisLabel(stream.compositionBasis))")
                    .accessibilityIdentifier("stream-\(stream.id.uuidString)-\(entry.component.rawValue)-composition")

                    Text(compositionBasisLabel(stream.compositionBasis))
                        .foregroundStyle(.secondary)
                        .frame(width: 84, alignment: .leading)
                        .accessibilityHidden(true)
                }
            }
            .onMove { source, destination in
                viewModel.moveImpurities(streamID: stream.id, from: source, to: destination)
            }

            Button("Add impurity", systemImage: "plus") {
                _ = viewModel.addImpurity(to: stream.id)
            }
            .disabled(stream.composition.count >= ComponentID.allCases.count)
            .accessibilityIdentifier("stream-add-impurity-\(stream.id.uuidString)")
        }
    }

    private func compositionBasisLabel(_ basis: CompositionUnit) -> String {
        switch basis {
        case .moleFraction:
            "mole frac"
        case .molePercent:
            "mol%"
        case .partsPerMillion:
            "ppm"
        case .massFraction:
            "mass frac"
        }
    }

    private func textSelectionBinding(for id: String) -> Binding<TextSelection?> {
        Binding(
            get: { textSelections[id] },
            set: { selection in
                if let selection {
                    textSelections[id] = selection
                } else {
                    textSelections.removeValue(forKey: id)
                }
            }
        )
    }
}

private struct ValidationIssueLabel: View {
    let issue: StreamMixingValidationIssue

    var body: some View {
        Label(issue.message, systemImage: "xmark.octagon.fill")
            .foregroundStyle(Color.pxError)
            .font(.subheadline)
            .accessibilityIdentifier("stream-mixing-validation-issue")
    }
}

private struct StreamMixingResultSections: View {
    let result: MixedCompositionResult
    @Binding var displayCompositionBasis: CompositionUnit
    let isStale: Bool

    var body: some View {
        Section {
            ScientificStatusBanner(
                title: isStale ? "Stale stream-mixing result" : "Preliminary V1 aggregation",
                message: "Composition and flow totals are conserved at user-defined outlet conditions. No thermodynamic outlet state was evaluated."
            )
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            IFEValueRow(
                title: "Total molar flow",
                value: number(result.totalMolarFlowMolesPerSecond),
                unit: "mol/s"
            )
            .accessibilityIdentifier("stream-mixing-total-molar-flow")

            IFEValueRow(
                title: "Total mass flow",
                value: number(result.totalMassFlowKilogramsPerSecond),
                unit: "kg/s"
            )
            .accessibilityIdentifier("stream-mixing-total-mass-flow")
        } header: {
            IFESectionHeader(step: 5, title: "Mixed-stream results")
        }

        Section {
            Picker("Display basis", selection: $displayCompositionBasis) {
                Text("Mole fraction").tag(CompositionUnit.moleFraction)
                Text("mol%").tag(CompositionUnit.molePercent)
                Text("ppm").tag(CompositionUnit.partsPerMillion)
            }
            .pickerStyle(.segmented)

            ForEach(result.composition) { component in
                IFEValueRow(
                    title: component.component.symbol,
                    value: displayCompositionValue(component.moleFraction),
                    unit: displayCompositionUnit,
                    status: "Canonical \(number(component.moleFraction)) mole fraction"
                )
            }
        } header: {
            IFESectionHeader(step: nil, title: "Mixed composition")
        }

        Section {
            ForEach(result.streamContributions) { contribution in
                IFEExpandableRow(contribution.streamName) {
                    IFEValueRow(
                        title: "Stable identifier",
                        value: contribution.streamID.uuidString
                    )
                    IFEValueRow(
                        title: "Molar flow",
                        value: number(contribution.molarFlowMolesPerSecond),
                        unit: "mol/s"
                    )
                    IFEValueRow(
                        title: "Mass flow",
                        value: number(contribution.massFlowKilogramsPerSecond),
                        unit: "kg/s"
                    )
                    ForEach(contribution.componentMolarFlows) { flow in
                        IFEValueRow(
                            title: "\(flow.component.symbol) molar flow",
                            value: number(flow.molarFlowMolesPerSecond),
                            unit: "mol/s",
                            status: "\(number(flow.massFlowKilogramsPerSecond)) kg/s"
                        )
                    }
                }
            }
        } header: {
            IFESectionHeader(step: nil, title: "Per-stream contributions")
        }

        Section {
            IFEExpandableRow("Assumptions and traceability") {
                traceabilityContent
            }
            .accessibilityIdentifier("stream-mixing-traceability")
        } header: {
            IFESectionHeader(step: 6, title: "Assumptions and traceability")
        }
    }

    @ViewBuilder
    private var traceabilityContent: some View {
        LabeledContent("Calculation status", value: result.status.rawValue.capitalized)
        LabeledContent("Request ID") {
            Text(result.requestID.uuidString)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
        LabeledContent(
            "Outlet pressure — entered",
            value: "\(number(result.outlet.pressureValue)) \(result.outlet.pressureUnit.rawValue)"
        )
        LabeledContent("Outlet pressure — SI", value: "\(number(result.outlet.pressurePa)) Pa")
        LabeledContent(
            "Outlet temperature — entered",
            value: "\(number(result.outlet.temperatureValue)) \(result.outlet.temperatureUnit.rawValue)"
        )
        LabeledContent("Outlet temperature — SI", value: "\(number(result.outlet.temperatureK)) K")

        ForEach(result.assumptions) { assumption in
            LabeledContent("Assumption") {
                Text(assumption.message)
                    .multilineTextAlignment(.trailing)
            }
        }

        if !result.warnings.isEmpty {
            LabeledContent("Warnings recorded", value: "\(result.warnings.count)")
        }

        LabeledContent(
            "Molar-flow residual",
            value: "\(number(result.conservation.totalMolarFlowResidual)) mol/s"
        )
        LabeledContent(
            "Mass-flow residual",
            value: "\(number(result.conservation.totalMassFlowResidual)) kg/s"
        )
        LabeledContent(
            "Molar tolerance",
            value: "\(number(result.conservation.molarFlowAbsoluteTolerance)) abs, \(number(result.conservation.molarFlowRelativeTolerance)) rel"
        )
        LabeledContent(
            "Mass tolerance",
            value: "\(number(result.conservation.massFlowAbsoluteTolerance)) abs, \(number(result.conservation.massFlowRelativeTolerance)) rel"
        )

        ForEach(result.streamContributions) { contribution in
            IFEExpandableRow("Input provenance — \(contribution.streamName)") {
                LabeledContent("Stable identifier", value: contribution.streamID.uuidString)
                LabeledContent(
                    "Entered flow",
                    value: "\(number(contribution.input.flowValue)) \(contribution.input.flowUnit.rawValue)"
                )
                LabeledContent("Flow basis", value: contribution.input.flowBasis.rawValue)
                LabeledContent("Canonical molar flow", value: "\(number(contribution.molarFlowMolesPerSecond)) mol/s")
                LabeledContent("Canonical mass flow", value: "\(number(contribution.massFlowKilogramsPerSecond)) kg/s")
                LabeledContent(
                    "Entered pressure",
                    value: "\(number(contribution.input.pressureValue)) \(contribution.input.pressureUnit.rawValue)"
                )
                LabeledContent("Pressure SI", value: "\(number(contribution.input.pressurePa)) Pa")
                LabeledContent(
                    "Entered temperature",
                    value: "\(number(contribution.input.temperatureValue)) \(contribution.input.temperatureUnit.rawValue)"
                )
                LabeledContent("Temperature SI", value: "\(number(contribution.input.temperatureK)) K")
                LabeledContent("Original composition") {
                    Text(originalCompositionText(contribution.input.originalComposition))
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Converted composition") {
                    Text(moleFractionText(contribution.input.convertedComposition))
                        .multilineTextAlignment(.trailing)
                }
                if let normalized = contribution.input.normalizedComposition {
                    LabeledContent("Explicitly normalized composition") {
                        Text(moleFractionText(normalized))
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
    }

    private var displayCompositionUnit: String {
        switch displayCompositionBasis {
        case .moleFraction:
            "mole frac"
        case .molePercent:
            "mol%"
        case .partsPerMillion:
            "ppm"
        case .massFraction:
            "mole frac"
        }
    }

    private func displayCompositionValue(_ moleFraction: Double) -> String {
        switch displayCompositionBasis {
        case .moleFraction, .massFraction:
            number(moleFraction)
        case .molePercent:
            number(moleFraction * 100)
        case .partsPerMillion:
            number(moleFraction * 1_000_000)
        }
    }

    private func originalCompositionText(_ composition: [CompositionInputSnapshot]) -> String {
        composition.map {
            "\($0.component.symbol) \(number($0.value)) \($0.unit.rawValue)"
        }.joined(separator: ", ")
    }

    private func moleFractionText(_ composition: [MixtureComponent]) -> String {
        composition.map {
            "\($0.component.symbol) \(number($0.moleFraction))"
        }.joined(separator: ", ")
    }

    private func number(_ value: Double) -> String {
        guard value.isFinite else { return "Unavailable" }
        return String(format: "%.8g", value)
    }
}

private struct ModelSelectionRow: View {
    let descriptor: ModelDescriptor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: IFESpacing.regular) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.ifePrimary : Color.secondary)
                    .font(.title3)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: IFESpacing.xSmall) {
                    Text(displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(statusDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: IFESpacing.small) {
                        if descriptor.availability == .unavailable {
                            IFEStatusBadge(
                                text: "Unavailable",
                                systemImage: "slash.circle",
                                color: .pxUnavailable
                            )
                        }
                        IFEStatusBadge(
                            text: "Local",
                            systemImage: "iphone",
                            color: .secondary
                        )
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(displayName), \(descriptor.availability.rawValue)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(
            descriptor.availability == .unavailable
                ? "This model is unavailable and cannot be selected."
                : "Selects this thermodynamic model."
        )
    }

    private var displayName: String {
        switch descriptor.id {
        case "coolprop-heos":
            "General Properties"
        case "ife-model":
            "IFE Model — Unavailable"
        default:
            descriptor.name
        }
    }

    private var statusDescription: String {
        if descriptor.id == "coolprop-heos" {
            return "Broad engineering property coverage"
        }
        if descriptor.id == "teqp-pure-co2-experimental" {
            return "Validated CCS impurity and mixture ranges"
        }
        return switch descriptor.availability {
        case .available:
            "Available for local calculations within the recorded provider domain."
        case .preliminary:
            "Operational local model."
        case .unavailable:
            "Visible for future traceability. It will not fall back to another provider."
        }
    }

}

private struct UnitAwareNumericField: View {
    let title: String
    @Binding var text: String
    @Binding var selection: TextSelection?
    let keyboardType: UIKeyboardType
    let isFocused: Bool
    let unitLabel: String
    let unitOptions: [String]
    let selectedUnit: String
    let accessibilityIdentifier: String
    let unitAction: (String) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: IFESpacing.regular) {
                titleView
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(2)
                controlGroup
                    .layoutPriority(3)
            }

            VStack(alignment: .leading, spacing: IFESpacing.small) {
                titleView
                controlGroup
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var titleView: some View {
        VStack(alignment: .leading, spacing: IFESpacing.xSmall) {
            Text(title)
                .font(.body.weight(.medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .multilineTextAlignment(.leading)
                .accessibilityIdentifier("\(accessibilityIdentifier)-label")
        }
    }

    private var controlGroup: some View {
        HStack(spacing: IFESpacing.regular) {
            inputView
            unitMenu
        }
    }

    private var inputView: some View {
        TextField("Value", text: $text, selection: $selection)
            .keyboardType(keyboardType)
            .multilineTextAlignment(.trailing)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.body.monospacedDigit())
            .frame(width: 132)
            .padding(.horizontal, IFESpacing.small)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: IFECornerRadius.field)
                    .fill(Color.secondary.opacity(0.08))
            )
            .overlay {
                RoundedRectangle(cornerRadius: IFECornerRadius.field)
                    .stroke(
                        isFocused ? Color.ifePrimary : Color.secondary.opacity(0.22),
                        lineWidth: isFocused ? IFELine.focus : IFELine.hairline
                    )
            }
            .contentShape(Rectangle())
            .accessibilityLabel("\(title) value")
            .accessibilityValue("\(text) \(unitLabel)")
            .accessibilityIdentifier("\(accessibilityIdentifier)-value-field")
    }

    private var unitMenu: some View {
        Menu {
            ForEach(unitOptions, id: \.self) { option in
                Button {
                    unitAction(option)
                } label: {
                    if option == selectedUnit {
                        Label(option, systemImage: "checkmark")
                    } else {
                        Text(option)
                    }
                }
                .accessibilityIdentifier("\(accessibilityIdentifier)-unit-option-\(option)")
            }
        } label: {
            HStack(spacing: IFESpacing.xSmall) {
                Text(selectedUnit)
                    .font(.body.weight(.medium).monospacedDigit())
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, IFESpacing.regular)
            .padding(.vertical, 8)
            .frame(minWidth: 86)
            .background(Color.pxSurface, in: RoundedRectangle(cornerRadius: IFECornerRadius.field))
            .overlay {
                RoundedRectangle(cornerRadius: IFECornerRadius.field)
                    .stroke(Color.pxSeparator.opacity(0.7), lineWidth: IFELine.hairline)
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel("\(title) unit")
        .accessibilityValue(selectedUnit)
        .accessibilityIdentifier("\(accessibilityIdentifier)-unit-menu")
    }
}

private struct WaterEquilibriumSection: View {
    let equilibrium: CarbonDioxideWaterEquilibriumResult
    var step: Int? = nil

    var body: some View {
        Section {
            IFEValueRow(
                title: "Water status",
                value: equilibrium.waterStatus.displayName,
                status: equilibrium.validationStatus
            )
            IFEValueRow(
                title: "Water saturation in CO₂-rich phase",
                value: number(equilibrium.waterInCarbonDioxideRichPhasePPM),
                unit: "ppm (mole)"
            )
            if let current = equilibrium.currentWaterPPM {
                IFEValueRow(title: "Current water content", value: number(current), unit: "ppm (mole)")
            }
            if let margin = equilibrium.marginToSaturationPPM {
                IFEValueRow(title: "Margin to saturation", value: number(margin), unit: "ppm (mole)")
            }
            if let ratio = equilibrium.waterSaturationRatio {
                IFEValueRow(title: "Water saturation ratio", value: number(ratio), unit: "current / saturation")
            }
            IFEValueRow(
                title: "CO₂ in H₂O-rich phase",
                value: number(equilibrium.carbonDioxideInWaterRichPhaseMoleFraction * 100),
                unit: "mol%"
            )
            if let dropoutPressurePa = equilibrium.waterDropoutPressurePa {
                IFEValueRow(
                    title: "Water-dropout pressure",
                    value: number(dropoutPressurePa / 100_000),
                    unit: "bar(a)",
                    status: "Preliminary bounded solve; no extrapolation"
                )
            }
            if let dropoutTemperatureK = equilibrium.waterDropoutTemperatureK {
                IFEValueRow(
                    title: "Water-dropout temperature",
                    value: number(dropoutTemperatureK - 273.15),
                    unit: "°C",
                    status: "Directly validated bounded solve, 30–80 °C and 4.999–50.055 bar(a)"
                )
            }
            IFEValueRow(
                title: "Equilibrium model",
                value: equilibrium.modelIdentifier,
                status: "Binary CO₂ + pure H₂O only"
            )
        } header: {
            IFESectionHeader(step: step, title: "Water equilibrium")
        }
    }

    private func number(_ value: Double) -> String {
        value.formatted(.number.precision(.significantDigits(1...7)))
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

    private var validatedProperties: Set<PropertyID> {
        Set(AdvancedValidationPresentation.validatedProperties(for: record))
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
            Section {
                if !record.response.isScientificResult {
                    ScientificStatusBanner(
                        title: "Non-scientific result",
                        message: "See Calculation Details for recorded provider status and provenance."
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                IFEValueRow(
                    title: "Phase",
                    value: record.response.phase.displayName,
                    status: "Returned by provider",
                    statusColor: .ifePrimary
                )
                IFEValueRow(
                    title: "Pressure",
                    value: number(record.input.pressureValue),
                    unit: record.input.pressureDisplayUnitLabel,
                    copyValue: "\(record.input.pressureValue)"
                )
                IFEValueRow(
                    title: "Temperature",
                    value: number(record.input.temperatureValue),
                    unit: record.input.temperatureUnit.rawValue,
                    copyValue: "\(record.input.temperatureValue)"
                )

                ForEach(stateProperties, id: \.property) { property in
                    PropertyResultRow(
                        property: property,
                        isValidated: validatedProperties.contains(property.property)
                    )
                }
            } header: {
                IFESectionHeader(step: 6, title: "Results and phase information")
            }

            Section("Composition summary") {
                IFEValueRow(
                    title: "Mixture",
                    value: SavedCaseNameFormatter.compositionLabel(for: record.request.composition)
                )
                IFEValueRow(
                    title: "Original input",
                    value: originalCompositionText
                )
                if record.input.normalizedComposition == nil {
                    IFEValueRow(
                        title: "Normalization",
                        value: "Not applied"
                    )
                }
            }

            if let equilibrium = record.response.waterEquilibrium {
                WaterEquilibriumSection(equilibrium: equilibrium)
            }

            ForEach(ResultGroup.allCases, id: \.self) { group in
                let properties = calculatedProperties(in: group.properties)
                if !properties.isEmpty {
                    Section(group.rawValue) {
                        ForEach(properties, id: \.property) { property in
                            PropertyResultRow(
                                property: property,
                                isValidated: validatedProperties.contains(property.property)
                            )
                        }
                    }
                }
            }

            if !unavailableProperties.isEmpty {
                Section {
                    IFEExpandableRow("Unavailable properties (\(unavailableProperties.count))") {
                        ForEach(unavailableProperties, id: \.property) { property in
                            PropertyResultRow(property: property, isValidated: false)
                        }
                    }
                }
            }

            Section("Scientific traceability") {
                IFEValueRow(
                    title: "Provider",
                    value: record.response.model.name,
                    status: "\(record.response.model.providerVersion) • \(record.response.model.availability.rawValue.capitalized)"
                )
                IFEValueRow(
                    title: "Model",
                    value: record.response.model.modelVersion,
                    status: record.response.model.equationOrMethod
                )
                IFEExpandableRow("Calculation details") { traceabilityContent }
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

        LabeledContent("Pressure — entered", value: "\(number(record.input.pressureValue)) \(record.input.pressureDisplayUnitLabel)")
        LabeledContent("Pressure — SI", value: "\(number(record.input.pressurePa)) Pa")
        LabeledContent("Temperature — entered", value: "\(number(record.input.temperatureValue)) \(record.input.temperatureUnit.rawValue)")
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
            Text("Scientific references")
                .font(.subheadline.weight(.semibold))

            ForEach(Array(record.response.model.references.enumerated()), id: \.offset) { index, reference in
                if let url = ReferenceLinkResolver.url(for: reference.doiOrURL) {
                    Link(destination: url) {
                        scientificReferenceLabel(reference, address: reference.doiOrURL)
                    }
                    .id("scientific-reference-\(index)-\(url.absoluteString)")
                    .accessibilityLabel(
                        "\(reference.authors), \(reference.title), open reference"
                    )
                    .accessibilityHint("Opens this reference in the browser.")
                } else {
                    scientificReferenceLabel(reference, address: nil)
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
    var isValidated = false

    private var presentation: PropertyResultPresentation {
        PropertyResultPresentation(property: property)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: IFESpacing.small) {
            IFEValueRow(
                title: presentation.title,
                value: presentation.value,
                unit: presentation.unit,
                status: isValidated ? presentation.validatedStatusText : presentation.statusText,
                statusColor: isValidated ? .pxSuccess : presentation.statusColor,
                copyValue: presentation.copyValue
            )
            if isValidated {
                Image(systemName: "checkmark.shield.fill")
                    .font(.caption)
                    .foregroundStyle(Color.pxSuccess)
                    .accessibilityLabel("\(presentation.title), validated for current state")
                    .accessibilityIdentifier("validated-property-\(property.property.rawValue)")
            }
        }
    }
}

struct PropertyResultPresentation {
    let property: PropertyValue

    var title: String {
        property.property.displayName
    }

    var effectiveStatus: PropertyStatus {
        EngineeringPropertyFormatter.effectiveStatus(for: property)
    }

    var value: String {
        displayValue.value
    }

    var unit: String? {
        displayValue.unit
    }

    private var displayValue: (value: String, unit: String?) {
        guard let measurement = EngineeringPropertyFormatter.measurement(for: property) else {
            return (EngineeringPropertyFormatter.effectiveStatus(for: property).displayName, nil)
        }
        return (
            measurement.value.formatted(.number.precision(.significantDigits(1...7))),
            measurement.unit.isEmpty ? nil : measurement.unit
        )
    }

    var statusText: String {
        [effectiveStatus.displayName, property.message].compactMap { $0 }.joined(separator: " — ")
    }

    var validatedStatusText: String {
        ["Validated", property.message].compactMap { $0 }.joined(separator: " — ")
    }

    var statusColor: Color {
        switch effectiveStatus {
        case .calculated:
            .pxSuccess
        case .unavailable:
            .pxUnavailable
        case .outsideValidatedRange, .extrapolated:
            .pxWarning
        case .failed:
            .pxError
        }
    }

    var copyValue: String? {
        guard let value = property.value, value.isFinite else { return nil }
        return "\(value) \(property.unit)"
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
