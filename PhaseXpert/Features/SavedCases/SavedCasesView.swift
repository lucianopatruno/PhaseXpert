import Foundation
import PhaseXpertCore
import SwiftData
import SwiftUI

@Model
final class SavedCalculation {
    @Attribute(.unique) var id: UUID
    var name: String
    var notes: String
    var createdAt: Date
    var updatedAt: Date
    var calculationID: UUID
    var calculatedAt: Date
    var modelIdentifier: String
    var modelName: String
    var phaseIdentifier: String
    var pressureBarAbsolute: Double
    var temperatureCelsius: Double
    var recordFormatVersion: Int
    var recordData: Data

    init(
        id: UUID = UUID(),
        name: String,
        notes: String = "",
        record: CalculationRecord,
        createdAt: Date = Date()
    ) throws {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.calculationID = record.response.calculationID
        self.calculatedAt = record.response.calculatedAt
        self.modelIdentifier = record.response.model.id
        self.modelName = record.response.model.name
        self.phaseIdentifier = record.response.phase.rawValue
        self.pressureBarAbsolute = record.input.pressurePa / 100_000
        self.temperatureCelsius = record.input.temperatureK - 273.15
        self.recordFormatVersion = 1
        self.recordData = try JSONEncoder().encode(record)
    }

    var calculationRecord: CalculationRecord? {
        guard recordFormatVersion == 1 else { return nil }
        return try? JSONDecoder().decode(CalculationRecord.self, from: recordData)
    }

    func updateMetadata(name: String, notes: String, updatedAt: Date = Date()) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        self.updatedAt = updatedAt
    }

    func duplicate(createdAt: Date = Date()) -> SavedCalculation {
        let copy = SavedCalculation(
            id: UUID(),
            name: "\(name) — Copy",
            notes: notes,
            createdAt: createdAt,
            updatedAt: createdAt,
            calculationID: calculationID,
            calculatedAt: calculatedAt,
            modelIdentifier: modelIdentifier,
            modelName: modelName,
            phaseIdentifier: phaseIdentifier,
            pressureBarAbsolute: pressureBarAbsolute,
            temperatureCelsius: temperatureCelsius,
            recordFormatVersion: recordFormatVersion,
            recordData: recordData
        )
        return copy
    }

    private init(
        id: UUID,
        name: String,
        notes: String,
        createdAt: Date,
        updatedAt: Date,
        calculationID: UUID,
        calculatedAt: Date,
        modelIdentifier: String,
        modelName: String,
        phaseIdentifier: String,
        pressureBarAbsolute: Double,
        temperatureCelsius: Double,
        recordFormatVersion: Int,
        recordData: Data
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.calculationID = calculationID
        self.calculatedAt = calculatedAt
        self.modelIdentifier = modelIdentifier
        self.modelName = modelName
        self.phaseIdentifier = phaseIdentifier
        self.pressureBarAbsolute = pressureBarAbsolute
        self.temperatureCelsius = temperatureCelsius
        self.recordFormatVersion = recordFormatVersion
        self.recordData = recordData
    }
}

enum PhaseXpertSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [SavedCalculation.self]
    }
}

enum PhaseXpertMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [PhaseXpertSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

enum SavedCaseSort: String, CaseIterable, Identifiable {
    case newest = "Newest first"
    case oldest = "Oldest first"
    case name = "Name"

    var id: String { rawValue }
}

private enum SavedCasesCategory: String, CaseIterable, Identifiable {
    case myCases = "My Cases"
    case validatedCases = "Validated Cases"
    case builtInCases = "Built-in Cases"

    var id: String { rawValue }
}

struct PropertyComparison: Identifiable, Equatable {
    let id: PropertyID
    let reference: PropertyValue?
    let compared: PropertyValue?
    let referenceDisplayValue: Double?
    let comparedDisplayValue: Double?
    let displayUnit: String?

    var difference: Double? {
        guard
            let referenceDisplayValue,
            let comparedDisplayValue,
            displayUnit != nil
        else {
            return nil
        }
        return comparedDisplayValue - referenceDisplayValue
    }
}

struct CalculationComparison: Equatable {
    let reference: CalculationRecord
    let compared: CalculationRecord
    let properties: [PropertyComparison]

    init(reference: CalculationRecord, compared: CalculationRecord) {
        self.reference = reference
        self.compared = compared

        let referenceProperties = Self.propertyMap(reference.response.properties)
        let comparedProperties = Self.propertyMap(compared.response.properties)
        let propertyIDs = Set(referenceProperties.keys).union(comparedProperties.keys)

        properties = propertyIDs
            .sorted { $0.displayName < $1.displayName }
            .map { propertyID in
                let referenceProperty = referenceProperties[propertyID]
                let comparedProperty = comparedProperties[propertyID]
                let referenceDisplay = Self.displayValue(for: referenceProperty)
                let comparedDisplay = Self.displayValue(for: comparedProperty)
                let commonUnit: String?
                if
                    let referenceUnit = referenceDisplay?.unit,
                    let comparedUnit = comparedDisplay?.unit,
                    !referenceUnit.isEmpty,
                    referenceUnit == comparedUnit
                {
                    commonUnit = referenceUnit
                } else {
                    commonUnit = nil
                }

                return PropertyComparison(
                    id: propertyID,
                    reference: referenceProperty,
                    compared: comparedProperty,
                    referenceDisplayValue: referenceDisplay?.value,
                    comparedDisplayValue: comparedDisplay?.value,
                    displayUnit: commonUnit
                )
            }
    }

    var pressureDifferenceBar: Double {
        (compared.input.pressurePa - reference.input.pressurePa) / 100_000
    }

    var temperatureDifferenceCelsius: Double {
        compared.input.temperatureK - reference.input.temperatureK
    }

    var usesSameComposition: Bool {
        let referenceComposition = Self.compositionMap(reference.request.composition)
        let comparedComposition = Self.compositionMap(compared.request.composition)
        guard Set(referenceComposition.keys) == Set(comparedComposition.keys) else {
            return false
        }
        return referenceComposition.allSatisfy { component, moleFraction in
            guard let comparedValue = comparedComposition[component] else {
                return false
            }
            return abs(moleFraction - comparedValue) <= 1e-12
        }
    }

    var comparableProperties: [PropertyComparison] {
        properties.filter { $0.difference != nil }
    }

    var nonComparableProperties: [PropertyComparison] {
        properties.filter { $0.difference == nil }
    }

    private static func displayValue(
        for property: PropertyValue?
    ) -> (value: Double, unit: String)? {
        guard
            let property,
            property.hasFiniteCalculatedValue,
            let value = property.value
        else {
            return nil
        }

        if property.property == .dynamicViscosity, property.unit == "Pa·s" {
            return (
                DynamicViscosityUnit.millipascalSecond.fromPascalSeconds(value),
                DynamicViscosityUnit.millipascalSecond.rawValue
            )
        }
        return (value, property.unit)
    }

    private static func propertyMap(
        _ properties: [PropertyValue]
    ) -> [PropertyID: PropertyValue] {
        properties.reduce(into: [:]) { result, property in
            result[property.property] = property
        }
    }

    private static func compositionMap(
        _ composition: [MixtureComponent]
    ) -> [ComponentID: Double] {
        composition.reduce(into: [:]) { result, component in
            result[component.component] = component.moleFraction
        }
    }
}

struct SavedCasesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedCalculation.updatedAt, order: .reverse)
    private var savedCases: [SavedCalculation]

    @State private var searchText = ""
    @State private var selectedCategory: SavedCasesCategory = .myCases
    @State private var sort: SavedCaseSort = .newest
    @State private var pendingDeletion: SavedCalculation?
    @State private var persistenceError: String?

    private var visibleCases: [SavedCalculation] {
        let filtered = savedCases.filter { savedCase in
            guard !searchText.isEmpty else { return true }
            return savedCase.name.localizedCaseInsensitiveContains(searchText)
                || savedCase.notes.localizedCaseInsensitiveContains(searchText)
                || savedCase.modelName.localizedCaseInsensitiveContains(searchText)
        }

        switch sort {
        case .newest:
            return filtered.sorted { $0.updatedAt > $1.updatedAt }
        case .oldest:
            return filtered.sorted { $0.updatedAt < $1.updatedAt }
        case .name:
            return filtered.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
    }

    private var visibleBuiltInCases: [BuiltInCase] {
        BuiltInCaseCatalog.cases.filter { builtInCase in
            guard !searchText.isEmpty else { return true }
            return builtInCase.name.localizedCaseInsensitiveContains(searchText)
                || builtInCase.shortDescription.localizedCaseInsensitiveContains(searchText)
                || builtInCase.modelingBasis.localizedCaseInsensitiveContains(searchText)
                || builtInCase.projectFacts.contains {
                    $0.localizedCaseInsensitiveContains(searchText)
                }
        }
    }

    private var visibleValidatedCases: [ValidatedStateOption] {
        AdvancedValidationPresentation.validatedCaseOptions().filter { validatedCase in
            guard !searchText.isEmpty else { return true }
            return validatedCase.name.localizedCaseInsensitiveContains(searchText)
                || validatedCase.detail.localizedCaseInsensitiveContains(searchText)
                || AdvancedValidationPresentation.propertyList(validatedCase.properties)
                    .localizedCaseInsensitiveContains(searchText)
        }
    }

    private var isVisibleCategoryEmpty: Bool {
        switch selectedCategory {
        case .myCases:
            visibleCases.isEmpty
        case .validatedCases:
            visibleValidatedCases.isEmpty
        case .builtInCases:
            visibleBuiltInCases.isEmpty
        }
    }

    private var batchCases: [BatchCaseInput] {
        BuiltInCaseCatalog.cases.map(BatchCaseInput.builtIn)
            + savedCases.map {
                BatchCaseInput.saved(id: $0.id, name: $0.name, record: $0.calculationRecord)
            }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isVisibleCategoryEmpty && !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List {
                        Section {
                            Picker("Saved case category", selection: $selectedCategory) {
                                ForEach(SavedCasesCategory.allCases) { category in
                                    Text(category.rawValue).tag(category)
                                }
                            }
                            .pickerStyle(.segmented)
                            .accessibilityIdentifier("saved-case-category")
                        }

                        categoryContent
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .ifeDottedBackground()
            .navigationTitle("Saved Cases")
            .searchable(text: $searchText, prompt: "Search name, notes or model")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        CaseBatchComparisonWorkflowView(cases: batchCases)
                    } label: {
                        Label("Compare", systemImage: "arrow.left.arrow.right")
                    }
                    .accessibilityIdentifier("compare-saved-cases")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Sort", systemImage: "arrow.up.arrow.down") {
                        Picker("Sort", selection: $sort) {
                            ForEach(SavedCaseSort.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                    }
                }
            }
            .confirmationDialog(
                "Delete saved case?",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let pendingDeletion {
                        delete(pendingDeletion)
                    }
                }
                Button("Cancel", role: .cancel) {
                    pendingDeletion = nil
                }
            } message: {
                Text("The saved inputs, results and provenance will be removed from this device.")
            }
            .alert(
                "Unable to update saved cases",
                isPresented: Binding(
                    get: { persistenceError != nil },
                    set: { if !$0 { persistenceError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(persistenceError ?? "")
            }
        }
    }

    @ViewBuilder
    private var categoryContent: some View {
        switch selectedCategory {
        case .myCases:
            myCasesSection
        case .validatedCases:
            validatedCasesSection
        case .builtInCases:
            builtInCasesSection
        }
    }

    private var myCasesSection: some View {
        Section("My Cases") {
            if visibleCases.isEmpty {
                Text("Run a calculation, then choose Save case.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleCases) { savedCase in
                    NavigationLink {
                        SavedCaseDetailView(savedCase: savedCase)
                    } label: {
                        SavedCaseRow(savedCase: savedCase)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button("Duplicate", systemImage: "plus.square.on.square") {
                            duplicate(savedCase)
                        }
                        .tint(.ifePrimary)
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            pendingDeletion = savedCase
                        }
                    }
                }
            }
        }
    }

    private var validatedCasesSection: some View {
        Section {
            ForEach(visibleValidatedCases) { validatedCase in
                NavigationLink {
                    ValidatedCaseDetailView(validatedCase: validatedCase)
                } label: {
                    ValidatedCaseRow(validatedCase: validatedCase)
                }
            }
        } header: {
            Text("Validated Cases")
        } footer: {
            Text("Curated reference cases are bundled with PhaseXpert and are not stored as My Cases.")
        }
    }

    private var builtInCasesSection: some View {
        Section("Built-in Cases") {
            ForEach(visibleBuiltInCases) { builtInCase in
                NavigationLink {
                    BuiltInCaseDetailView(builtInCase: builtInCase) {
                        duplicate(builtInCase)
                    }
                } label: {
                    BuiltInCaseRow(builtInCase: builtInCase)
                }
            }
        }
    }

    private func duplicate(_ savedCase: SavedCalculation) {
        modelContext.insert(savedCase.duplicate())
        saveContext()
    }

    private func duplicate(_ builtInCase: BuiltInCase) {
        guard builtInCase.hasCalculationPreset else {
            persistenceError = "This built-in project entry does not include a calculation preset."
            return
        }
        do {
            let savedCase = try SavedCalculation(
                name: "\(builtInCase.name) — Copy",
                notes: builtInCaseDuplicationNotes(for: builtInCase),
                record: builtInCase.inputSnapshotRecord()
            )
            modelContext.insert(savedCase)
            saveContext()
        } catch {
            modelContext.rollback()
            persistenceError = error.localizedDescription
        }
    }

    private func delete(_ savedCase: SavedCalculation) {
        modelContext.delete(savedCase)
        pendingDeletion = nil
        saveContext()
    }

    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            persistenceError = error.localizedDescription
        }
    }
}

private struct ValidatedCaseRow: View {
    let validatedCase: ValidatedStateOption

    var body: some View {
        VStack(alignment: .leading, spacing: IFESpacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Text(validatedCase.name)
                    .font(.headline)
                    .lineLimit(2)
                Spacer(minLength: IFESpacing.small)
                Label("Validated", systemImage: "checkmark.shield")
                    .font(.caption)
                    .foregroundStyle(Color.pxSuccess)
                    .labelStyle(.titleAndIcon)
            }
            Text("\(number(validatedCase.pressurePa / 100_000)) bar(a) · \(number(validatedCase.temperatureK - 273.15)) °C")
                .font(.subheadline.monospacedDigit())
            Text(compositionLabel(validatedCase.composition))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text("Validated: \(AdvancedValidationPresentation.propertyList(validatedCase.properties))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("validated-case-\(validatedCase.id)")
    }
}

private struct ValidatedCaseDetailView: View {
    @Environment(AppNavigationState.self) private var navigationState
    let validatedCase: ValidatedStateOption

    var body: some View {
        Form {
            Section("Validated case") {
                LabeledContent("Name", value: validatedCase.name)
                LabeledContent("Status", value: "Validated")
                Text("Curated reference case from PhaseXpert validation capability metadata.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Inputs") {
                LabeledContent("Pressure", value: "\(number(validatedCase.pressurePa / 100_000)) bar(a)")
                LabeledContent("Temperature", value: "\(number(validatedCase.temperatureK - 273.15)) °C")
                LabeledContent("Composition") {
                    Text(compositionLabel(validatedCase.composition))
                        .multilineTextAlignment(.trailing)
                }
            }

            Section("Validated properties") {
                Text(AdvancedValidationPresentation.propertyList(validatedCase.properties))
            }

            Section {
                Button("Use case", systemImage: "arrow.trianglehead.2.clockwise") {
                    navigationState.openValidatedCaseInCalculator(validatedCase)
                }
                .accessibilityIdentifier("use-validated-case-\(validatedCase.id)")
            } footer: {
                Text("Validated cases are read-only bundled reference cases. Loading a case opens it in Calculator with General Properties as the calculation model.")
            }
        }
        .navigationTitle(validatedCase.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct BuiltInCaseRow: View {
    let builtInCase: BuiltInCase

    var body: some View {
        VStack(alignment: .leading, spacing: IFESpacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Text(builtInCase.name)
                    .font(.headline)
                    .lineLimit(2)
                Spacer(minLength: IFESpacing.small)
                Label(builtInCase.label, systemImage: "lock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }
            if
                let pressurePa = builtInCase.defaultPressurePa,
                let temperatureK = builtInCase.defaultTemperatureK,
                let composition = builtInCase.composition
            {
                Text("\(number(pressurePa / 100_000)) bar(a) · \(number(temperatureK - 273.15)) °C")
                    .font(.subheadline.monospacedDigit())
                Text(compositionLabel(composition))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Label("No calculation preset", systemImage: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(builtInCase.shortDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("built-in-case-\(builtInCase.id)")
    }
}

private struct BuiltInCaseDetailView: View {
    @Environment(AppNavigationState.self) private var navigationState
    let builtInCase: BuiltInCase
    let duplicateAction: () -> Void

    var body: some View {
        Form {
            Section("Built-in case") {
                LabeledContent("Name", value: builtInCase.name)
                LabeledContent("Label", value: builtInCase.label)
                Text(builtInCase.shortDescription)
                Text("Published specifications are limits or design conditions and do not define a continuously fixed project stream.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                if builtInCase.hasCalculationPreset {
                    Button("Open in Calculator", systemImage: "arrow.trianglehead.2.clockwise") {
                        navigationState.openBuiltInCaseInCalculator(builtInCase)
                    }
                    .accessibilityIdentifier("open-built-in-\(builtInCase.id)-calculator")

                    Button("Duplicate to My Cases", systemImage: "plus.square.on.square") {
                        duplicateAction()
                    }
                    .accessibilityIdentifier("duplicate-built-in-\(builtInCase.id)")
                } else {
                    Label("Project information only", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text(builtInCase.hasCalculationPreset ? "Built-in cases are immutable presets. Duplicates become editable My Cases and are not linked to later catalog changes." : "This entry is intentionally not loadable because PhaseXpert does not fabricate project stream compositions or operating states.")
            }

            if !builtInCase.projectFacts.isEmpty {
                Section("Project facts") {
                    ForEach(builtInCase.projectFacts, id: \.self) { fact in
                        Label(fact, systemImage: "info.circle")
                    }
                }
            }

            if
                let pressurePa = builtInCase.defaultPressurePa,
                let temperatureK = builtInCase.defaultTemperatureK,
                let composition = builtInCase.composition
            {
                Section("Default inputs") {
                    LabeledContent("Pressure", value: "\(number(pressurePa / 100_000)) bar(a)")
                    LabeledContent("Temperature", value: "\(number(temperatureK - 273.15)) °C")
                    LabeledContent("Composition") {
                        Text(compositionLabel(composition))
                            .multilineTextAlignment(.trailing)
                    }
                    Text("Default inputs are PhaseXpert source-based presets, not measured operating data unless the source says so explicitly.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Default inputs") {
                    ContentUnavailableView(
                        "No Calculation Preset",
                        systemImage: "info.circle",
                        description: Text("Public sources did not provide an exact composition and operating state suitable for a thermodynamic input preset.")
                    )
                }
            }

            Section("Modeling basis") {
                Text(builtInCase.modelingBasis)
                ForEach(builtInCase.assumptions, id: \.self) { assumption in
                    Label(assumption, systemImage: "info.circle")
                }
                ForEach(builtInCase.limitations, id: \.self) { limitation in
                    Label(limitation, systemImage: "lock")
                }
            }

            Section("Sources") {
                ForEach(builtInCase.sources, id: \.url) { source in
                    Link(destination: source.url) {
                        VStack(alignment: .leading, spacing: IFESpacing.xSmall) {
                            Text(source.title)
                                .font(.headline)
                            if let dateOrVersion = source.dateOrVersion {
                                Text(dateOrVersion)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(source.url.absoluteString)
                                .font(.caption)
                                .foregroundStyle(Color.ifePrimary)
                        }
                    }
                }
            }
        }
        .navigationTitle(builtInCase.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private func builtInCaseDuplicationNotes(for builtInCase: BuiltInCase) -> String {
    ([builtInCase.label, builtInCase.modelingBasis] + builtInCase.assumptions + builtInCase.limitations)
        .joined(separator: "\n\n")
}

private func compositionLabel(_ composition: [MixtureComponent]) -> String {
    composition.map {
        "\($0.component.symbol) \(number($0.moleFraction * 100)) mol%"
    }.joined(separator: ", ")
}

private func number(_ value: Double) -> String {
    value.formatted(.number.precision(.significantDigits(1...8)))
}

extension BuiltInCase {
    func inputSnapshotRecord() -> CalculationRecord {
        guard
            let defaultPressurePa,
            let defaultTemperatureK,
            let composition
        else {
            preconditionFailure("Information-only built-in cases do not provide calculation records.")
        }
        let request = CalculationRequest(
            modelID: "phase-xpert-built-in-case-input",
            pressurePa: defaultPressurePa,
            temperatureK: defaultTemperatureK,
            composition: composition,
            requestedProperties: [],
            clientVersion: Bundle.main.releaseVersion
        )
        let descriptor = ModelDescriptor(
            id: "phase-xpert-built-in-case-input",
            name: "Built-in source-based input preset",
            modelVersion: "input-only",
            providerVersion: "PhaseXpert catalog",
            availability: .unavailable,
            calculationMode: .local,
            supportedComponents: Set(ComponentID.allCases),
            supportedProperties: [],
            domain: .initialCO2Transport,
            scientificBasis: "Provider-neutral built-in input preset. It is not a thermodynamic calculation result.",
            equationOrMethod: "No equation of state evaluated",
            limitations: ["Not a provider calculation.", label],
            references: sources.map {
                SourceReference(
                    authors: "Source publication",
                    title: $0.title,
                    year: $0.referenceYear,
                    doiOrURL: $0.url.absoluteString
                )
            }
        )
        return CalculationRecord(
            request: request,
            input: CalculationInputSnapshot(
                pressureValue: defaultPressurePa / 100_000,
                pressureUnit: .bara,
                pressurePa: defaultPressurePa,
                temperatureValue: defaultTemperatureK - 273.15,
                temperatureUnit: .celsius,
                temperatureK: defaultTemperatureK,
                originalComposition: composition.map {
                    CompositionInputSnapshot(
                        component: $0.component,
                        value: $0.moleFraction * 100,
                        unit: .molePercent
                    )
                },
                normalizedComposition: nil
            ),
            response: CalculationResponse(
                requestID: request.requestID,
                model: descriptor,
                phase: .unknown,
                properties: [],
                solver: SolverMetadata(
                    method: "No provider calculation",
                    converged: false,
                    durationMilliseconds: 0
                ),
                warnings: [label, "This duplicated case is an editable input snapshot, not a validated thermodynamic result."],
                isScientificResult: false
            ),
            application: Bundle.main.applicationIdentity
        )
    }
}

private extension BuiltInCaseSource {
    var referenceYear: Int {
        guard let dateOrVersion else { return 2026 }
        return Int(dateOrVersion.prefix(4)) ?? 2026
    }
}

private struct SavedCaseComparisonView: View {
    let savedCases: [SavedCalculation]
    @State private var referenceID: UUID
    @State private var comparedID: UUID
    @State private var exportArtifacts: [ReportingExportArtifact] = []
    @State private var exportError: String?

    init(savedCases: [SavedCalculation]) {
        self.savedCases = savedCases
        _referenceID = State(initialValue: savedCases.first?.id ?? UUID())
        _comparedID = State(initialValue: savedCases.dropFirst().first?.id ?? UUID())
    }

    private var referenceCase: SavedCalculation? {
        savedCases.first { $0.id == referenceID }
    }

    private var comparedCase: SavedCalculation? {
        savedCases.first { $0.id == comparedID }
    }

    private var comparison: CalculationComparison? {
        guard
            let reference = referenceCase?.calculationRecord,
            let compared = comparedCase?.calculationRecord
        else {
            return nil
        }
        return CalculationComparison(reference: reference, compared: compared)
    }

    var body: some View {
        Form {
            Section {
                ScientificStatusBanner(
                    title: "Comparison is not an accuracy assessment",
                    message: "Differences are compared case minus reference case. They do not establish which model or result is more accurate."
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section("Cases") {
                Picker("Reference case", selection: $referenceID) {
                    ForEach(savedCases) { savedCase in
                        Text(savedCase.name).tag(savedCase.id)
                    }
                }
                Picker("Compared case", selection: $comparedID) {
                    ForEach(savedCases) { savedCase in
                        Text(savedCase.name).tag(savedCase.id)
                    }
                }
            }

            if let comparison {
                comparisonSections(comparison)
                Section {
                    Button {
                        prepareComparisonExport(comparison)
                    } label: {
                        Label("Prepare searchable PDF and CSV", systemImage: "doc.badge.arrow.up")
                    }
                    .accessibilityIdentifier("export-saved-case-comparison")
                    ForEach(exportArtifacts) { artifact in
                        comparisonShareLink(for: artifact)
                    }
                } header: {
                    Text("Export comparison")
                } footer: {
                    Text("Both files preserve compared-minus-reference semantics, immutable calculation identifiers, units, statuses, warnings and provider provenance. They do not assess model accuracy.")
                }
            } else {
                Section {
                    ContentUnavailableView(
                        "Comparison Unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text("One or both saved calculation records could not be decoded.")
                    )
                }
            }
        }
        .navigationTitle("Compare Cases")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: referenceID) { _, newValue in
            exportArtifacts = []
            if newValue == comparedID,
               let replacement = savedCases.first(where: { $0.id != newValue }) {
                comparedID = replacement.id
            }
        }
        .onChange(of: comparedID) { _, newValue in
            exportArtifacts = []
            if newValue == referenceID,
               let replacement = savedCases.first(where: { $0.id != newValue }) {
                referenceID = replacement.id
            }
        }
        .alert(
            "Unable to export comparison",
            isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
    }

    private func prepareComparisonExport(_ comparison: CalculationComparison) {
        guard let referenceCase, let comparedCase else { return }
        let reference = SavedCaseExportSnapshot(
            savedCaseID: referenceCase.id,
            name: referenceCase.name,
            notes: referenceCase.notes,
            savedAt: referenceCase.createdAt,
            lastUpdatedAt: referenceCase.updatedAt,
            calculation: comparison.reference
        )
        let compared = SavedCaseExportSnapshot(
            savedCaseID: comparedCase.id,
            name: comparedCase.name,
            notes: comparedCase.notes,
            savedAt: comparedCase.createdAt,
            lastUpdatedAt: comparedCase.updatedAt,
            calculation: comparison.compared
        )
        do {
            exportArtifacts = try ComparisonReportExporter().createArtifacts(
                for: ComparisonExportSnapshot(reference: reference, compared: compared)
            )
        } catch {
            exportArtifacts = []
            exportError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    @ViewBuilder
    private func comparisonShareLink(for artifact: ReportingExportArtifact) -> some View {
        ShareLink(item: artifact.fileURL) {
            Label(comparisonShareTitle(for: artifact.id), systemImage: comparisonShareIcon(for: artifact.id))
        }
    }

    private func comparisonShareTitle(for kind: ReportingArtifactKind) -> String {
        kind == .comparisonPDF ? "Share PDF report" : "Share CSV data"
    }

    private func comparisonShareIcon(for kind: ReportingArtifactKind) -> String {
        kind == .comparisonPDF ? "doc.richtext" : "tablecells"
    }

    @ViewBuilder
    private func comparisonSections(_ comparison: CalculationComparison) -> some View {
        Section("Operating point") {
            ComparisonValueRow(
                title: "Pressure",
                reference: "\(number(comparison.reference.input.pressurePa / 100_000)) bar(a)",
                compared: "\(number(comparison.compared.input.pressurePa / 100_000)) bar(a)",
                difference: "\(signed(comparison.pressureDifferenceBar)) bar"
            )
            ComparisonValueRow(
                title: "Temperature",
                reference: "\(number(comparison.reference.input.temperatureK - 273.15)) °C",
                compared: "\(number(comparison.compared.input.temperatureK - 273.15)) °C",
                difference: "\(signed(comparison.temperatureDifferenceCelsius)) °C"
            )
        }

        Section("Model and phase") {
            ComparisonValueRow(
                title: "Model",
                reference: modelLabel(comparison.reference),
                compared: modelLabel(comparison.compared)
            )
            ComparisonValueRow(
                title: "Model status",
                reference: comparison.reference.response.model.availability.rawValue.capitalized,
                compared: comparison.compared.response.model.availability.rawValue.capitalized
            )
            ComparisonValueRow(
                title: "Phase",
                reference: comparison.reference.response.phase.displayName,
                compared: comparison.compared.response.phase.displayName
            )
        }

        if
            !comparison.reference.response.warnings.isEmpty
                || !comparison.compared.response.warnings.isEmpty
        {
            Section("Recorded warnings") {
                ComparisonValueRow(
                    title: "Warnings",
                    reference: warningLabel(comparison.reference),
                    compared: warningLabel(comparison.compared)
                )
            }
        }

        Section("Composition") {
            ComparisonValueRow(
                title: "Mixture",
                reference: compositionLabel(comparison.reference),
                compared: compositionLabel(comparison.compared)
            )
            LabeledContent(
                "Composition match",
                value: comparison.usesSameComposition ? "Same" : "Different"
            )
        }

        if !comparison.comparableProperties.isEmpty {
            Section("Comparable properties") {
                ForEach(comparison.comparableProperties) { property in
                    PropertyComparisonView(property: property)
                }
            }
        }

        if !comparison.nonComparableProperties.isEmpty {
            Section {
                IFEExpandableRow("Unavailable or non-comparable (\(comparison.nonComparableProperties.count))") {
                    ForEach(comparison.nonComparableProperties) { property in
                        PropertyComparisonView(property: property)
                    }
                }
            } footer: {
                Text("A numerical difference is shown only when both results are finite, calculated values expressed in the same display unit.")
            }
        }

        Section("Traceability") {
            ComparisonValueRow(
                title: "Calculation ID",
                reference: comparison.reference.response.calculationID.uuidString,
                compared: comparison.compared.response.calculationID.uuidString
            )
            ComparisonValueRow(
                title: "Calculated at",
                reference: comparison.reference.response.calculatedAt.formatted(
                    .dateTime.year().month().day().hour().minute().second()
                ),
                compared: comparison.compared.response.calculatedAt.formatted(
                    .dateTime.year().month().day().hour().minute().second()
                )
            )
        }
    }

    private func modelLabel(_ record: CalculationRecord) -> String {
        "\(record.response.model.name) \(record.response.model.modelVersion)"
    }

    private func compositionLabel(_ record: CalculationRecord) -> String {
        record.request.composition.map {
            "\($0.component.symbol) \(number($0.moleFraction * 100)) mol%"
        }.joined(separator: ", ")
    }

    private func warningLabel(_ record: CalculationRecord) -> String {
        record.response.warnings.isEmpty
            ? "None recorded"
            : record.response.warnings.joined(separator: " ")
    }

    private func number(_ value: Double) -> String {
        guard value.isFinite else { return "Invalid" }
        return value.formatted(.number.precision(.significantDigits(1...8)))
    }

    private func signed(_ value: Double) -> String {
        guard value.isFinite else { return "Invalid" }
        if value > 0 { return "+\(number(value))" }
        if value < 0 { return "−\(number(abs(value)))" }
        return number(value)
    }
}

private struct ComparisonValueRow: View {
    let title: String
    let reference: String
    let compared: String
    var difference: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            LabeledContent("Reference", value: reference)
            LabeledContent("Compared", value: compared)
            if let difference {
                LabeledContent("Difference", value: difference)
                    .foregroundStyle(Color.ifePrimary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PropertyComparisonView: View {
    let property: PropertyComparison

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(property.id.displayName)
                .font(.headline)
            LabeledContent("Reference", value: display(property.reference, property.referenceDisplayValue))
            LabeledContent("Compared", value: display(property.compared, property.comparedDisplayValue))
            if let difference = property.difference, let unit = property.displayUnit {
                LabeledContent("Difference", value: "\(signed(difference)) \(unit)")
                    .foregroundStyle(Color.ifePrimary)
            } else {
                Text("No numerical difference available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func display(_ property: PropertyValue?, _ displayValue: Double?) -> String {
        guard let property else { return "Not requested" }
        guard let displayValue, let unit = displayUnit(for: property) else {
            return property.hasFiniteCalculatedValue
                ? "Unit mismatch"
                : property.status.displayName
        }
        return "\(number(displayValue)) \(unit)"
    }

    private func displayUnit(for property: PropertyValue) -> String? {
        if property.property == .dynamicViscosity, property.unit == "Pa·s" {
            return DynamicViscosityUnit.millipascalSecond.rawValue
        }
        return property.unit.isEmpty ? nil : property.unit
    }

    private func number(_ value: Double) -> String {
        value.formatted(.number.precision(.significantDigits(1...8)))
    }

    private func signed(_ value: Double) -> String {
        if value > 0 { return "+\(number(value))" }
        if value < 0 { return "−\(number(abs(value)))" }
        return number(value)
    }
}

private struct SavedCaseRow: View {
    let savedCase: SavedCalculation

    var body: some View {
        VStack(alignment: .leading, spacing: IFESpacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Text(savedCase.name)
                    .font(.headline)
                    .lineLimit(2)
                Spacer(minLength: IFESpacing.small)
                Text(savedCase.updatedAt, format: .dateTime.year().month().day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("\(number(savedCase.pressureBarAbsolute)) bar(a) · \(number(savedCase.temperatureCelsius)) °C")
                .font(.subheadline.monospacedDigit())
            if let record = savedCase.calculationRecord {
                Text(SavedCaseNameFormatter.compositionLabel(for: record.request.composition))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(AdvancedValidationPresentation.savedCaseStatus(for: record))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .accessibilityIdentifier("saved-case-validation-status")
            } else {
                Text("Stored record unavailable")
                    .font(.caption)
                    .foregroundStyle(Color.pxUnavailable)
            }
            HStack(spacing: IFESpacing.small) {
                IFEStatusBadge(
                    text: savedCase.modelName,
                    systemImage: "cpu",
                    color: .secondary
                )
                if savedCase.calculationRecord?.response.model.availability == .preliminary {
                    IFEStatusBadge(
                        text: "Preliminary",
                        systemImage: "exclamationmark.triangle",
                        color: .pxWarning
                    )
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func number(_ value: Double) -> String {
        value.formatted(.number.precision(.significantDigits(1...6)))
    }
}

private struct SavedCaseDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigationState.self) private var navigationState

    let savedCase: SavedCalculation
    @State private var isEditing = false
    @State private var isExporting = false
    @State private var isConfirmingDeletion = false
    @State private var persistenceError: String?

    var body: some View {
        Form {
            Section("Saved case") {
                LabeledContent("Name", value: savedCase.name)
                if !savedCase.notes.isEmpty {
                    LabeledContent("Notes") {
                        Text(savedCase.notes)
                            .multilineTextAlignment(.trailing)
                    }
                }
                LabeledContent("Saved", value: savedCase.createdAt.formatted(
                    .dateTime.year().month().day().hour().minute()
                ))
                LabeledContent("Last updated", value: savedCase.updatedAt.formatted(
                    .dateTime.year().month().day().hour().minute()
                ))
            }

            if let record = savedCase.calculationRecord {
                Section {
                    Button("Open in Calculator", systemImage: "arrow.trianglehead.2.clockwise") {
                        navigationState.editAndRerun(record)
                    }
                    Button("Duplicate", systemImage: "plus.square.on.square") {
                        modelContext.insert(savedCase.duplicate())
                        saveContext()
                    }
                    Button("Export case", systemImage: "square.and.arrow.up") {
                        isExporting = true
                    }
                    .accessibilityIdentifier("export-saved-case")
                } footer: {
                    Text("Opening a case preserves the saved result. Rerunning uses the model currently installed in PhaseXpert and creates a new calculation record.")
                }

                CalculationResultSections(record: record)
            } else {
                Section {
                    ContentUnavailableView(
                        "Saved Result Unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text("The stored calculation record could not be decoded. It has not been altered.")
                    )
                }
            }
        }
        .navigationTitle(savedCase.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Case actions", systemImage: "ellipsis.circle") {
                    Button("Edit name and notes", systemImage: "pencil") {
                        isEditing = true
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        isConfirmingDeletion = true
                    }
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            EditSavedCaseSheet(savedCase: savedCase) {
                saveContext()
            }
        }
        .sheet(isPresented: $isExporting) {
            SavedCaseExportView(savedCase: savedCase)
        }
        .confirmationDialog(
            "Delete \(savedCase.name)?",
            isPresented: $isConfirmingDeletion,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                modelContext.delete(savedCase)
                saveContext()
                if persistenceError == nil {
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the saved case from this device.")
        }
        .alert(
            "Unable to update saved case",
            isPresented: Binding(
                get: { persistenceError != nil },
                set: { if !$0 { persistenceError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(persistenceError ?? "")
        }
    }

    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            persistenceError = error.localizedDescription
        }
    }
}

private struct EditSavedCaseSheet: View {
    @Environment(\.dismiss) private var dismiss

    let savedCase: SavedCalculation
    let onSave: () -> Void
    @State private var name: String
    @State private var notes: String

    init(savedCase: SavedCalculation, onSave: @escaping () -> Void) {
        self.savedCase = savedCase
        self.onSave = onSave
        _name = State(initialValue: savedCase.name)
        _notes = State(initialValue: savedCase.notes)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Case name", text: $name)
                TextField("Description or notes", text: $notes, axis: .vertical)
                    .lineLimit(3...8)
            }
            .navigationTitle("Edit Saved Case")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        savedCase.updateMetadata(name: name, notes: notes)
                        onSave()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
