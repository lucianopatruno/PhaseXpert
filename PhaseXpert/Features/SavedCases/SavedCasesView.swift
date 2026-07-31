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

private struct SavedCaseRow: View {
    let savedCase: SavedCalculation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(savedCase.name)
                .font(.headline)
            Text("\(number(savedCase.pressureBarAbsolute)) bar abs · \(number(savedCase.temperatureCelsius)) °C")
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
