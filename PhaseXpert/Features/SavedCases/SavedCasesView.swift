import Foundation
import PhaseXpertCore
import SwiftData
import SwiftUI

enum SavedRecordIssue: Error, Equatable {
    case unsupportedVersion(Int)
    case corrupt

    var message: String {
        switch self {
        case .unsupportedVersion(let version):
            return "Stored record unavailable: unsupported record format version \(version)."
        case .corrupt:
            return "Stored record unavailable: the saved data could not be read."
        }
    }
}

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
        if case .success(let record) = decodedRecord { return record }
        return nil
    }

    /// Why the stored record cannot be shown, or `nil` when it decodes.
    var recordIssue: SavedRecordIssue? {
        if case .failure(let issue) = decodedRecord { return issue }
        return nil
    }

    private var decodedRecord: Result<CalculationRecord, SavedRecordIssue> {
        guard recordFormatVersion == 1 else {
            return .failure(.unsupportedVersion(recordFormatVersion))
        }
        do {
            return .success(try JSONDecoder().decode(CalculationRecord.self, from: recordData))
        } catch {
            return .failure(.corrupt)
        }
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

enum NameSortDirection: String, CaseIterable, Identifiable {
    case ascending
    case descending

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .ascending: "Name A–Z"
        case .descending: "Name Z–A"
        }
    }
}

enum MyCasesSort: String, CaseIterable, Identifiable {
    case newest
    case oldest
    case nameAscending
    case nameDescending

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .newest: "Newest"
        case .oldest: "Oldest"
        case .nameAscending: "Name A–Z"
        case .nameDescending: "Name Z–A"
        }
    }
}

enum SavedCaseOrdering {
    static func savedCases(
        _ cases: [SavedCalculation],
        sort: MyCasesSort,
        locale: Locale
    ) -> [SavedCalculation] {
        cases.sorted { lhs, rhs in
            switch sort {
            case .newest:
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            case .oldest:
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
            case .nameAscending:
                return nameComesBefore(lhs.name, id: lhs.id.uuidString, rhs.name, id: rhs.id.uuidString, direction: .ascending, locale: locale)
            case .nameDescending:
                return nameComesBefore(lhs.name, id: lhs.id.uuidString, rhs.name, id: rhs.id.uuidString, direction: .descending, locale: locale)
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    static func validatedCases(
        _ cases: [ValidatedStateOption],
        direction: NameSortDirection,
        locale: Locale
    ) -> [ValidatedStateOption] {
        cases.sorted {
            nameComesBefore($0.name, id: $0.id, $1.name, id: $1.id, direction: direction, locale: locale)
        }
    }

    static func builtInCases(
        _ cases: [BuiltInCase],
        direction: NameSortDirection,
        locale: Locale
    ) -> [BuiltInCase] {
        cases.sorted {
            nameComesBefore($0.name, id: $0.id, $1.name, id: $1.id, direction: direction, locale: locale)
        }
    }

    private static func nameComesBefore(
        _ lhsName: String,
        id lhsID: String,
        _ rhsName: String,
        id rhsID: String,
        direction: NameSortDirection,
        locale: Locale
    ) -> Bool {
        let comparison = lhsName.compare(
            rhsName,
            options: [.caseInsensitive, .numeric],
            range: nil,
            locale: locale
        )
        guard comparison != .orderedSame else { return lhsID < rhsID }
        return direction == .ascending
            ? comparison == .orderedAscending
            : comparison == .orderedDescending
    }
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

/// Confirms that a built-in, validated or saved case was copied into My Cases.
private struct DuplicateNotice: Identifiable, Equatable {
    let id = UUID()
    let name: String
}

private extension View {
    func duplicateNoticeAlert(
        _ notice: Binding<DuplicateNotice?>,
        showInMyCases: @escaping () -> Void
    ) -> some View {
        alert(
            "Case duplicated",
            isPresented: Binding(
                get: { notice.wrappedValue != nil },
                set: { if !$0 { notice.wrappedValue = nil } }
            ),
            presenting: notice.wrappedValue
        ) { _ in
            Button("Show in My Cases") { showInMyCases() }
            Button("OK", role: .cancel) {}
        } message: { notice in
            Text("“\(notice.name)” was added to My Cases.")
        }
    }
}

/// The same three actions on every saved, validated and built-in case.
private struct CaseActionsSection: View {
    let footer: LocalizedStringKey
    let openIdentifier: String
    let duplicateIdentifier: String
    let exportIdentifier: String
    let open: () -> Void
    let duplicate: () -> Void
    let export: () -> Void

    var body: some View {
        Section {
            Button("Open in Calculator", systemImage: "arrow.trianglehead.2.clockwise", action: open)
                .buttonStyle(.ifeFilled)
                .ifeActionRow()
                .accessibilityIdentifier(openIdentifier)
            Button("Duplicate", systemImage: "plus.square.on.square", action: duplicate)
                .buttonStyle(.ifeTonal)
                .ifeActionRow()
                .accessibilityIdentifier(duplicateIdentifier)
            Button("Export case", systemImage: "square.and.arrow.up", action: export)
                .buttonStyle(.ifeTonal)
                .ifeActionRow()
                .accessibilityIdentifier(exportIdentifier)
        } footer: {
            Text(footer)
        }
    }
}

struct SavedCasesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @Environment(AppNavigationState.self) private var navigationState
    @Query(sort: \SavedCalculation.updatedAt, order: .reverse)
    private var savedCases: [SavedCalculation]

    @State private var searchText = ""
    @State private var selectedCategory: SavedCasesCategory = .myCases
    @State private var myCasesSort: MyCasesSort = .newest
    @State private var validatedCasesSort: NameSortDirection = .ascending
    @State private var builtInCasesSort: NameSortDirection = .ascending
    @State private var pendingDeletion: SavedCalculation?
    @State private var persistenceError: String?
    @State private var duplicateNotice: DuplicateNotice?

    private var visibleCases: [SavedCalculation] {
        let filtered = savedCases.filter { savedCase in
            guard !searchText.isEmpty else { return true }
            return savedCase.name.localizedCaseInsensitiveContains(searchText)
                || savedCase.notes.localizedCaseInsensitiveContains(searchText)
                || savedCase.modelName.localizedCaseInsensitiveContains(searchText)
        }

        return SavedCaseOrdering.savedCases(filtered, sort: myCasesSort, locale: locale)
    }

    private var matchingBuiltInCases: [BuiltInCase] {
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

    /// Loadable presets, ordered by the selected sort.
    private var visibleBuiltInCases: [BuiltInCase] {
        SavedCaseOrdering.builtInCases(
            matchingBuiltInCases.filter(\.hasCalculationPreset),
            direction: builtInCasesSort,
            locale: locale
        )
    }

    /// Entries with no calculation preset; listed last, in catalog order, outside the sort.
    private var visibleInformationOnlyCases: [BuiltInCase] {
        matchingBuiltInCases.filter { !$0.hasCalculationPreset }
    }

    private var visibleValidatedCases: [ValidatedStateOption] {
        let filtered = AdvancedValidationPresentation.validatedCaseOptions().filter { validatedCase in
            guard !searchText.isEmpty else { return true }
            return validatedCase.name.localizedCaseInsensitiveContains(searchText)
                || validatedCase.detail.localizedCaseInsensitiveContains(searchText)
                || AdvancedValidationPresentation.propertyList(validatedCase.properties)
                    .localizedCaseInsensitiveContains(searchText)
        }
        return SavedCaseOrdering.validatedCases(filtered, direction: validatedCasesSort, locale: locale)
    }

    private var isVisibleCategoryEmpty: Bool {
        switch selectedCategory {
        case .myCases:
            visibleCases.isEmpty
        case .validatedCases:
            visibleValidatedCases.isEmpty
        case .builtInCases:
            visibleBuiltInCases.isEmpty && visibleInformationOnlyCases.isEmpty
        }
    }

    private var batchCases: [BatchCaseInput] {
        BuiltInCaseCatalog.cases.map(BatchCaseInput.builtIn)
            + savedCases.map {
                BatchCaseInput.saved(id: $0.id, name: $0.name, record: $0.calculationRecord)
            }
    }

    private var listOrderingIdentity: String {
        switch selectedCategory {
        case .myCases:
            "my-cases-\(myCasesSort.id)"
        case .validatedCases:
            "validated-cases-\(validatedCasesSort.id)"
        case .builtInCases:
            "built-in-cases-\(builtInCasesSort.id)"
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
                            .listRowInsets(
                                EdgeInsets(
                                    top: IFESpacing.small,
                                    leading: IFESpacing.medium,
                                    bottom: IFESpacing.small,
                                    trailing: IFESpacing.medium
                                )
                            )
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .accessibilityIdentifier("saved-case-category")
                        }

                        categoryContent
                    }
                    .id(listOrderingIdentity)
                    .listStyle(.plain)
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
                        switch selectedCategory {
                        case .myCases:
                            Picker("Sort", selection: $myCasesSort) {
                                ForEach(MyCasesSort.allCases) { option in
                                    Text(option.title).tag(option)
                                }
                            }
                        case .validatedCases:
                            Picker("Sort", selection: $validatedCasesSort) {
                                ForEach(NameSortDirection.allCases) { option in
                                    Text(option.title).tag(option)
                                }
                            }
                        case .builtInCases:
                            Picker("Sort", selection: $builtInCasesSort) {
                                ForEach(NameSortDirection.allCases) { option in
                                    Text(option.title).tag(option)
                                }
                            }
                        }
                    }
                    .accessibilityIdentifier("saved-cases-sort")
                }
            }
            .duplicateNoticeAlert($duplicateNotice) {
                selectedCategory = .myCases
            }
            // A centred alert that names the case; a confirmation dialog anchors to the
            // list instead of the swiped row.
            .alert(
                "Delete \(pendingDeletion?.name ?? "")?",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                presenting: pendingDeletion
            ) { savedCase in
                Button("Delete", role: .destructive) {
                    delete(savedCase)
                }
                Button("Cancel", role: .cancel) {
                    pendingDeletion = nil
                }
            } message: { _ in
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
                VStack(spacing: IFESpacing.regular) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundStyle(Color.ifeViolet)
                        .accessibilityHidden(true)
                    Text("Run a calculation, then choose Save case.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button("Calculator", systemImage: "function") {
                        navigationState.selectedTab = .calculator
                    }
                    .buttonStyle(.ifeTonal)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, IFESpacing.large)
            } else {
                ForEach(visibleCases) { savedCase in
                    NavigationLink {
                        SavedCaseDetailView(savedCase: savedCase)
                    } label: {
                        SavedCaseRow(savedCase: savedCase)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button("Duplicate", systemImage: "plus.square.on.square") {
                            noteDuplicate(duplicate(savedCase))
                        }
                        .tint(.ifePrimary)
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            pendingDeletion = savedCase
                        }
                    }
                    .ifeCardListRow()
                }
            }
        }
    }

    private var validatedCasesSection: some View {
        Section {
            ForEach(visibleValidatedCases) { validatedCase in
                NavigationLink {
                    ValidatedCaseDetailView(
                        validatedCase: validatedCase,
                        duplicate: { duplicate(validatedCase) },
                        showInMyCases: { selectedCategory = .myCases }
                    )
                } label: {
                    ValidatedCaseRow(validatedCase: validatedCase)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button("Duplicate", systemImage: "plus.square.on.square") {
                        noteDuplicate(duplicate(validatedCase))
                    }
                    .tint(.ifePrimary)
                }
                .ifeCardListRow()
            }
        } header: {
            Text("Validated Cases")
        } footer: {
            Text("Curated reference cases are bundled with PhaseXpert and are not stored as My Cases.")
        }
    }

    @ViewBuilder
    private var builtInCasesSection: some View {
        Section("Built-in Cases") {
            ForEach(visibleBuiltInCases) { builtInCase in
                builtInCaseLink(builtInCase)
            }
        }
        if !visibleInformationOnlyCases.isEmpty {
            Section("Project information only") {
                ForEach(visibleInformationOnlyCases) { builtInCase in
                    builtInCaseLink(builtInCase)
                }
            }
        }
    }

    private func builtInCaseLink(_ builtInCase: BuiltInCase) -> some View {
        NavigationLink {
            BuiltInCaseDetailView(
                builtInCase: builtInCase,
                duplicate: { duplicate(builtInCase) },
                showInMyCases: { selectedCategory = .myCases }
            )
        } label: {
            BuiltInCaseRow(builtInCase: builtInCase)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if builtInCase.hasCalculationPreset {
                Button("Duplicate", systemImage: "plus.square.on.square") {
                    noteDuplicate(duplicate(builtInCase))
                }
                .tint(.ifePrimary)
            }
        }
        .ifeCardListRow()
    }

    private func noteDuplicate(_ name: String?) {
        if let name { duplicateNotice = DuplicateNotice(name: name) }
    }

    /// Each `duplicate` returns the new case's name, or nil when nothing was added.
    private func duplicate(_ savedCase: SavedCalculation) -> String? {
        let copy = savedCase.duplicate()
        modelContext.insert(copy)
        return saveContext() ? copy.name : nil
    }

    private func duplicate(_ builtInCase: BuiltInCase) -> String? {
        guard builtInCase.hasCalculationPreset else {
            persistenceError = "This built-in project entry does not include a calculation preset."
            return nil
        }
        return insertCopy(
            name: "\(builtInCase.name) — Copy",
            notes: builtInCaseDuplicationNotes(for: builtInCase),
            record: builtInCase.inputSnapshotRecord()
        )
    }

    private func duplicate(_ validatedCase: ValidatedStateOption) -> String? {
        insertCopy(
            name: "\(validatedCase.name) — Copy",
            notes: validatedCase.duplicationNotes,
            record: validatedCase.inputSnapshotRecord()
        )
    }

    private func insertCopy(name: String, notes: String, record: CalculationRecord) -> String? {
        do {
            let savedCase = try SavedCalculation(name: name, notes: notes, record: record)
            modelContext.insert(savedCase)
            return saveContext() ? savedCase.name : nil
        } catch {
            modelContext.rollback()
            persistenceError = error.localizedDescription
            return nil
        }
    }

    private func delete(_ savedCase: SavedCalculation) {
        modelContext.delete(savedCase)
        pendingDeletion = nil
        saveContext()
    }

    @discardableResult
    private func saveContext() -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            persistenceError = error.localizedDescription
            return false
        }
    }
}

private struct ValidatedCaseRow: View {
    let validatedCase: ValidatedStateOption

    var body: some View {
        HStack(alignment: .top, spacing: IFESpacing.regular) {
        IFERowIcon(systemImage: "checkmark.shield", tint: .ifeGreen)
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
                .ifePill()
            Text(compositionLabel(validatedCase.composition))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text("Validated: \(AdvancedValidationPresentation.propertyList(validatedCase.properties))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("validated-case-\(validatedCase.id)")
    }
}

/// Pressure, temperature and composition of a case as a tinted summary.
private struct CaseStateHero: View {
    let pressureBar: Double
    let temperatureCelsius: Double
    let composition: String
    let tint: Color

    var body: some View {
        IFEHeroCard(tint: tint) {
            VStack(alignment: .leading, spacing: IFESpacing.regular) {
                HStack(spacing: IFESpacing.regular) {
                    IFEMetricTile(
                        title: "Pressure",
                        value: format(pressureBar),
                        unit: "bar(a)",
                        tint: .ifeCard
                    )
                    IFEMetricTile(
                        title: "Temperature",
                        value: format(temperatureCelsius),
                        unit: "°C",
                        tint: .ifeCard
                    )
                }
                Text(composition)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(format(pressureBar)) bar(a), \(format(temperatureCelsius)) °C, \(composition)"
        )
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.significantDigits(1...6)))
    }
}

private struct ValidatedCaseDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppNavigationState.self) private var navigationState
    let validatedCase: ValidatedStateOption
    let duplicate: () -> String?
    let showInMyCases: () -> Void
    @State private var duplicateNotice: DuplicateNotice?
    @State private var isExporting = false

    var body: some View {
        Form {
            Section {
                CaseStateHero(
                    pressureBar: validatedCase.pressurePa / 100_000,
                    temperatureCelsius: validatedCase.temperatureK - 273.15,
                    composition: compositionLabel(validatedCase.composition),
                    tint: .ifeBlue
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            CaseActionsSection(
                footer: "Validated cases are read-only bundled reference cases. Opening a case loads it in Calculator with General Properties as the calculation model. A duplicate becomes an editable My Case.",
                openIdentifier: "use-validated-case-\(validatedCase.id)",
                duplicateIdentifier: "duplicate-validated-case-\(validatedCase.id)",
                exportIdentifier: "export-validated-case-\(validatedCase.id)",
                open: { navigationState.openValidatedCaseInCalculator(validatedCase) },
                duplicate: { if let name = duplicate() { duplicateNotice = DuplicateNotice(name: name) } },
                export: { isExporting = true }
            )

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
                if validatedCase.references.isEmpty {
                    Label("No source recorded", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.pxWarning)
                }
                ForEach(Array(validatedCase.references.enumerated()), id: \.offset) { _, reference in
                    SourceReferenceRow(reference: reference)
                }
            } header: {
                Text("Validation sources")
            } footer: {
                Text("Publications behind the formulation that validates this state.")
            }
        }
        .navigationTitle(validatedCase.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isExporting) {
            SavedCaseExportView(
                name: validatedCase.name,
                notes: validatedCase.duplicationNotes,
                inputSnapshot: validatedCase.inputSnapshotRecord()
            )
        }
        .duplicateNoticeAlert($duplicateNotice) {
            showInMyCases()
            dismiss()
        }
    }
}

/// A publication with a link when a DOI or URL is recorded.
private struct SourceReferenceRow: View {
    let reference: SourceReference

    var body: some View {
        if let link = reference.doiOrURL, let url = URL(string: link) {
            Link(destination: url) { content(link: link) }
        } else {
            content(link: nil)
        }
    }

    private func content(link: String?) -> some View {
        VStack(alignment: .leading, spacing: IFESpacing.xSmall) {
            Text(reference.title)
                .font(.headline)
            Text("\(reference.authors) (\(String(reference.year)))")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let link {
                Text(link)
                    .font(.caption)
                    .foregroundStyle(Color.ifePrimary)
            }
        }
    }
}

private struct BuiltInCaseRow: View {
    let builtInCase: BuiltInCase

    var body: some View {
        HStack(alignment: .top, spacing: IFESpacing.regular) {
        IFERowIcon(systemImage: "folder", tint: .ifeCoral)
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
                    .ifePill()
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
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("built-in-case-\(builtInCase.id)")
    }
}

private struct BuiltInCaseDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppNavigationState.self) private var navigationState
    let builtInCase: BuiltInCase
    let duplicate: () -> String?
    let showInMyCases: () -> Void
    @State private var duplicateNotice: DuplicateNotice?
    @State private var isExporting = false

    var body: some View {
        Form {
            if
                let pressurePa = builtInCase.defaultPressurePa,
                let temperatureK = builtInCase.defaultTemperatureK,
                let composition = builtInCase.composition
            {
                Section {
                    CaseStateHero(
                        pressureBar: pressurePa / 100_000,
                        temperatureCelsius: temperatureK - 273.15,
                        composition: compositionLabel(composition),
                        tint: .ifePeach
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }

            if builtInCase.hasCalculationPreset {
                CaseActionsSection(
                    footer: "Built-in cases are immutable presets. A duplicate becomes an editable My Case and is not linked to later catalog changes.",
                    openIdentifier: "open-built-in-\(builtInCase.id)-calculator",
                    duplicateIdentifier: "duplicate-built-in-\(builtInCase.id)",
                    exportIdentifier: "export-built-in-\(builtInCase.id)",
                    open: { navigationState.openBuiltInCaseInCalculator(builtInCase) },
                    duplicate: { if let name = duplicate() { duplicateNotice = DuplicateNotice(name: name) } },
                    export: { isExporting = true }
                )
            } else {
                Section {
                    Label("Project information only", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("This entry is intentionally not loadable because PhaseXpert does not fabricate project stream compositions or operating states.")
                }
            }

            Section("Built-in case") {
                LabeledContent("Name", value: builtInCase.name)
                LabeledContent("Label", value: builtInCase.label)
                Text(builtInCase.shortDescription)
                Text("Published specifications are limits or design conditions and do not define a continuously fixed project stream.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .sheet(isPresented: $isExporting) {
            if builtInCase.hasCalculationPreset {
                SavedCaseExportView(
                    name: builtInCase.name,
                    notes: builtInCaseDuplicationNotes(for: builtInCase),
                    inputSnapshot: builtInCase.inputSnapshotRecord()
                )
            }
        }
        .duplicateNoticeAlert($duplicateNotice) {
            showInMyCases()
            dismiss()
        }
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

/// An input-only record for cases that carry a defined state but no calculation.
/// It is explicitly not a scientific result: no properties, no solver, no convergence.
private func makeInputSnapshotRecord(
    modelID: String,
    modelName: String,
    providerVersion: String,
    scientificBasis: String,
    limitations: [String],
    references: [SourceReference],
    warnings: [String],
    pressurePa: Double,
    temperatureK: Double,
    composition: [MixtureComponent]
) -> CalculationRecord {
    let request = CalculationRequest(
        modelID: modelID,
        pressurePa: pressurePa,
        temperatureK: temperatureK,
        composition: composition,
        requestedProperties: [],
        clientVersion: Bundle.main.releaseVersion
    )
    let descriptor = ModelDescriptor(
        id: modelID,
        name: modelName,
        modelVersion: "input-only",
        providerVersion: providerVersion,
        availability: .unavailable,
        calculationMode: .local,
        supportedComponents: Set(ComponentID.allCases),
        supportedProperties: [],
        domain: .initialCO2Transport,
        scientificBasis: scientificBasis,
        equationOrMethod: "No equation of state evaluated",
        limitations: limitations,
        references: references
    )
    return CalculationRecord(
        request: request,
        input: CalculationInputSnapshot(
            pressureValue: pressurePa / 100_000,
            pressureUnit: .bara,
            pressurePa: pressurePa,
            temperatureValue: temperatureK - 273.15,
            temperatureUnit: .celsius,
            temperatureK: temperatureK,
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
            warnings: warnings,
            isScientificResult: false
        ),
        application: Bundle.main.applicationIdentity
    )
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
        return makeInputSnapshotRecord(
            modelID: "phase-xpert-built-in-case-input",
            modelName: "Built-in source-based input preset",
            providerVersion: "PhaseXpert catalog",
            scientificBasis: "Provider-neutral built-in input preset. It is not a thermodynamic calculation result.",
            limitations: ["Not a provider calculation.", label],
            references: sources.map {
                SourceReference(
                    authors: "Source publication",
                    title: $0.title,
                    year: $0.referenceYear,
                    doiOrURL: $0.url.absoluteString
                )
            },
            warnings: [label, "This duplicated case is an editable input snapshot, not a validated thermodynamic result."],
            pressurePa: defaultPressurePa,
            temperatureK: defaultTemperatureK,
            composition: composition
        )
    }
}

extension ValidatedStateOption {
    var duplicationNotes: String {
        [
            "Validated reference case: \(AdvancedValidationPresentation.propertyList(properties)).",
            detail,
            "This is an editable input snapshot, not a calculation result."
        ].joined(separator: "\n\n")
    }

    func inputSnapshotRecord() -> CalculationRecord {
        makeInputSnapshotRecord(
            modelID: "phase-xpert-validated-case-input",
            modelName: "Validated reference input state",
            providerVersion: "PhaseXpert validation capability metadata",
            scientificBasis: "Provider-neutral input state taken from PhaseXpert validation capability metadata. It is not a thermodynamic calculation result.",
            limitations: [
                "Not a provider calculation.",
                "Validated for: \(AdvancedValidationPresentation.propertyList(properties))."
            ],
            references: references,
            warnings: [
                "Validated reference case (\(AdvancedValidationPresentation.propertyList(properties))). This record is an input snapshot, not a calculation result."
            ],
            pressurePa: pressurePa,
            temperatureK: temperatureK,
            composition: composition
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
        HStack(alignment: .top, spacing: IFESpacing.regular) {
        IFERowIcon(systemImage: "tray.full", tint: .ifeViolet)
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
                .ifePill()
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
                Text(savedCase.recordIssue?.message ?? "Stored record unavailable")
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
    @State private var duplicateNotice: DuplicateNotice?

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
                CaseActionsSection(
                    footer: "Opening a case preserves the saved result. Rerunning uses the model currently installed in PhaseXpert and creates a new calculation record.",
                    openIdentifier: "open-saved-case",
                    duplicateIdentifier: "duplicate-saved-case",
                    exportIdentifier: "export-saved-case",
                    open: { navigationState.editAndRerun(record) },
                    duplicate: {
                        let copy = savedCase.duplicate()
                        modelContext.insert(copy)
                        saveContext()
                        if persistenceError == nil {
                            duplicateNotice = DuplicateNotice(name: copy.name)
                        }
                    },
                    export: { isExporting = true }
                )

                if AdvancedValidationPresentation.validatedProperties(for: record).isEmpty {
                    Section {
                        Link(
                            destination: IFEContactMailLink.url(
                                subject: IFEContactMailLink.validationQuoteSubject
                            )
                        ) {
                            Label("Contact IFE for a validation quote", systemImage: "envelope")
                        }
                        .accessibilityIdentifier("request-saved-case-validation-quote")
                    } header: {
                        Text("Physical validation")
                    } footer: {
                        Text("Request a quote to physically validate this saved pressure, temperature and composition in IFE's laboratories.")
                    }
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
        .duplicateNoticeAlert($duplicateNotice) {
            dismiss()
        }
        .alert(
            "Delete \(savedCase.name)?",
            isPresented: $isConfirmingDeletion
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
