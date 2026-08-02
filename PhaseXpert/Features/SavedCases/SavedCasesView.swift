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

    var body: some View {
        NavigationStack {
            Group {
                if savedCases.isEmpty {
                    ContentUnavailableView(
                        "No Saved Cases",
                        systemImage: "tray.full",
                        description: Text("Run a calculation, then choose Save case.")
                    )
                } else if visibleCases.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List {
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
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Saved Cases")
            .searchable(text: $searchText, prompt: "Search name, notes or model")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SavedCaseComparisonView(savedCases: savedCases)
                    } label: {
                        Label("Compare", systemImage: "arrow.left.arrow.right")
                    }
                    .disabled(savedCases.count < 2)
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

    private func duplicate(_ savedCase: SavedCalculation) {
        modelContext.insert(savedCase.duplicate())
        saveContext()
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
                Section("Export comparison") {
                    Button("Prepare searchable PDF and CSV", systemImage: "doc.badge.arrow.up") {
                        prepareComparisonExport(comparison)
                    }
                    .accessibilityIdentifier("export-saved-case-comparison")
                    ForEach(exportArtifacts) { artifact in
                        ShareLink(item: artifact.fileURL) {
                            Label(
                                artifact.id == .comparisonPDF ? "Share PDF report" : "Share CSV data",
                                systemImage: artifact.id == .comparisonPDF ? "doc.richtext" : "tablecells"
                            )
                        }
                    }
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
                DisclosureGroup(
                    "Unavailable or non-comparable (\(comparison.nonComparableProperties.count))"
                ) {
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
        VStack(alignment: .leading, spacing: 6) {
            Text(savedCase.name)
                .font(.headline)
            Text("\(number(savedCase.pressureBarAbsolute)) bar(a) · \(number(savedCase.temperatureCelsius)) °C")
                .font(.subheadline)
            HStack {
                Text(savedCase.modelName)
                Spacer()
                Text(savedCase.updatedAt, format: .dateTime.year().month().day())
            }
            .font(.caption)
            .foregroundStyle(.secondary)
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
                    Button("Edit inputs and rerun with current model", systemImage: "arrow.trianglehead.2.clockwise") {
                        navigationState.editAndRerun(record)
                    }
                } footer: {
                    Text("The original saved result is preserved. Rerunning uses the model currently installed in PhaseXpert.")
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
                    Button("Duplicate", systemImage: "plus.square.on.square") {
                        modelContext.insert(savedCase.duplicate())
                        saveContext()
                    }
                    Button("Export case", systemImage: "square.and.arrow.up") {
                        isExporting = true
                    }
                    .disabled(savedCase.calculationRecord == nil)
                    .accessibilityIdentifier("export-saved-case")
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
